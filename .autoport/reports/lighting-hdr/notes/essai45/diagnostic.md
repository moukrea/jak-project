DIRECTIVES v3909a9767c
Essai45 : revue hors appareil, aucun changement du rendu ou du harnais.

## Revue researcher render_audit, vérifiée par le manager
Le correctif43 reste commun : shade.glsl386 neutralise shd_mul ; tfrag3.frag54–98, etie_base.frag52–85, tie_wind.frag51–84 et shrub.frag49–78 préparent base=fragment_color*T0 et appellent shade une fois. Aucun refroidissement baked supplémentaire trouvé dans ces hôtes. Conclusion statique, pas preuve jeu.
Une modulation distincte subsiste dans pbr_fused.glsl559–577 (FUS_COOL/fshd_mul/fmod), appliquée au baked ligne677. Sous poids jaune1/vert0 et occultation complète, les defaults background_common.cpp3215–3220 donnent avant puissance (.641888,.650078,.670670), puis environ (.733198,.739734,.756060). Ce calcul décrit une branche conditionnelle, pas une mesure du sol owner. Elle exige u_pbr_mode!=0 et avait été expressément conservée par decision.md43:9 ; aucune attribution matérielle de la zone owner ne justifie son changement.
shade.glsl722 comporte aussi une ombre legacy scalaire sous temps réel OFF/PBR absent/ombre active ; aucune attribution au défaut et aucun mécanisme chromatique démontré par ce seul facteur.
Trace héritée ground/shader-runtime-audit.json43 : shader_error_lines=[], hdr_fallback_used=0, hdr_progs_scanned=53. Cela ne localise aucun matériau.
Trace héritée ground/composition/composition-summary.json43 : event_count=120, sample_count=12, unjoined=0 ; étapes ciel/sprites seulement. Pas de séparation terrain/TIE/décal/ombre.

## Revue researcher coverage_review, vérifiée par le manager
owner-regions.json43:42421–42424 porte status=diagnostic_only et sage-hut-ground dans unattributed_cases. Aucune regions[].layer=sage-hut-ground avec roi_exclusive/samples.
Les rectangles chemin [0,137,35,152] et entrée [82,119,153,148] ont zéro fraction violette270–330 aux trois heures avant/après (decision.md43:35–37, ground-comparison.json). Ils ne sont pas une preuve de disparition du défaut.
image-region-summary.json43 fournit six régions clouds ; les témoins existants ne localisent pas les petites zones du sol. timing-and-witnesses.json conserve case/chain_lf/sample/âge/repin, grass=false et rt_light=true : contexte, pas attribution locale.
Le helper existant mesure des rectangles (hdr_batches.py84–114), mais owner_regions associe seulement HDR-OWNER-SPRITE/HDR-OWNER-SKY, acteurs0/10012/10013/1395 (224–235). Le jugement sol reste sans ROI/séquence sémantique (956–958). Aucun nouveau rectangle arbitraire ne remplit ce contrat.
Minimum encore nécessaire : localisation reproductible de la zone signalée et lien à sa géométrie/contribution ; mesures ON/OFF de cette même région (pixels/hue_bins/luma/detail/saturation), case/frame/options/hash. Les instruments consultés ne fournissent pas ce lien sémantique ni la séparation des contributions. Aucune instrumentation ajoutée.

## Décision et limite de reprise
Aucun défaut nouveau attribué au rendu owner : aucun patch spéculatif PBR, courbe, gain ou couleur. Les diagnostics négatifs nuages/soleil41 et éco30, ainsi que portail44, ne sont pas rejoués.
La mention « aucun appareil » est appliquée comme en44. Aucun build/déploiement, appareil, replay proof_run ou validateur. La preuve du8septembre reste historique, sans rafraîchissement ; empreinte et mtime dans proof-preservation.json.
Le superviseur doit résoudre le cadrage appareil avant une nouvelle reprise de collecte. Reprendre encore les mêmes données ne donnera ni attribution du sol ni couverture21niveaux8h. Aucun changement du backlog, de l’orchestrateur ou des critères par ce worker.

## Vérification tester delivery_check
Contrôle documentaire Python exit0 : report.md/report.txt identiques23lignes ; handoff25lignes avec trois sections ; version correcte ;8/8lignes preuve exactes.
SHA256 proof2b7076b33fb7943da70645d4d87d12a46971106b0913241cbcb20123289b4006 ; mtime_ns1788892154000000000, identiques au relevé initial.
git diff --check et git diff --cached --check : exit0, sortie vide ; aucun diff source rendu/harnais.
Premier contrôle Python exit1 : filtre du contrôle omettait les quatre documents notes/essai45 indexés ; filtre corrigé puis succès. Ce n’était pas un test du jeu ni un défaut de source.
Les trois sous-agents ont terminé. Aucun test294 acquis44 rejoué ; aucun appareil/build/replay/validateur.
