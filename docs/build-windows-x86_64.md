# Compiler pour Windows x86-64

**Aucune machine Windows locale n'est nécessaire.** Les binaires moteur Windows sont
produits par GitHub Actions ; l'empaquetage se fait ensuite en local sur Linux.

## Les binaires moteur viennent de la CI

Le workflow **« Port CI »** (`.github/workflows/port-ci.yaml`), job
**« Windows x86_64 artifact »**, compile `gk.exe` et `goalc.exe` avec le preset cmake
`Release-windows-clang-static`. Le runner exécute `goalc.exe --version` et vérifie le
marqueur `ogflags:` de `gk.exe` en guise de smoke test. Le résultat est publié sous
l'artefact **`opengoal-windows-port`**.

## Empaquetage local (sur Linux)

1. Récupérez l'artefact d'un run vert :

   ```
   gh run download -R moukrea/jak-project -n opengoal-windows-port -D out/ci/windows-x86_64
   ```

2. Lancez le build/empaquetage :

   ```
   ./build.sh windows-x86_64 [flags] [--package] [--win-bin-dir <dir>]
   ```

Ce que fait la commande :

- vérifie que le marqueur `ogflags:` de `gk.exe` correspond au jeu de flags demandé
  (hash par défaut `e3b0c44298fc`, c.-à-d. aucun flag) ;
- compile l'ensemble CGO x86 avec le marqueur Windows vers `out/jak1-windows/iso`, puis
  restaure l'oracle x86 ;
- avec `--package`, émet `out/artifacts/app-jak1-windows-x86_64.zip` (`gk.exe` + `data/` +
  `iso/` + `custom/` + `run.bat`) et l'archive d'assets.

`--win-bin-dir <dir>` désigne le dossier contenant `gk.exe` (défaut :
`out/ci/windows-x86_64`).

## Build natif Windows (optionnel, pour les devs sous Windows)

Presets cmake `Release-windows-clang` / `Release-windows-msvc` (voir `CMakePresets.json`),
`nasm` installé via choco.
