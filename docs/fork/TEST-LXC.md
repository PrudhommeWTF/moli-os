# Tester Moli OS dans un LXC jetable

Un essai complet sur un conteneur qu'on détruit à la fin : installation par les scripts de
[`proxmox/`](../../proxmox/README.md), vérifications, code d'installation, sauvegarde et
restauration, mise à jour, retour arrière, redémarrage, suppression. Moli n'a aucun pilote :
rien ne touche à un appareil de la maison.

Notations : `<CTID>` est le numéro du conteneur créé, `<IP>` son adresse. Les commandes
« hôte » se lancent en root sur un nœud Proxmox ; les commandes « LXC », dans le conteneur
(`pct enter <CTID>`).

## 0. Avant

1. Les scripts sont sur `main` du fork (ils y cherchent leur `install/` et leur `update`).
2. Actions est autorisé sur le fork, et une première release existe :
   `git tag -a v0.1.0-2 -m "Moli OS v0.1.0-2" && git push origin v0.1.0-2`
   (voir [RELEASES.md](RELEASES.md)). Attendu : la release `v0.1.0-2` avec ses cinq fichiers.

## 1. Installer

Hôte :

```sh
git clone --depth 1 https://github.com/PrudhommeWTF/moli-os /root/moli-os-test
dev_mode=keep bash /root/moli-os-test/proxmox/ct/moli-os.sh
```

Choisir l'installation par défaut, puis le stockage (ZFS). `dev_mode=keep` garde le
conteneur si l'installation échoue, pour lire ce qui s'est passé.

Attendu : `Completed Successfully!`, l'adresse `http://<IP>:8790`, et la commande du code
d'installation. Pas de bannière ASCII en tête : le moteur n'en a pas pour ce fork
(cosmétique).

Hôte, la forme du conteneur :

```sh
pct config <CTID> | grep -E 'unprivileged|features|memory|cores|rootfs|ostype'
```

Attendu : `unprivileged: 1`, `features: keyctl=1` (sans `nesting=1`), `memory: 256`,
`cores: 1`, un disque de 2G, `ostype: debian`.

## 2. Vérifier l'installation

LXC :

```sh
systemctl is-active moli-os                  # active
systemctl --failed --no-legend               # rien : Debian 13 vit bien sans nesting
moli-os check-config                         # configuration OK (0 driver(s))
moli-os health && echo OK                    # OK
curl -s http://127.0.0.1:8790/api/health | head -c 300; echo
cat ~/.moli-os                               # 0.1.0-2
ps -o user,rss,cmd -C moli-os                # moli, quelques Mo de RSS
stat -c '%U:%G %a %n' /etc/moli-os/master.key /var/lib/moli-os /var/lib/moli-os/moli.toml
                                             # moli:moli 600, moli:moli 750, moli:moli 640
ls /var/lib/moli-os                          # pas de master.key ici
systemctl show moli-os -p MemoryMax -p MemorySwapMax   # 134217728 et 0
cat /sys/fs/cgroup/system.slice/moli-os.service/memory.max   # 134217728
sha256sum /etc/moli-os/master.key /var/lib/moli-os/moli.toml > /root/avant.sha256
```

Si `memory.max` n'existe pas ou vaut `max`, le contrôleur mémoire n'est pas délégué au
conteneur : le plafond de 128 Mo ne joue pas (celui du LXC, 256 Mo, reste). Me le signaler.

Depuis un ordinateur du réseau : `curl -s http://<IP>:8790/api/health` répond aussi.

## 3. Le code d'installation

LXC, lu par vous seul :

```sh
journalctl -u moli-os | grep code= | tail -n 1
```

Ouvrir `http://<IP>:8790`, choisir la langue, taper le code, choisir le code de la maison
(deux fois). Attendu : le dashboard s'ouvre.

Puis, tout de suite, copier `/etc/moli-os/master.key` dans le gestionnaire de mots de passe,
sans la coller ailleurs (pas de chat, pas de ticket).

Le code ne revient plus :

```sh
systemctl restart moli-os; sleep 5
journalctl -u moli-os --since "-1min" | grep -c code=     # 0
```

## 4. Sauvegarder puis restaurer

LXC :

```sh
B=/var/backups/moli-os/test-$(date +%H%M%S)
moli-os backup "$B"                          # backup: N files in … (the master key is not in it)
cat "$B/manifest.json"
grep -rqF -f /etc/moli-os/master.key /var/backups/moli-os && echo FUITE || echo "clé absente"
systemctl stop moli-os
moli-os restore "$B" --force                 # restored N files into /var/lib/moli-os
find /var/lib/moli-os ! -user moli           # rien : aucun fichier à root
systemctl start moli-os; sleep 3; moli-os health && echo OK
```

Attendu : `clé absente`, `OK`, et dans le dashboard le code de la maison marche toujours.

## 5. Mettre à jour vers une version de test

Sur votre poste, publier la suivante :

```sh
git tag -a v0.1.0-3 -m "Moli OS v0.1.0-3" && git push origin v0.1.0-3
```

Une fois la release publiée, LXC :

```sh
update
```

Attendu, dans l'ordre : `Update available: moli-os 0.1.0-2 -> 0.1.0-3`, `Backed up Moli OS
data to /var/backups/moli-os/<date>-0.1.0-2`, `Stopped Moli OS`, `Kept the current Moli OS
binary…`, `Deployed: moli-os (0.1.0-3)`, `Started Moli OS (/api/health answers)`,
`Updated successfully!`.

```sh
cat ~/.moli-os                                   # 0.1.0-3
cat /opt/moli-os/moli-os.previous.version        # 0.1.0-2
ls /var/backups/moli-os                          # une sauvegarde de plus
sha256sum -c /root/avant.sha256                  # les deux OK : clé et moli.toml intacts
update                                           # No update available: moli-os (0.1.0-3)
```

## 6. Revenir en arrière

### À la main

LXC :

```sh
systemctl stop moli-os
cp -a /opt/moli-os/moli-os.previous /opt/moli-os/moli-os
cp -a /opt/moli-os/moli-os.previous.version ~/.moli-os
systemctl start moli-os; sleep 3; moli-os health && echo OK
cat ~/.moli-os                                   # 0.1.0-2
```

### Le retour automatique (facultatif)

Une version qui démarre sans répondre, simulée en remplaçant le programme du service, pendant
que `update` repasse à `0.1.0-3` :

```sh
mkdir -p /etc/systemd/system/moli-os.service.d
cat <<'EOF' >/etc/systemd/system/moli-os.service.d/test-panne.conf
[Service]
ExecStart=
ExecStart=/bin/sleep infinity
EOF
systemctl daemon-reload
update
```

Attendu : `Moli OS 0.1.0-3 does not answer /api/health: going back to the previous binary`,
puis `Previous Moli OS binary restored (0.1.0-2)` et la commande `restore` de la sauvegarde ;
le script sort en erreur. `cat ~/.moli-os` donne `0.1.0-2`. Retirer la panne :

```sh
rm /etc/systemd/system/moli-os.service.d/test-panne.conf
systemctl daemon-reload; systemctl restart moli-os; sleep 3; moli-os health && echo OK
```

## 7. Redémarrer le conteneur

Hôte :

```sh
pct reboot <CTID>
sleep 20
pct exec <CTID> -- systemctl is-active moli-os                     # active
pct exec <CTID> -- moli-os health && echo OK                      # OK
pct exec <CTID> -- sh -c 'journalctl -u moli-os -b | grep -c code='   # 0
```

Attendu : le dashboard est toujours là, sans redemander le code de la maison sur un
navigateur déjà reconnu.

## 8. Supprimer proprement

Hôte :

```sh
pct stop <CTID>
pct destroy <CTID> --purge --destroy-unreferenced-disks 1
rm -rf /root/moli-os-test
pct list | grep -w <CTID> || echo "conteneur parti"
zfs list -H -o name | grep -- "-<CTID>-" || echo "disques partis"
```

`--purge` retire aussi le conteneur des tâches de sauvegarde, de réplication et de HA. Les
releases de test peuvent rester (la suivante les remplace) ou être supprimées sur GitHub.
