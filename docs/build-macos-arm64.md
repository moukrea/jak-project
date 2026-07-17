# Compiler pour macOS ARM64

Cible **meilleur effort, CI uniquement** : aucune application empaquetée n'est produite, et
il n'existe pas de machine mac locale dans ce projet.

## Ce que fait la CI

Le workflow **« Port CI »** (`.github/workflows/port-ci.yaml`), job **`macos_arm64`**,
compile `gk` et `goalc` avec le preset cmake `Release-macos-arm64-clang` sur un runner
**macos-15 (Apple Silicon)**. Il exécute `goalc --version` en guise de smoke test, puis
publie les binaires sous l'artefact **`opengoal-macos-arm-port`**.

## Pas de guide d'installation

Aucune application macOS empaquetée n'est produite, donc il n'existe pas de guide
d'installation pour cette plateforme. Le support macOS amont n'est pas touché par ce fork
(l'audit de portabilité n'a trouvé aucune régression `APPLE` introduite par le fork).

Les contributions pour un vrai paquet macOS sont les bienvenues.
