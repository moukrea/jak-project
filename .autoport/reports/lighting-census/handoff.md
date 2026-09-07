# Handoff — lighting-census, essai 12
DIRECTIVES v6fca51fe40
## ÉTABLI
- Corrigé hdr.cpp : préserver programme/VAO/array buffer après tonemap_draw.
- Cause GL : Sprite3:679 appelle UI puis écrit uniforms SPRITE3 avec programme TONEMAP.
- Build incrémental code0 ; garde npc-flicker47 ; sha1aed1e5494ac62fa.
- Preuve unique150s : crash0 frames8393 tonemap_draws2389 ; GL_INVALID_OPERATION7290→0.
- 575 références intactes ;24 PNG identiques essai11 ; origine/h00 maxdiff202/diffpx794.
- 37/672 comparaisons ; maxdiff254, census_replay_runs0, coverage_missing244.
- Draws3427130 residual0 rb_mismatch0 ; GPU7.3219ms diagnostic inclus.
- Sunkenb-vis SUB.DGO2796608octets = raw_obj ; SHA4af61081b37f3acc887e8661c5342f91763102b3760f58ac3f04d1ef64039680.
- BSP adgifs0x29ff04,9 entrées : sky00..07 et clouds,tpage162 ; ciel non absent des données.
- Source capturée par builder3c911bd6ca après run ; PID2541075 repris Ss ; aucun appareil.
## TENTÉ
- Fix producteur GL enlève les erreurs mesurées, mais ne change aucun des24 PNG legacy.
- Audit état : aucun delta causal hutlamp/start/pad_replay/reseed identifié depuis89db5b7d8a.
- Init rand-vu puis accumulation float ; reseed après start ne restaure pas acteur résident.
- Phase/RNG init, naissance, suite des pas, joint3/matrices et ressources historiques absents.
- Ni gel/reseed arbitraire, ni nouveau harnais/recapture ; aucune attribution causale lampe obtenue.
- Piste ciel Sunkenb sans adgifs réfutée CPU ; présence textures ne prouve pas visibilité.
## RESTE
- Reconstituer état historique de la lampe ou faire arbitrer ce blocage de données ; pas nouveau run identique.
- Restaurer état complet par cas ; préfixe564/suffixe108 et capture_lf ne restaurent que l'agenda.
- Établir108 références séparées ; sidecars existants sans provenance CGO/DGO/FR3 complète.
- Conserver8 manques Sunkenb : conditions GOAL/bucket exécuté/occlusion encore non mesurés.
- non prouvé : bit-identité564,cinq rejeux,couverture globale,état par cas,qualité HDR/Android.
- Notes diagnostic-essai12.md,test-essai12.md,summary-essai12.json,sunkenb-essai12.md.
- Prochaine preuve seulement via proof_run.sh ; generic.sh inchangé, laissé à l'orchestrateur.
