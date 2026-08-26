# ABSORBER `feat/recharged-managed-assets` DANS LA BRANCHE PRINCIPALE

**TOP PRIORITE owner, 2026-08-26** : « d'abord la branche dont je viens de parler à absorber
nickel (dans le framework, pas toi tout seul en autonomie) ».

## Ce que la branche apporte

`origin/feat/recharged-managed-assets` — 13 commits, 56 fichiers, +3569 / -33 lignes.
Depot d'assets associe : **`moukrea/recharged-assets`**, version epinglee `assets-v0.2.1`.

Blocs neufs :
- `common/assets/AssetManager.{h,cpp}` + `Manifest.{h,cpp}` — gestionnaire d'assets, installation
  verifiee et **reprenable**.
- `common/util/RPack.{h,cpp}` — conteneur de pack.
- `common/util/Ktx2Subset.{h,cpp}` — **KTX2**, donc textures compressees GPU pretes a televerser.
- `common/util/AssetsLock.{h,cpp}` + `assets.lock.json` — verrouillage de version.
- `android/.../AssetPackDownloader.java` (413 lignes) — telechargement au premier lancement.
- `gk --assets status/install/verify` en ligne de commande, profil GPU detecte par le renderer,
  bascule « HD TEXTURE PACK » dans le menu recharged, `scripts/packaging/package_release.sh`.
- Tests : `test_asset_manager.cpp`, `test_rpack_ktx2.cpp`, fixture `.rpack`.

## Pourquoi c'est la priorite 1

Mesure du 2026-08-26 sur la Shield : les textures de remplacement sont des **PNG 2048x2048 decodes
a chaque chargement**, quatre cartes par materiau (base, `_normal`, `_roughness`, `_height`). Huit
etapes de texture sur 107 concentrent 94 % d'un demarrage de 11,5 s. Consequence rapportee par
l'owner : « le logo apparait bien apres le son qui est sense etre la au moment de son apparition
[...] C'est je crois le pire truc honnetement ».

**KTX2 supprime le decodage** (le GPU consomme le format directement) et divise l'occupation VRAM
par 4 a 8. Cette branche porte donc deja le correctif que la phase de pre-calcul allait construire.

## Etat de la fusion

- Base commune : `26b26029d9`. Notre branche a **1065 commits** en plus, la sienne **13**.
- **16 fichiers touches des deux cotes** : `android/android_gfx.cpp`, `android/CMakeLists.txt`,
  `android/gk_android_main.cpp`, `game/graphics/gfx.h`, `background_common.cpp`, `Tie3.cpp`,
  `CustomTextureReplacements.{h,cpp}`, `Loader.cpp`, `LoaderStages.cpp`, `kmachine.cpp`,
  `.gitignore`, `hud-classes-pc.gc`, `pckernel.gc`, et 3 autres.
- Attention particuliere sur `Loader.cpp` : il porte deja nos ajouts `A50-LEVRAM` (mesure RAM par
  niveau), `A51-FR3` (tailles compressee/decompressee) et la liberation des tangentes apres
  televersement. **Ces mesures doivent survivre a la fusion** : ce sont elles qui instruisent les
  deux phases suivantes.

## Contraintes

- **Fusionner, pas ecraser.** Aucun de nos 1065 commits ne doit etre perdu ; resoudre chaque
  conflit en gardant les deux intentions, et le justifier.
- L'arbre doit compiler pour les DEUX cibles : x86 desktop ET arm64 Android.
- Les tests apportes par la branche (`test_asset_manager`, `test_rpack_ktx2`) doivent passer.
- Assets HD derives des dumps Jak2/Jak3 : jamais dans l'APK, le binaire ou git — le telechargement
  gere est justement la bonne voie.
- **Stockage disponible sur la Shield** : l'owner y a monte une cle USB adoptee comme stockage
  interne, `/mnt/expand/ff091cb1-80aa-46c6-ac14-283ecb0574c0`, **114 Go libres**. Plus aucune
  contrainte de place ; ne pas dimensionner les packs sur l'ancienne limite de 2,7 Go.
