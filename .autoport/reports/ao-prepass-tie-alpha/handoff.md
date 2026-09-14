DIRECTIVES v775512c234
## ÉTABLI
Essai 1 : diagnostic commité 0106ca837a, build/repack réussis, preuve USB neuve produite par proof_run.sh.
Run 20260914T165752Z-307512-2d62b1fd ; eae4df44 ; SHA d476a8f72ce8ebf1 ; 2100 images, crash=0.
CAUSE MESURÉE : sur 4 images, 347209 pixels TIE observés, 725 absents ; tous classés alpha_rejection_other.
Échantillon proof.txt:1806 : même draw 10 et z 0.010251225, raw couleur=raw pré=0, color_test=1.
Seuil couleur 0.299212605, seuil pré 0.149021909 ; textures/états identiques. Table 32 lignes, audit 32/32.
PrePass.cpp:1678 arme u_ao_proof ; shade.glsl:451 retourne alpha=1 AVANT le discard tfrag3.frag:118.
C’est la mesure couleur qui garde les transparents. Le sur-découpage dans le rendu normal n’est PAS établi.
Ancien compteur dans cette course : 1521 absents, 1009 intérieurs ; ses 8 relevés ne sont pas les 4 du diagnostic.
Les cinq acquis affichent zéro ; ao_static_defects et ao_tie_prepass_defects sont absents, pas des zéros.
## TENTÉ
Observation MRT RGBA32F dans les dessins existants, alpha brut/précoupure, draw partagé et profondeur propres.
Filtrage par famille/profondeur finales ; refus des lectures GPU invalides ; aucune image visuelle utilisée.
Build initial bloqué par quota /tmp ; même garde NPC réussie hors /tmp, 47 propriétés ; repack en 16 s.
Une seule course préalable de 150 s demandées, 163 s consignées ; aucun correctif ni autre course ni validateur.
## RESTE
Réconcilier le contrat avec la cause : le fix minimal est shade.glsl:451, quatrième composante c.a au lieu de 1.0.
Ce fix est instrumental, mais change les fragments COULEUR sondés et n’est pas dans la PRÉPASSE : non appliqué.
Ne pas élargir la prépasse pour suivre l’alpha=1 fabriqué par la preuve ; corriger la mesure avant nouveau diagnostic.
ao_static_probe.h:requested et AmbientOcclusion.cpp:exact_static_probe ne reconnaissent que l’ancien item.
Obtenir ao_static_defects dans la même preuve demande de revoir cette activation ; sonde laissée intacte conformément au contrat.
FEATURE imprime le global (40359433), distinct des 347209 own_hits ; clause littérale encore non satisfaite.
Après résolution : vérifier trous/intérieurs sur village1-hut et deux autres vues, invariance AO off, acquis et ablation.
Table, logs et audit dans notes/ ; anomalies non corrigées dans FINDINGS.txt. Aucune preuve ancienne présentée comme neuve.
