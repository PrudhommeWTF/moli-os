# Moli OS dans un LXC Proxmox (Community Scripts)

Trois fichiers au format [Community Scripts](https://community-scripts.org/docs), qui
installent le binaire publié par ce fork ([docs/fork/RELEASES.md](../docs/fork/RELEASES.md))
dans un conteneur LXC non privilégié, sans Docker :

| Fichier | Rôle |
|---|---|
| `ct/moli-os.sh` | lancé sur l'hôte Proxmox : crée le conteneur ; dans le conteneur, `update_script` met à jour |
| `install/moli-os-install.sh` | lu par l'hôte et exécuté dans le conteneur : binaire, utilisateur, configuration, clé, service |
| `json/moli-os.json` | les métadonnées (site web de Community Scripts ; inutilisé à l'exécution) |

Plan de test complet : [docs/fork/TEST-LXC.md](../docs/fork/TEST-LXC.md).

## Lancer

Depuis l'hôte Proxmox, en root :

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/PrudhommeWTF/moli-os/main/proxmox/ct/moli-os.sh)"
```

ou depuis une copie du dépôt :

```sh
git clone --depth 1 https://github.com/PrudhommeWTF/moli-os && bash moli-os/proxmox/ct/moli-os.sh
```

Défauts : Debian 13, non privilégié, 1 CPU, 256 Mo, 2 Go, sans nesting. Le mode avancé du
script permet de les changer.

## Comment le moteur trouve ces fichiers

Le moteur (`community-scripts/core`, téléchargé à chaque lancement) remonte depuis
`ct/moli-os.sh` jusqu'au premier dossier qui contient `ct/` et `install/` : ce dossier,
`proxmox/`. Il y lit `install/moli-os-install.sh` (le nom vient de `APP="Moli-OS"`, mis en
minuscules). Comme `proxmox/` n'est pas la racine d'un dépôt git, il ne déduit pas l'adresse
du remote : il prend `_CS_DEFAULT_URL`, ligne 2 de `ct/moli-os.sh`, qui pointe vers la
branche `main` de ce fork. C'est cette adresse que garde la commande `update` du conteneur.

Pour essayer une autre branche, la donner au moteur :

```sh
export COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/PrudhommeWTF/moli-os/<branche>/proxmox
bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/moli-os.sh")"
```

## Ce qu'il y a dans le conteneur

| Chemin | Contenu | Propriétaire, droits |
|---|---|---|
| `/opt/moli-os/moli-os` | le binaire (statique, musl) | root, 0755 |
| `/opt/moli-os/moli-os.previous` (+ `.version`) | le binaire d'avant la dernière mise à jour | root |
| `/var/lib/moli-os/` | le dossier de données (`data_dir`) : `moli.toml`, coffre, historique… | `moli:moli`, 0750 |
| `/etc/moli-os/master.key` | la clé maître du coffre, créée une seule fois | `moli:moli`, 0600 |
| `/var/backups/moli-os/` | les sauvegardes faites avant chaque mise à jour | `moli:moli`, 0750 |
| `/etc/systemd/system/moli-os.service` | le service (`Restart=always`, `MemoryMax=128M`) | root |
| `/usr/local/bin/moli-os` | lance `moli-os` en tant que `moli`, avec la config et la clé du service | root, 0755 |
| `~/.moli-os` (root) | la version installée, tenue par le moteur | root |

- `moli-os <commande>` dans le shell root du conteneur : `check-config`, `backup`,
  `restore`, `secrets set` (toujours par un tube) passent par le wrapper. Donner des
  chemins absolus : la commande tourne en `moli`.
- Le code d'installation (premier démarrage, une heure) : `journalctl -u moli-os | grep code=`.
- La clé maître n'est jamais dans `moli-os backup`, mais elle est sur le même disque que
  le coffre : les sauvegardes du conteneur (vzdump, PBS), ses snapshots ZFS et sa
  réplication la contiennent. En garder une copie dans un gestionnaire de mots de passe.

## Mise à jour (`update` dans le conteneur)

`update_script` ne fait rien si la release « latest » est déjà installée. Sinon :

1. `moli-os backup /var/backups/moli-os/<date>-<version>` ;
2. arrêt du service, copie du binaire en `moli-os.previous` ;
3. `fetch_and_deploy_gh_release` (sans nettoyage du dossier) ;
4. démarrage, puis 30 s pour que `moli-os health` (`/api/health`) réponde ;
5. pas de réponse : le binaire `.previous` et sa version reviennent, le service redémarre,
   le script sort en erreur et donne la commande `restore` de la sauvegarde.

Il ne touche jamais à `/etc/moli-os/master.key` ni à `/var/lib/moli-os/moli.toml`.

## Écarts au standard Community Scripts

Ces scripts restent dans ce dépôt ; s'ils devaient un jour être proposés à
`community-scripts/DevScripts`, voici ce qu'un relecteur relèverait, et pourquoi c'est ainsi :

- **Un utilisateur `moli`, et `runuser` dans le wrapper** (leurs règles 9, 12 et 31 : tout en
  root). Moli est conçu pour ne pas tourner en root (l'image officielle tourne en
  `1000:1000`), et la clé maître ne doit pas être lisible par d'autres processus.
- **`_CS_DEFAULT_URL` vers ce fork** au lieu de `DevScripts` : c'est là que vivent les scripts.
- **Les sauvegardes dans `/var/backups/moli-os`** et non `/opt/moli-os.backup` (réservé à
  `create_backup`) : ce sont des sauvegardes de Moli (`moli-os backup`), pas des copies de
  fichiers de configuration.
- **`var_arm64` non décidé** : la release contient un binaire aarch64, mais aucun conteneur
  arm64 ne l'a encore fait tourner ; le moteur demande donc confirmation sur un hôte ARM.
- **Pas de vérification du `.sha256`** à l'installation : `fetch_and_deploy_gh_release` n'en
  fait pas, et la refaire à côté serait du téléchargement « maison » (leur règle 2). Le
  téléchargement passe par HTTPS depuis GitHub ; l'empreinte sert à une vérification à la main.
