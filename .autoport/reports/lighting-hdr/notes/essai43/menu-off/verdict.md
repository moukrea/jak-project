DIRECTIVES v8aed688f73
Menu parcouru sans crash dans preuve300s ; Lighting OFF et persistanceOFF non atteints.
source=device
serial=eae4df44
binary=build-android/lib/arm64-v8a/libgk.so
sha=ab2f8019a399c9c1
started_at=2026-09-08T15:59:46Z
duration_s=313
crash=0
frames=3840
Navigation runtime : titre27→settings28→Graphics5 dans preuve ; Recharged67 après fin producteur.
Snapshots CRC/chaînes vérifiés ; menu Lighting index14, on-off2, label pointeur34031620, bool30799760=#t1375532.
Le menu initial était fermé(screen=-1,progress=#f) ; touche108 sans effet, puis tap titre après état target-title-wait.
Taps calculés sur rows abs-index et CINEVP2400x1080 ; Gtm-tap titre best2 fy0.4304 confirme calibration.
Recharged index9 a nécessité défilement : première tentative bloquée par garde absent, aucun tap erroné envoyé.
Après page67, défilement lent : dernière sélection observée6, Lighting14 hors écran.
Délai finaliseur180s après preuve expiré, restauration normale ; pas de tap Lighting, pas de seconde preuve persistance.
Snapshot graphics2 : cache companions handles(PID22,23), drivers(PID12,21), quatre ppointer[0].pid concordants.
Array static handle est pointeur brut u64, pas boxed : valeurs de title2/handle_caches mal décodées, remplacées par graphics2 pour interprétation.
Lectures start-partial: progress=#f, champs progress décodés sans objet sont invalides et ne représentent aucun état.
Restauration settings SHA78108670e26658496f33a2a0dc50c45fe16a0f2e59c774ea70499c7fefb52fd6 exacte, props initiales restaurées, PID23597stable12s.
non prouvé : LightingOFF/persistanceOFF/ombresOFF ; correction cache sur tous niveaux ; qualité/couverture HDR.
