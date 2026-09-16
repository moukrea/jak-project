DIRECTIVES v07b292c21f

## ÉTABLI (mesuré)
Instrument LIVRÉ : `game/system/grass_baseline.{h,cpp}`, campagne 10 cellules (5 paliers x ON/OFF)
sur le patron `perf_baseline`. `build_x86.sh` rc=0, `build_arm64.sh --dir build-android` rc=0, APK
rebâti, `libgk.so` de l'APK md5-identique à `build-android/lib/arm64-v8a/libgk.so`.
Course à blanc x86 (notes/smoke3-x86.log, n'a PAS touché proof.txt) : `GRASS-BASELINE done
cells=10 short=0`, `grass_baseline_gaps=0`. Le critère de la porte est donc TENU par l'instrument
de bout en bout — reste à le produire sur l'appareil, seul bras qui ferme l'item.
Chiffres d'août CONFIRMÉS sur le binaire courant : `dead_instances=110472`,
`built_instances=726851` (7,07 Mo de VBO d'instances jamais dessinés).
Contraste falsifiable : cellule ON `render_frames=300` contre OFF `render_frames=0`, même
instrument. Aucun test de frustum n'existait dans GrassRenderer ; celui-ci rejoue `world_to_clip`
(grass.vert:81-98) et publie `frustum_behind`, qui rend sa convention de signe falsifiable.
Item épinglé : `proof_timeout` 420 -> 1800 ; `proof_props` = level.warp=training-start,
perf.buckets=1, recharged=1, uncap.fps=240.

## TENTÉ, et pourquoi ça a échoué
Preuve APPAREIL impossible : aucun appareil USB de tout l'essai (`pick_device.sh` exit 3, `adb
devices` vide, veilleur en fond jamais déclenché). `proof.txt` n'a pas été reproduit et celui de
l'essai 1 n'a pas été réutilisé. Bras `--off` non lancé, même cause.
Deux défauts de MON code trouvés par la course à blanc, corrigés avant qu'ils comptent :
`close_cell` lisait `g_state_frames` après sa remise à zéro par `enter_state(kCensus)` ; et les
témoins ne sortaient qu'aux fermetures, donc une course tronquée aurait dit `state=0`.

## RESTE
1. Brancher l'USB puis `lib/proof_run.sh grass-baseline-cost device`. Rien d'autre à préparer.
2. Optionnel (contrat, pas le validateur) : `... device --off --timeout 240` -> `armed=0 hits=0`.
3. NE PAS rééditer game/ common/ android/ goal_src/ après la course : le validateur refuse une
   preuve plus vieille que ses sources moteur.
4. Cellule sous 300 images -> lire `cells_short` ; `kMeasureMaxSeconds`=220 s vise 4,6 img/s.
