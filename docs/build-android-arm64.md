# Compiler pour Android ARM64

Cible **native, compilée en local**. Une seule commande, `./build.sh android-arm64`,
produit la `libgk.so` ARM64, l'ensemble des CGO ARM64 et l'APK.

## Prérequis

- Tout ce que demande la [compilation Linux x86-64](build-linux-x86_64.md) (les mêmes
  outils, et `iso_data/jak1/` avec vos données de jeu).
- **Android NDK r27c** et **gradle** (disposition sous `~/Android`). Chargez l'environnement
  avec `source .autoport/lib/android-env.sh`, qui exporte `ANDROID_NDK_HOME` et compagnie.
- Un **JDK** pour gradle.
- **Deux arbres goalc pré-compilés** :
  - `build/goalc/goalc` — backend x86, sert d'oracle ;
  - `build-arm64/goalc/goalc` — backend ARM64, un build hôte configuré avec
    `-DGOALC_BACKEND=arm64`.

## Commande

```
./build.sh android-arm64 [flags] [--no-apk] [--package]
```

Les *feature flags* sont les mêmes que pour les autres cibles (`--recharged-hud`,
`--grass-overhang`, `--hd-models`, `--vulkan-support`, ou `--yolo`).

## Ce que fait la commande

- Build cmake NDK de `libgk.so` (`arm64-v8a`, `android-29`).
- Compilation de l'ensemble CGO ARM64, mis en scène sous `out/jak1-arm64-full/iso`, puis
  restauration de l'oracle x86.
- gradle `assembleJak1Debug` empaquette le zip des CGO et le pack custom dans l'APK.
- Preuve d'appariement R1 : le marqueur `ogflags:` de la `libgk.so` de l'APK doit être égal
  à celui du pack CGO.

## Empaquetage (`--package`)

`--package` produit sous `out/artifacts/` :

- `app-jak1-android-arm64.apk` — l'APK slim vérifié ;
- l'archive d'assets `jak1_assets.zip` (données pures du jeu).

La **règle des deux artefacts** est la même que pour la [cible Linux](build-linux-x86_64.md) :
données pures dans l'archive d'assets, tout ce que le port modifie/ajoute dans l'application.

## Installation sur appareil

```
adb install -i com.android.vending <apk>
```
