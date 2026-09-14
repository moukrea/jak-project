DIRECTIVES v775512c234
## ÉTABLI
Essai 2 : correction instrumentale shade.glsl c.a sous u_ao_proof ; aucun changement des seuils ou dessins de prépasse.
Cause préalable conservée : table essai 1, 32 lignes auditées, alpha brut identique, alpha test couleur forcé à 1 ; 725 absents historiques.
Raccordement sonde statique dans requested/active, AmbientOcclusion et les deux ancres kmachine ; critères et ordonnanceur intacts.
Build arm64 incrémental et repack codes 0 ; garde NPC 47 propriétés ; shader c.a vérifié dans le .so.
Preuve neuve unique : run 20260914T171045Z-330330-a3338647, eae4df44, SHA 14f694dbd6dfdfc9, 1980 images, 162 s, crash=0.
MD5 build/appareil 2f0b1f4c5906f297793ccc22d30b8485 ; 13 proof_props effectives, 0 perdue.
village1-hut : ao_geom_cover_px=463967, tie_cover=87027, tie_absent=0, tie_absent_inner=0 ; une acquisition géométrique.
Diagnostic neuf : observed=87027, missing=0 ; FEATURE armed=1 hits=1444 égale pre_judged et own_hits.
Les cinq acquis valent zéro. Sonde : 18 échantillons, 2 ancres, tous termes zéro sauf nondeterminism=1.
ao_static_defects=1 ; ao_probe_compared=0, nondeterminism=non-mesure, baseline_saved=1 ; référence neuve produite par le code.
## TENTÉ
L’alpha corrigé supprime les faux trous mesurés ; aucun défaut de découpe du rendu normal établi sur la vue actuelle.
Le raccordement réutilise sonde et lecteur sans assouplir ; première course ne compare pas au même binaire, donc rouge honnête.
Une seule course ON, aucun deuxième ON, aucune campagne, aucune ablation ni validateur lancé ; pas de proof écrit à la main.
L’état diagnostic_only demeure et ao_tie_prepass_defects n’est pas produit : les clauses manquantes ne sont pas des zéros.
## RESTE
Réconcilier « correctif dans la prépasse » avec la cause instrumentale et la mesure neuve zéro trou sans modification de prépasse.
Autoriser/inscrire le plan minimal nécessaire à la comparaison inter-courses et aux deux autres vues ; ne pas modifier les critères statiques.
Pour la référence du même binaire : état temporaire enregistré sur USB ; un rebuild invalide sa compatibilité. Aucune preuve archive ne vaut course.
Mesurer identité couleur AO éteinte et fragments couleur changés ; --off requis par contrat mais non mesuré ici.
Publier la somme ao_tie_prepass_defects et ses termes seulement quand les clauses sont réellement instrumentées/mesurées.
Laisser l’orchestrateur juger ; rapport et FINDINGS à jour, pas de validation owner. Notes détaillées dans notes/attempt2-scope.md.
