# Handoff — lighting-census, essai 31
DIRECTIVES v6fca51fe40
## ÉTABLI
- Dernier rewarp corrigé sur origine/h00, baseline ET candidat : restore ancre2102/due2104/executed2104, sample2282, captured1/slip0.
- Deux runs75s via proof_run : baseline4150frames SHA b6059dcd2f155540 ; candidat4182frames SHA bfdc96edc613e5f6 ; crash0 chacun.
- Même bootstrap17 rejoué5880/79fb964dc17507ec, sans recapture ni ajout au flux ; PNJ47 PASS dans les deux builds gk incrémentaux.
- Delta3fichiers : requête ancre+2 après dernier warp, listener levels puis display, premier vantage/REQUIRE_LOADED seulement.
- Timing manqué/slot occupé refusés ; gardes capture inchangées ; fingerprint guard ON restore-plus2-v2, historique OFF préservé.
- Baseline isolée /home/emeric/code/jak-lighting-baseline au a9ea15a69062a57335278db7680cd647df3c1e1d, renderer/shaders séparés.
- Patch COMPLET31fichiers actualisé : notes/essai31-postwarp/full-baseline.patch ; postwarp.patch est le delta commun de cet essai.
- Checkpoint réel origine/h00/chain-lf2282 : mêmes4FR3/756ISO/486objets/787textures ; shaders106vs108,95communs.
- CAM(80octets caméra+12position Jak) bit-identique sur180frames LF2104..2283, ancre pad3 dans les deux bras.
- Quatre réglages portables SHA identiques et inchangés ; sidecars config8f2a7e6fadebd324/data56f0364a8789c816/inputf97b073c2df76fb4 communs.
- 575SHA historiques intacts ; deux sorties neuves .autoport/refset-candidates/essai31-{baseline,candidate}-postwarp, NON qualifiées.
- Logs/proofs/manifestes/CAM conservés notes/essai31-postwarp/{baseline-postwarp,postwarp}/ ; postload-comparison.txt détaille les limites.
## TENTÉ
- Réapplication immédiate après start exclue par code : target-death suspend AVANT reset des demandes ; +2 exécuté et chargé mesurés.
- Empreintes PNG différentes ; aucune comparaison de pixels/qualification lancée, car autres acteurs/RNG/config effective non attestés.
- loaded_ready1 et levels actifs ; loaded_pending résiduel car autoport_proof::publish_text ignore le vide, pas erreur de la garde capture.
- v2 reste missing-state-and-baseline ; compared0 et absence de refset_replay_maxdiff ne valent jamais zéro ; generic non exécuté.
## RESTE
- Apparier état des AUTRES acteurs/RNG/config effective APRÈS chargement ; bootstrap scellé et CAM ne le prouvent pas (voir research.md).
- Seulement ensuite qualifier origine baseline/candidat ; ne pas refaire construction baseline, bootstrap ou audit des exports/FR3.
- Trois modes/21niveaux/8heures/≥4intérieurs/ciel≥15%, Sunkenb manquant, puis5rejeux exacts et adoption distincte contrôlée restent à faire.
- Tous21niveaux non comparés ; le cas h00 ne couvre que village1/beach, ciel0‰/sky_missing16 ; HDR/SDR/Android/owner-ok non prouvés.
- Réutiliser builds existants et runner notes/essai31-postwarp/run-arm.sh <worktree> <baseline|candidate> <cycle-neuf> (75s, pas archive).
- Runner sélectionne/restaure proof_env sous lock ; builder2541075 vérifié idle puis suspendu/repris par trap. Aucun démon/appareil lancé.
