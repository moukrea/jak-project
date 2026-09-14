# Diagnostic préalable, essai 1

DIRECTIVES v775512c234

Le contrat complet a été lu dans `.autoport/prompts/item-ao-prepass-tie-alpha-contrat.md`.
Le chemin `prompts/` fourni dans le message n'existe pas à la racine du dépôt.

Les 1646 absents, dont 1096 intérieurs, sont les mesures HISTORIQUES de
`lighting-ao-indirect`, pas le résultat de cet essai.
La table alpha demandée avant correctif est absente de cette ancienne preuve.

Lecture de code, à ne pas confondre avec une mesure :
- Le stencil de famille peut être remplacé par un draw sans écriture de profondeur.
  Une proximité de profondeur ne suffit donc pas à identifier un fragment TIE.
- Le diagnostic ajoute un attachement de données flottantes aux dessins existants :
  alpha texture, alpha couleur avant clamp, seuil, profondeur et identité du draw.
  L'identité repose sur le tableau source de draws partagé et son indice, pas sur
  le VAO propre à chaque instance de renderer.
- Le diagnostic refuse un FBO incompatible ou multisample ; il ne convertit pas
  une observation impossible en population nulle réussie.
- La sonde de stabilité et ses portes d'activation sont laissées inchangées.
  Elles ne reconnaissent pas le nouvel identifiant d'item.
- L'émetteur FEATURE commun publie le compteur global, distinct du compte propre
  `proof_feature_own_hits`. Aucune identité entre ces deux compteurs n'est supposée.

Le sélecteur USB exécuté par le tester a rendu `eae4df44`, code 0.
Les paramètres de la vue village1-hut sont épinglés dans le seul item concerné.
La première course doit observer la cause ; aucun correctif de rendu ne la précède.
