# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-07 : « Enfin j'y entend pas grand chose mais j'espère m'être fait comprendre »
- 2026-09-07 : « Mais putain mais c'est pas possible t'es con ou quoi ? S'il s'est arrêté faut comprendre pourquoi et corriger, ça sert a rien si le harnais s'arrête tout seul pour un rien, soit pas débile ! »
- 2026-09-07 : « Attends attends... Le mouvement natif des buissons ? Qu'es-ce que ça vient foutre là ? On parlait du rendu (blancs brûlés, teinte/saturation) avec notre refonte de lighting en HDR vs OFF (donc éclairage par défaut) les textures, les modèles HD, l'herbe, la brise, etc. n'ont absolument rien à voir ! »

## Cause connue
Les anciennes references ne montraient presque aucun ciel (village1-hut) : elles ont donne un faux vert malgre les blancs brules. Detail conserve dans notes et SPEC §8 item 2.

## Livrable
Comparer uniquement refonte lighting ON versus OFF dans le meme build, master ON constant, textures/modeles HD/herbe/brise et autres options identiques. Scenes/cameras/heures/etats apparies. Aucun prerequis master OFF ou egalite historique. ON/OFF peuvent differer : teinte/saturation coherentes avec eclairage par defaut, contraste et details plus riches, pas de blancs brules. HDR interne puis tonemap SDR unique ; ecran HDR natif plus tard. Mesurer clipping, teinte/saturation, contraste et details sur tous niveaux interieurs/exterieurs et huit heures. Adapter les anciens verdicts trois configurations au perimetre deux bras eclairage ; ne jamais transformer une absence de mesure en succes.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Textures, modeles HD, herbe, brise, cadence et comparaison master OFF historique. Sortie ecran HDR native ulterieure. Aucun owner-ok sans parole owner.
