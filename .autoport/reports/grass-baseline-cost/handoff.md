DIRECTIVES v07b292c21f
## ETABLI (mesure)
CLAUSE 1 DEVENUE UN TERME (commit e3d55c6fbe). « au MEME vantage » n'etait juge par rien : dix
cellules sous dix points de vue passaient vertes. Deux termes le jugent, relus dans la table par
`autoport_proof::read_text` (neuf ; troncature = echec, pas prefixe) : `..._vantage_spread_mm`
(10 cellules, seuil 100 mm) et `..._camera_spread_dm` (5 cellules ON, seuil 1 dm), chacun avec sa
population a cote et un `-` — jamais 0 — sous deux cellules comparables.
Course a blanc x86 (notes/dry-run-x86-essai9.txt, aucun fichier de preuve touche) : gaps 199 -> 0,
vantage_cells=10, camera_cells=5, ecarts 0 et 0, cells_short=0. Sans les deux termes le premier
gaps aurait valu 197 : ils MORDENT. Arbres batis par leur porte ; l'APK porte le libgk de l'arbre
(md5 6f1a86f039b3e3e86497f3113361f1e9). APPAREIL USB PRESENT DEPUIS 16:24 : eae4df44 usb:1-6
Redmi_Note_9_Pro — l'empechement de l'essai 8 (aucun appareil) n'existe plus.
## TENTE, et pourquoi ca a echoue
LA COURSE N'A PAS PU DEMARRER : TELEPHONE EN DIRECT BOOT, PIN jamais saisi depuis son demarrage
de 16:24. Grandeurs relues, pas deduites :
  dumpsys user  -> Started users state: [0=RUNNING_LOCKED]
  dumpsys trust -> deviceLocked=1, strongAuthRequired=0x1 (AFTER_BOOT)
  logcat        -> ActivityTaskManager: aInfo is null ... com.miui.securitycenter/
                   ...AdbInstallActivity ; PKMSImpl: MIUILOG- ... Install canceled by user
L'activite de confirmation MIUI n'est pas directBootAware : elle n'existe pas avant le PIN. LES
DEUX chemins rendent ce refus — `adb install` (garde binaire, 16:24:07, code 6) et
`pm install -r -d -t -i com.android.vending` apres push (16:26:11), celui que
device-validate.sh:230 annonce a tort comme keyguard-independent. Les 4 reglages MIUI sont poses
et ne changent rien. Ecran reveille, alerte ntfy envoyee, attente de 1700 s armee.
## RESTE
1. DEVERROUILLER LE TELEPHONE UNE FOIS (PIN) : seul geste manquant, aucun code ne le remplace.
   Controle : `adb shell dumpsys user | grep "Started users state:"` doit rendre RUNNING_UNLOCKED.
2. Puis `bash .autoport/lib/proof_run.sh grass-baseline-cost device`. Rien d'autre a preparer.
3. NE PAS rebatir sur « le telephone porte <autre md5> » : le binaire est bon, c'est l'INSTALL qui
   est refuse (FINDINGS). Echec le plus probable ensuite : throttling sur high/very_high, derniers.
