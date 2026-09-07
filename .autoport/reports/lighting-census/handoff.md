# Handoff — lighting-census, essai 7
DIRECTIVES v6fca51fe40
## ÉTABLI
- Code moteur checkpointé par builder : 0a589b258c ; build final OK, binaire 5eeed592dba35c6b.
- Preuve fraîche armée 180 s : crash=0, frames=10320, draws=4374701, residual=0, rb_mismatch=0.
- Phase ORIGINE-LUMIÈRE publiée : lc_orig_light_un=1282703 ; timings GPU publiés.
- Plan moteur : 672 étapes (28 vues × 8 heures × 3 jeux), contre 564 auparavant.
- Preuve courte : 47 étapes comparées, refset_replay_maxdiff=254, census_replay_runs=0.
- Ancienne capture complète (refset/refset-capture.log) : 21 niveaux, 13 intérieurs, sky_missing=8.
- Les huit couples manquants sont sunkenb, tous à 0‰ ; aucune impossibilité générale établie.
- 572 PNG du plan neuf inchangés par SHA256 ; 564 de la dernière capture, 8 antérieurs non qualifiés.
- Notes : references-manquantes-essai7.txt (100 fichiers), references-hors-derniere-capture-essai7.txt (8).
- Ablation 120 s : crash=0, frames=6836, armed=0 hits=0 ; builder2541075 repris (Ss).

## TENTÉ
- Course armée interrompue à 106 s pour corriger ETIE sans shade(), auparavant classé A.
- Trace interrompue archivée notes/essai7-interrompu-proof.txt (crash=1 vient de notre SIGTERM).
- Correction host_paths : shade/legacy distincts, bypass sans textures ; aucun shader modifié.
- Porte renforcée uniquement pour census : couverture, configuration, cinq rejeux armés stricts.
- Pas de tournée complète répétée : la capture antérieure a coûté ~38 min, incompatible avec le budget minutes.
- Ne pas reprendre l’ancien handoff essai5 : settle livré=180/600, pas 1200 ; données plus récentes en notes.

## RESTE
- Trouver un cadrage de sunkenb satisfaisant ≥150‰ de ciel sans retirer ce niveau de la liste moteur.
- Établir les 108 étapes supplémentaires du plan ; les 8 PNG antérieurs ne suffisent pas comme provenance.
- Protéger les origines existantes ; préparer les nouvelles références séparément avant toute adoption.
- Résoudre le coût de la tournée avant cinq rejeux complets ; ne pas lancer une campagne de plusieurs heures.
- Refaire la preuve complète par lib/proof_run.sh ; generic.sh appartient à l’orchestrateur.
- Non prouvé : bit-identité des deux origines, couverture et absence de régression sur tous les niveaux.
- Examiner les erreurs glReadBuffer GL_FRONT/GL_BACK du log ; fiabilité complète de capture non prouvée.
