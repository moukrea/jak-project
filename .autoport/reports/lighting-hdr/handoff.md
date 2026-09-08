DIRECTIVES vb7966a3839
## ÉTABLI
- Moteur 810a60f430 inchangé ; lib SHA256 2e6a7759c45543b4a98ffd0cdcb9e07c6ce6d75ef71320dbf682855814516316, MD5 build/device 4d5024c55ede04ab75430e22d1d3c324. Aucun build/APK neuf.
- Collecteur proof_run corrigé : PID connu disparu/changé => collecte CRASH1 immédiate ; erreur transport ignorée. 108 tests HDR passent, dont 8 nouveaux ; bash-n/diff-check 0.
- Proof officiel commencé 2026-09-08T02:48:25Z, durée 189 s, frames 4080, crash 0, hits 704154, hdr_tonemap_defects=6 ; dernier lot 20260908T024828-3604150.
- Campagne essai19-current : 44 lots, 192 paires qualifiées conservées, 168/168 cellules, 21/21 niveaux ; intérieurs/hutte complets, 16 ciels manquants Sunkenb/Swamp, quality_bad=0.
- 352 erreurs : remplacements refusés/doublons/demandes non qualifiées/3 crashs non remplacés ; chaîne rouge par mesures absentes dans ces crashs, pas de régression de rendu démontrée.
- Courbe 0/exposition 1/genou 0,95 conservés ; luma équilibrée +3,8668/255, 81 cellules plus claires/87 plus sombres. Diagnostic notes/essai20/quality-review.md.
## TENTÉ
- Swamp start 20:195:2462:63 près du dock : lot 023107-3582518 SIG11 intern_from_c avant warp ; retry 023556-3590581 SIG11/GRV-NULLFG/GOALpc 01e751fc après caméra et swa.VIS.
- Amorçage cave1 puis start : lot 024312-3599900, même famille SIG11, aucune capture ; trois crashs conservés. Ne pas répéter ces arrivées inchangées.
- Sunkenb 20:90:0:700, lot 023227-3585945 : 16 captures achromatiques, 0‰ ciel ; caméra élevée empêchant sub.VIS, LOADSCREEN-SHOW arm6 maintenu.
- Acteur trouvé : SCENECMD alive exit-chamber-1 ; level.gc:1215-1231/1253 conditionne VIS aux boîtes caméra ; target-death.gc:178-184 attend all-visible?=loading.
- Helix natif avant Start charge sub.VIS : lot 024020-3595619, 32 captures colorées, hdr_paired=16, 31 sondes ; GL1282 h00 ON après blackout-fin ; toutes paires refusées.
- Même vues, settle60/load480, lot 024828-3604150 : 32 captures, 26 sondes, six GL1282 ; aucune qualification nouvelle. L’attente prolongée n’a pas corrigé les sondes.
- Édition concurrente de proof_run : finalisation 024312 interrompue (exit2), manifeste scellé conservé et réintégré par le dernier run officiel. Ne jamais éditer le script pendant un run.
## RESTE
- Corriger le producteur GL1282/sondes Sunkenb et les crashs Swamp GRV, ou trouver des remplacements qualifiés ; ces défauts ne sont pas des échecs de contraste.
- Couvrir ciel Sunkenb/Swamp aux 8h. Le rayon géométrique ouvert Sunkenb ne suffit pas : sondes 0‰, aucune vue ciel validée.
- Conserver les 192 paires compatibles et les sources brutes ; les demandes échouées incluent désormais cave1 Swamp 8h et helix Sunkenb 8h, en plus des start 8h.
- Commandes et mappings exacts : notes/essai20/campaign-runs.jsonl. Reprendre toutes les sources échouées concernées pour éviter les doublons ; usage dans notes/essai19/usage-lots.md.
- Entrée officielle : proof_run.sh lighting-hdr device --hdr-campaign essai19-current ; --hdr-replace LOT:VUE:H=VUE. Aucun manifeste/proof écrit à la main.
- Compatibilité rendu/config stricte : un nouveau binaire n’hérite pas automatiquement des 192 paires. Ne pas rejouer 200 paires sans nécessité démontrée.
- non prouvé : calibration/résidus locaux, ciels, ordre/identité GPU, acquis complets, Filmique1, coût GPU, sortie HDR native ; collecte précoce de crash testée synthétiquement seulement.
- Redmi relancé normalement PID18928, propriétés debug vides, aucun verrou ; publieur laissé actif. Generic réservé orchestrateur, aucun owner-ok/backlog édité par worker ; backend codex pour relances.
