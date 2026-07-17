# Compiler pour Linux x86-64

Cible **native, compilée en local**. Une seule commande, `./build.sh linux-x86_64`,
produit à la fois le moteur x86 et l'ensemble des CGO/DGO du jeu.

## Prérequis

- `git`, `cmake` (≥ 3.16), `ninja`, `gcc` ou `clang`, `nasm`.
- Les paquets de développement X11 / audio, identiques à la CI
  (`.github/workflows/linux-build-clang.yaml`) :

  ```
  build-essential cmake clang gcc g++ lcov make nasm \
  libxrandr-dev libxinerama-dev libxcursor-dev libpulse-dev \
  libxi-dev zip ninja-build libgl1-mesa-dev libssl-dev
  ```

- **Vos propres données de jeu extraites dans `iso_data/jak1/`** (issues de votre disque
  PS2 ; voir la doc OpenGOAL amont pour l'extraction). Elles sont requises pour produire
  les CGO/DGO et les assets. Elles n'entrent jamais dans le dépôt ni dans la CI.

## Commande

```
./build.sh linux-x86_64 \
  [--recharged-hud --grass-overhang --hd-models --vulkan-support | --yolo] \
  [--package] [--no-cache]
```

Les *feature flags* activent des fonctionnalités encore en chantier. `--yolo` active les
quatre. Sans flag, seul l'ensemble validé est inclus. Une fonctionnalité non demandée est
absente du binaire **et** des menus.

## Ce que fait la commande

- Build cmake + ninja de `build/game/gk` et `build/goalc/goalc` (backend x86).
- Compilation GOAL complète des 28 CGO/DGO du jeu vers `out/jak1/iso`.
- Plomberie des flags : génération de `goal_src/jak1/pc/recharged-flags.gc` (constantes
  GOAL, source unique de vérité côté menus) et des défines CMake `-DOG_FEAT_*`
  (côté C++).
- Marqueur de jeu de flags `ogflags:<hash>:linux-x86_64` embarqué **à la fois** dans le
  binaire et dans les CGO, `<hash>` étant le sha256 (12 hex) de la liste de flags.
- Cache CGO sous `.autoport/cgo-cache/`, indexé par le jeu de flags **et** l'empreinte des
  sources : réutilisé si rien de pertinent n'a changé (`--no-cache` force la reconstruction).

## Empaquetage (`--package`)

`--package` produit sous `out/artifacts/` :

- `app-jak1-linux-x86_64.tar.gz` — le paquet applicatif (moteur + `data/` + `iso/` + `custom/` + `run.sh`) ;
- `jak1_assets.zip` — les données pures du jeu ;
- les manifestes associés.

**Règle des deux artefacts.** Tout ce qui est identique à la sortie du pipeline OpenGOAL
d'origine va dans `jak1_assets.zip` (données pures). Tout ce que ce port modifie ou ajoute
va dans le paquet applicatif. L'archive d'assets ne bouge donc quasiment jamais d'une
version à l'autre : seul le paquet applicatif est en général à retélécharger.

## Vérification

Les builds à jeux de flags mélangés sont refusés : le marqueur du binaire et celui des CGO
doivent s'apparier (contrôle R1 fait par `deploy_verify.sh` / `release_verify.sh`).
