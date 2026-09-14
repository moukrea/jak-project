DIRECTIVES v775512c234

Essai 3 : comparaison neuve, sans changement du binaire ni rebuild.

Le contrat complet a été relu dans .autoport/prompts/.
La table de cause et le correctif instrumental de l'essai 2 sont conservés.
Aucun changement des sources, seuils, populations, ticks ou critères statiques.
L'audit researcher et la course tester sont délégués aux agents natifs Codex,
gpt-6-astra, efforts high et medium ; aucun autre backend lancé.

Audit de code, distinct des mesures d'exécution :
- ao_static_probe.h:103-132 accepte la référence temporaire du même binaire,
  puis la consomme. finish():135-169 compare les 18 entrées neuves à cette
  référence ; il ne réutilise aucun verdict archivé.
- PrePass.cpp:1135-1144,1629 : les six acquisitions de la sonde ne produisent
  qu'une acquisition géométrique. Aucun résultat par trois vues n'existe.
- ao_tie_alpha_probe.cpp:224-235,265-278 : observed et pre_judged ne sont pas
  des nombres de fragments couleur changés ; le mode reste diagnostic_only.
- shade.glsl:438-453 corrige l'alpha de la sortie instrumentale couleur.
  Ce changement ne satisfait pas littéralement un correctif dans la prépasse.
- AmbientOcclusion.cpp:1882-1910 conserve les défauts de non-mesure et tous
  les termes du lecteur statique existant.

Budget : un seul bras ON, timeout 150 s, via lib/proof_run.sh, sans second ON.
La référence de l'essai 2 est l'entrée native de la comparaison, pas une preuve
de remplacement. Le précontrôle et la course sont consignés par le tester.

Blocages contractuels précis :
- DIRECTIVES conditionne l'ablation à une demande du validateur ;
  generic.sh:181-182 vérifie seulement une ablation déjà présente.
  Le contrat exige --off. Aucun OFF ajouté en contradiction avec DIRECTIVES.
- Aucun proof_plan de campagne n'autorise les deux vues supplémentaires.
- Aucun instrument existant trouvé pour l'identité couleur AO éteinte ou
  le delta de fragments couleur. Pas d'instrument ajouté pour fabriquer un zéro.
- Aucun producteur existant de ao_tie_prepass_defects ; aucune somme ajoutée
  en omettant les clauses non mesurées.

Ancres OFF : kmachine.cpp:6145,6156,6188-6192 utilise requested(), et garde
les rendez-vous 300/900 même désarmé. Leur absence sous OFF serait un faux
diagnostic ; aucune course OFF ne les mesure dans cet essai.

Le validateur appartient à l'orchestrateur. Aucun validateur ni jeton owner
écrit par le worker. Le backlog comporte des modifications préexistantes
de statuts et de verdict ; elles ne font pas partie de cet essai.

Résultat de la course neuve :
20260914T171948Z-345561-e6efad49, eae4df44 (Redmi Note 9 Pro), SHA 14f694dbd6dfdfc9, durée 161 s.
Fraîcheur : MD5 local/appareil 2f0b1f4c5906f297793ccc22d30b8485 ; proof_props_effective=13, proof_props_lost=0.
Huit lignes recopiées de proof.txt :
crash=0
frames=2040
ao_geom_cover_px=463871
ao_geom_tie_cover_px=86866
ao_geom_tie_absent_px=0
ao_geom_tie_absent_inner_px=0
ao_probe_nondeterminism=0
ao_static_defects=0
FEATURE ao-prepass-tie-alpha armed=1 hits=1347 ; preuve propre égale ao_tie_alpha_pre_judged_px=1347.
Une acquisition géométrique à village1-hut ; ao_tie_alpha_observed_px=86866, ao_tie_alpha_missing_px=0.
Comparaison native neuve : ao_probe_compared=1, samples=18, baseline_time=1789406035, baseline_saved=0 ; deux ancres exécutées.
La référence de l’essai 2 a servi d’entrée au code, aucun verdict archivé n’a été recopié comme résultat actuel.
Les cinq acquis sont à zéro : ao_high_not_fullres, ao_pattern_over_ceiling, ao_on_alpha_device_px, ao_direct_leak_px, ao_contact_band_px.
Tous les termes ao_static_term_* sont à zéro dans la même preuve ; le blocage statique de l’essai 2 est levé.
