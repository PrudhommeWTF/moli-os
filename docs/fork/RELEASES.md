# Releases du fork

Ce fork publie lui-même le binaire de Moli OS, pour l'installer dans un conteneur LXC
Proxmox sans Docker (scripts dans [`proxmox/`](../../proxmox/README.md)). Rien ici ne
touche au code de Moli ni aux workflows d'origine (`check.yml`, `audit.yml`) : la
synchronisation avec `rudy-io/moli-os` reste un simple merge.

## Ce que fait le workflow

`.github/workflows/release-fork.yml` part de chaque tag `v*` poussé :

1. vérifie le nom du tag (ci-dessous) ;
2. construit le dashboard (`web/`, `npm ci` puis `npm run build`), puis
   `node scripts/i18n-check.mjs` ;
3. lance `scripts/check.sh` dans l'image de dev (`docker/dev.Dockerfile`, Rust sur
   Alpine) : format, clippy, tests, catalogue, fuites ;
4. compile `cargo build --release --locked -p moli-os --target <arch>-unknown-linux-musl`
   dans la même image, et vérifie que le binaire est statique ;
5. démarre ce binaire comme le ferait le service : `check-config`, `serve`, `health`,
   `/api/health`, `backup`, arrêt, `restore` dans un dossier vide ;
6. publie la release GitHub, marquée « latest ».

Deux architectures, chacune compilée nativement (runners `ubuntu-24.04` et
`ubuntu-24.04-arm`) :

| Fichier | Contenu |
|---|---|
| `moli-os-linux-x86_64.tar.gz` | `moli-os`, `moli.example.toml`, `LICENSE`, `NOTICE` |
| `moli-os-linux-x86_64.tar.gz.sha256` | son empreinte SHA-256 (`sha256sum -c`) |
| `moli-os-linux-aarch64.tar.gz` | la même chose pour ARM 64 bits |
| `moli-os-linux-aarch64.tar.gz.sha256` | son empreinte |
| `moli.example.toml` | l'exemple de configuration, à part |

Une étape qui échoue arrête tout : aucune release n'est publiée à moitié.

## Le nom du tag

`v<version du workspace>-<n>` : `v0.1.0-2` (la première release de ce fork), puis
`v0.1.0-3`… La version du workspace est
celle de `[workspace.package]` dans `Cargo.toml` (aujourd'hui `0.1.0`). Quand l'amont la
change (par exemple `0.2.0`), on repart à `v0.2.0-1`. Le workflow refuse tout autre nom.

`moli-os --version` affiche la version du workspace, pas le tag : la version installée
d'un LXC est celle que retient le script (`~/.moli-os` dans le conteneur).

Pas de pré-release : les scripts Proxmox ne voient que la release marquée « latest ».
Une version de test est donc une release comme une autre ; si elle déçoit, on la
supprime (ou on publie la suivante) et les LXC reviennent en arrière comme décrit dans
[TEST-LXC.md](TEST-LXC.md).

## Publier une version

Une seule fois sur le fork : onglet **Actions**, autoriser les workflows (GitHub les
désactive sur un fork).

Ensuite, depuis une copie à jour de `main` :

```sh
git switch main && git pull --ff-only
git ls-tree --name-only HEAD .github/workflows/release-fork.yml   # doit afficher le fichier
sh scripts/check.sh                     # facultatif : la CI le refait
git tag -a v0.1.0-2 -m "Moli OS v0.1.0-2"
git push origin v0.1.0-2
```

GitHub lance le workflow tel qu'il est **dans le commit tagué**. Un tag posé sur un commit
qui n'a pas `release-fork.yml` (un `main` local pas à jour, par exemple) ne déclenche rien :
pas d'exécution dans l'onglet Actions, pas de release. Le vérifier :

```sh
git ls-tree --name-only v0.1.0-2 .github/workflows/release-fork.yml   # vide = mauvais commit
```

Suivre le workflow dans l'onglet Actions (`release-fork`), puis vérifier la release :

```sh
curl -fsSLO https://github.com/PrudhommeWTF/moli-os/releases/download/v0.1.0-2/moli-os-linux-x86_64.tar.gz
curl -fsSLO https://github.com/PrudhommeWTF/moli-os/releases/download/v0.1.0-2/moli-os-linux-x86_64.tar.gz.sha256
sha256sum -c moli-os-linux-x86_64.tar.gz.sha256
```

Un tag sur le mauvais commit, ou un workflow raté : corriger, supprimer le tag
(`git push origin :refs/tags/v0.1.0-2` et `git tag -d v0.1.0-2`), puis le reposer depuis
le bon commit. Une release déjà publiée ne se republie pas sous
le même nom : passer au numéro suivant.

## Après une synchronisation avec l'amont

```sh
git fetch upstream && git merge upstream/main   # upstream = rudy-io/moli-os
git push origin main
git tag -a v0.1.0-3 -m "Moli OS v0.1.0-3" && git push origin v0.1.0-3
```

Si l'amont touche au `Dockerfile` (nouvelle étape de build, nouvelle dépendance), relire
ce workflow : il reproduit ces étapes sans s'en servir.
