# Handoff — lighting-census, essai 32
DIRECTIVES v6fca51fe40
## ÉTABLI
- Deux runs75s via proof_run : baseline707b0ed69313e8b2/4152frames, candidat5e7dd4684802aebe/4161frames ; crash0 chacun.
- Bootstrap17 scellé5880/79fb964dc17507ec rejoué sans ajout ; restore2104 et sample origine/h00 LF2282/slip0 dans les deux bras.
- POSTLOAD LF2281/2282 :3449records chaque, octets tous égaux ;94processus présents observés par bloc, six témoins RNG dont2mt19937 complets.
-11champs pc-settings et40options réellement transmises au renderer identiques ; master_active0,320x180,MSAA1.
- CAM/Jak92octets identiques sur180frames LF2104..2283 ; ancre pad3 des deux côtés.
- Au sample : mêmes4FR3/756ISO/486objets/787textures ; shaders106vs108. Quatre fichiers réglages inchangés et identiques.
- Comparaison hors ligne NEUVE par tools/refset_compare.py : origine/h00 maxdiff71,diffpx190,bbox[77,110,105,143] ; aucune qualification/adoption.
- Baseline isolée a9ea15a69062a57335278db7680cd647df3c1e1d préservée ; full-baseline.patch et delta postload.patch dans notes/essai32-postload/.
- Six fichiers modifiés : sinks bootstrap réutilisés vers pad trace postdispatch + options effectives ; PNJ47 garde build tenue dans les deux.
-575SHA historiques intacts ; refs neuves essai32-baseline-baseline (copie identique dans HEAD et worktree isolé) et essai32-candidate-candidate (HEAD), non qualifiées.
- Logs/proofs/CAM/POSTLOAD/manifeste conservés notes/essai32-postload/{baseline,candidate}/ ; state-comparison.txt et data-comparison.txt.
## TENTÉ
- Observation postload ciblée réussie ; aucun tirage/restauration RNG ajouté, flux bootstrap/gardes capture/provenance v2 inchangés.
- Premier build a refusé display_fps_cap absent baseline : retiré du relevé commun, puis builds gk incrémentaux réussis.
- Le delta71/190 persiste malgré tous les états OBSERVÉS égaux ; poses articulées/états privés et uniformes par draw ne sont pas attestés.
- Recherche ciblée : merc2 shaders identiques ; Merc2.cpp diff ROI inactif, Shader.cpp recensement passif + tonemap. Aucune cause démontrée.
- Les lecteurs relèvent après dispatch, pas pendant construction DMA : ne pas transformer cette limite en qualification automatique.
- Captures seulement : refset_replay_maxdiff absent, compared0 ne vaut pas zéro ; generic non exécuté.
## RESTE
- Localiser le delta NEUF71/190 ; exploiter ROI existant (OG_REFSET_TRACE_ROI) pour identifier draw/modèle, voir renderer-research.md et ses limites.
- Ne pas refaire bootstrap, baseline, audits exports/FR3, ni acteurs/RNG/config observés désormais appariés ; ne pas rejouer l’archive maxdiff195.
- Qualifier indépendamment origine baseline/candidat après résolution des limites ; aucune adoption sur simple égalité des snapshots partiels.
- Trois modes/21niveaux/8heures/≥4intérieurs/ciel≥15%, Sunkenb manquant, puis5rejeux exacts restent non prouvés ; HDR/SDR/Android également.
- Runner notes/essai32-postload/run-arm.sh <worktree> <baseline|candidate> <cycle-NEUF> réutilisable (build gk incrémental puis75s).
- proof_env restaurés sous lock ; builder2541075 repris après chaque bras, aucun démon/appareil lancé ; pas de nouvelle campagne dans cet essai.
