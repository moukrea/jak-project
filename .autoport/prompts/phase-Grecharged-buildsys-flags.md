## WORK ECONOMY: MANAGER plans/verifies; delegate bulk edits/builds. ONE task at a time.
## READ FIRST: .autoport/plans/build-system-pillar.md (the thought-out architecture) — follow it.

# Phase Grecharged-buildsys-flags (P1 of the owner's TOP-PRIORITY build-system pillar)

## Owner pitch (2026-07-17, verbatim extract — the pillar's why)
"Il faut qu'on utilise des feature flags lors des builds, comme des arguments de commande... --recharged-hud
(pas fini) --grass-overhang (horrible) --hd-models (garbled, useless en l'état) --vulkan-support (juste une
entrée menu inutile)... si lors du build ces arguments ne sont pas fournis, alors le build ne contiendra
tout simplement pas les features... un argument bonus pour inclure toutes les features flagged d'un coup
genre --yolo. Ça produira des builds plus clean avec moins de menus pétés et des trucs half-baked."
Plus: "qu'on puisse facilement build, en ligne de commande, pour tout ce que supportait déjà OpenGOAL et
pour ARM Android... en embarquant absolument toutes les améliorations qu'on a faites (on a caché des
éléments de menus pour le build ARM Android, faut les garder pour les builds Windows et Linux)."

## Deliverables
1. ONE build CLI: ./build.sh <linux-x86_64|android-arm64> [--recharged-hud] [--grass-overhang]
   [--hd-models] [--vulkan-support] [--yolo] — wraps the full per-target pipeline (cmake+goalc+gradle).
2. DUAL flag plumbing from that single source: (a) CMake defines -> C++/#ifdef excludes renderer/menu C++
   paths; (b) GENERATED goal_src/jak1/pc/recharged-flags.gc defconstants -> GOAL menu rows of off
   features are NOT COMPILED (no hidden rows — absent). Same mechanism generates *platform-android* so
   Android-hidden menu items REMAIN on desktop builds (orthogonal dimension).
3. CGO cache + deploy_verify/release_verify keyed by the FLAG-SET HASH (risk R1: no mixed flag builds).
4. Proofs: default build (no flags) on linux + android = binaries AND menus contain none of the 4
   features (grep symbols + menu capture); --yolo build contains all 4; desktop keeps the
   Android-hidden rows; device boots default build clean (spot-check 90s); validated features (grass
   base/precompute/shadow/AO) present in BOTH.
Report RESULT + flag matrix table. Max: max_turns 3000, max_retries 6.
