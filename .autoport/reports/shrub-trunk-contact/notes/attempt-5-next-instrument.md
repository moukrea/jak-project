DIRECTIVES vab39193976
Préparation de la suite ; audit statique, aucune capture GPU exécutée.

Le binaire 602cd72eb7 signalé par l'owner est conservé dans notes/reference-602cd72eb7/libgk.so
(fichier binaire ignoré par git ; copie locale persistante, provenance/empreintes dans attempt-5-audit.txt).
Il ne contient pas encore de mesure de déplacement ; ne pas le présenter comme témoin mesuré.

Parcours : les anciennes courses avaient mode=0 et deux positions finales distinctes.
Le rejeu actuel s'ancre après le spawn F1, mais pas après level.warp seul.
La voie F1 / f1.warp.cont=training-warp existe ; le clip de contact reste à préparer.
Ne pas remplacer cette préparation par trois courses exploratoires.
Le proof_plan impose trois courses de 130 s maximum au TOTAL : 0 consommée depuis autorisation.
Les quatre courses du 14/09 antérieures à 22:45 sont historiques et n'entament pas ce budget.
Épingler tous les réglages nécessaires dans proof_props de l'item, jamais via setprop avant proof_run.

Instrument proposé par l'audit (pas implémenté ici) :
- Conserver uniquement pendant une preuve les indices finaux et paires exactes produits après mesh.
- TIE matrix_idx=-1 : espace prototype, exclu du snapshot monde ; respecter contact_flags==1.
- Séparer LOD TIE ; SHRUB-TIE peut joindre chaque LOD, TIE-TIE de LOD différents ne joint pas.
- Exporter pré-contact et post-contact dans les vertex shaders réellement dessinés.
- SHRUB : pré-contact après vent natif ; v_world est position_in, inutilisable pour mesurer la déformation.
- TIE : paramètre bent et retour de tie_contact_apply ; couvrir ETIE si rencontré.
- Enregistrer varyings avant glLinkProgram (Shader.cpp), capturer transform feedback avec
  VAO/VBO/uniformes et indices effectivement dessinés, sous RASTERIZER_DISCARD.
- Lire les positions GPU et comparer post-pré, puis les deltas des paires à la même frame.
- Publier séparément maximum tronc, maximum feuillage, écart de jonction, populations,
  captures absentes/NaN, invariance vent/herbe et comparaison OFF avec témoin instrumenté.
- Une population ou capture vide est un défaut ; les relations supports ne sont pas des joints.
- Ne produire shrub_trunk_squash_defects que depuis ces mesures, jamais depuis ancres/plans CPU.
- Le témoin doit recevoir une instrumentation neutre justifiée ; disponibilité du .so ancien
  ne prouve pas à elle seule l'identité bit à bit du comportement OFF.
