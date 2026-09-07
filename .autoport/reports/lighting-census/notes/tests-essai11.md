# Vérifications — essai 11
DIRECTIVES v6fca51fe40
Build et runner réussis ; divergence legacy inchangée, provenance runtime non exercée.
- Commande : cmake --build build --target gk -j6 ; code0, build-essai11.log.
- Commande UNIQUE : OG_REFSET_TRACE_ROI=1 bash .autoport/lib/proof_run.sh lighting-census x86 --timeout 150 ; code0.
- Wrapper run-essai11.sh code0 ; session-essai11.log, proof-run-essai11.log.
- SHA256 gk : 82b403292cbf2cec4d460ec7cb5515a5ef46494da3bd06f87a81adab25636f6f.
- Archives proof/log/24 PNG essai10 : essai10-avant11/ ; aucun champ de preuve édité.
- 575 chemins et SHA avant essai11 identiques essai10 ; contrôle après run575/575 OK, code0.
- refs-before-essai11.sha256, refs-preflight-essai11.log, refs-check-essai11.log.
- Builder2541075 vérifié idle (unique enfant sleep2924992), aucun verrou/compilateur avant STOP parent.
- Trap EXIT CONT exécuté ; parent repris Ss, enfant sleep2929771 observé ; aucun appareil.
- Preuve produite535 lignes, une ligne source=x86 (aucune ligne littérale SOURCE).
- SHA256 proof.txt : f7d4b9e2d3def8581b0eda6a84891d4b834e4f1d51dddacd3311911505485c8d.
Huit lignes exactes du producteur :
duration_s=150
crash=0
frames=8399
refset_compared=37
refset_provenance_checked=0
refset_provenance_bad=0
refset_replay_maxdiff=254
refset_census_coverage_missing=244
- Plan runtime672 indices0..671, historique564, supplément108 ; plan-essai11.tsv.
- CPU helpers : résultat manager code0 ; valid roundtrip=1 rejected=32, provenance-test-essai11.log.
- refset_provenance_checked=0 signifie suffixe non exercé dans cette course, aucun crédit de couverture.
- Analyse Python code0 : 24/24 PNG SHA identiques essai10 ; legacy-comparisons-essai11.json.
- Origine/h00 versus référence RGB : maxdiff202, diffpx794, bbox287,13,314,72 ; hors ROI0 pour24 PNG.
- Capture1 : hutlamp-lod0, hash NOM b872b73f9b7e5d2e ; roi-essai11.log contient5 lignes exactes.
- Merc indices34395/34488/34583 textures429/430/431 : rgb_changed590/117/58 ; maxdiff168/128/151.
- Bboxes RGB288,43,314,67 / 292,38,310,72 / 300,13,308,37 ; alpha_only0 pour chaque draw.
- Bucket52 : rgb_changed765, maxdiff168, bbox288,13,314,72 ; écriture RGB mesurée, cause historique non établie.
- GL_INVALID_OPERATION7290 occurrences contre7185 essai10 ; GL_INVALID_ENUM0 et GL_INVALID_VALUE0.
- Census total3427130, residual0, rb_mismatch0 ; gpu_ms_buckets7.4360 inclut lectures diagnostic.
- Avertissements build shadow/deprecation et sign-promo refset.cpp:1646 ; aucune erreur build.
- Non prouvé : phase historique lampe, correction divergence, cinq rejeux, suffixe/provenance runtime, couverture complète, non-régression GL.
- Aucun generic.sh, appareil, nouvelle référence, ablation ou deuxième course exécuté.
