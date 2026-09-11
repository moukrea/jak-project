# hdr-display-output — CONTRAT COMPLET

Ce fichier porte ce que la consigne (2 560 octets) ne peut pas contenir. La consigne
ORDONNE de le lire : elle est un resume, pas le contrat.

## Les verdicts 1 a 8, dans le detail

Voir `prompts/SPEC-refonte-lumiere.md` section 4.5 pour le texte normatif. Rappel :
1. capacite DETECTEE et publiee (`hdr_out_display_caps`)
2. option visible SEULEMENT si l'ecran annonce un mode
3. vrai interrupteur : `hdr_out_forced_on` = 0, choix persistant au redemarrage
4. activee : sortie dans l'espace annonce, UN SEUL tone map (`hdr_out_tonemaps_applied` = 1)
5. desactivee : identique au BIT a lighting-hdr (`hdr_out_defect_5_off_identical` = 0)
6. auto-configuration au premier demarrage, choix conserve
7. `hdr_out_menu_parent` = eclairage — la ligne vit sous Options > Recharged > Eclairage Recharge
8. `hdr_out_ui_white_nits` >= blanc SDR du systeme : UI, sous-titres, sprites BLANCS, jamais gris

## Historique des refus de l'owner, dans l'ordre

### 2026-09-06
> Mhhhh ça change effectivement l'image, les blancs sont brûlés ! Mon Honor supporte le HDR, ça l'exploite pas ! Et quand ça supporte par le HDR ça devrait être... Tonemappé je crois qu'on dit ? Vers du SDR pour les écrans qui ne sont pas HDR, en gros par défaut ça devrait être tonemappé en SDR (de la meilleure façon possible pour pas écraser les détails de trop) sauf quand on active le HDR (une option en plus?) qui apparaît si l'écran le supporte, idem sur PC/Linux/Android TV, etc. Et bien sûr ca pourrait faire partie de l'auto-detection au first start

### 2026-09-07
> Attention à distinguer les LUT par niveaux et tonemapping... Car là on tonemap vers SDR pour rendu en mode SDR, mais après on veut aussi bénéficier des LUT quand on aura le rendu HDR possible sur des écrans qui supportent le HDR! Enfin je sais pas si c'est clair c'est un peu au dessus de mon domaine de compétences ! Peut-être que c'est deux choses distinctes , d'ailleurs peut-être que c'est un tout autre chemin, d'ailleurs est-ce que c'est vraiment bénéfique le HDR pour des écrans SDR via tonemapping, est-ce que le HDR est toggleable dans notre refonte parce que ça a probablement un impact sur les perfs de tonemap non ? Bon ça c'est des questions hein, je suis un peu over m'y head là

### 2026-09-07
> Je sais pas ce que ça change pour notre plan de refonte et sa spec... Ça doit bien changer des trucs non ? Tu peux y réfléchir un peu et pas juste consigner ça dans une footnote je sais pas trop où ?

### 2026-09-07
> Après on peut quand même avoir des adaptations différentes sur écran SDR et écran HDR, le fait de partager les altérations c'était de la supposition, je suis pas expert ! Je compte sur toi mais fais pas de la merde

### 2026-09-09
> sur écran HDR, on doit aussi pouvoir toggle ça à off hein ? Pour ceux qui préfèreraient la sortie SDR actuelle sur leur écran HDR par example. Comme sur certains jeux actuels qui supportent le HDR, c'est pas parce que leur écran supporte le HDR qu'ils peuvent pas activer/désactiver le HDR ! Attention je parle bien du HDR écran et pas du calcul HDR qu'on vient de valider, c'est deux sujets différents

### 2026-09-09
> je vois bien qu'il y a un toggle HDR Output (hors des réglages rechargés alors que lui même dépend de la refonte de l'éclairage qui est un réglage rechargé, c'est à corriger)... Et oui, les zones brillantes ressortent bien plus c'est stylé, mais tout est BEAUCOUP plus sombre ! Même les menus... Les a plats blancs sont gris clair (genre le sprite de jak qui cours pendant les chargements), les sous-titres, etc. Ça devrait rester blanc ça ! Et OK la sortie HDR permet de montrer un panel plus large de détail (dans les ombres et lumières), faire pop un peu plus etc etc... Mais ça devrait pas tout assombrir

### 2026-09-09
> oui on doit certes trouver plus de détails dans les ombres (et aussi les lumières) mais pas tout assombrir pour autant sinon c'est un peu un contre-sens ! et ça doit s'ajuster au nits proposés par l'écran je suppose... celui-ci fait 480, mais quid d'un écran à 1000?

### 2026-09-10
> le HDR output toggle est bien deplace dans les options rechargees, mais on/off j'ai aucun changement a l'ecran, je pense que ca active meme plus le HDR en fait

### 2026-09-10
> oui l'image doit pas etre plus sombre au global (ce qui etait mon retour) mais gagner en richesse dans les ombres et lumieres, car l'ecran le supporte c'est litteralement le but du HDR d'avoir plus de detail dans les ombres et lumieres, pas d'assombrir l'ecran ou etre totalement identique !

### 2026-09-10
> le HDR Output apparait et peut etre toggled on/off sur le Redmi alors que je pense pas que ce device supporte le HDR

### 2026-09-10
> faut aligner aux capacites device ! Voila pourquoi je trouve ca trop sombre, t'as calibre pour 1000 nits alors que le Honor expose 480 ! Faut que ca s'aligne automatiquement ! C'est debile de caler a 1000 nits pour tout ecran HDR ! La on dirait que je joue en plein soleil avec la luminosite basse alors que je suis en interieur en luminosite max !

### 2026-09-10
> le dernier build je trouve pas trop sombre, mais on retombe sur le quasi 0 diff entre off vs on... je trouve pas ca plus riche, ou vraiment juste un yota au niveau des trucs qui brillent. Aussi, c'est statique non ? le HDR s'ajuste pas constamment, facon dolby vision ou HDR10+ dans les films, la j'ai l'impression qu'on a un truc HDR et fini, c'est applique partout pareil. Truc bidon quasi inutile donc

### 2026-09-10
> PAS VALIDE DU TOUT. oui j'ai bien l'impression que le HDR s'ajuste automatiquement, mais c'est pas pour autant qu'il le fait bien [...] ca donne aussi lieu a des endroits avec des contrastes completement crames comme si on poussait la teinte/saturation/contraste au max sur un filtre photoshop [...] Pour moi le HDR output, il devrait prendre le calcul HDR brut sans tonemapping vers SDR pour beneficier de toute la richesse que ca a de calculer direct en HDR sans aucun tonemapping, avec potentiellement des corrections pour rester dans les tons de couleurs attendus. La j'ai l'impression que HDR output est un filtre qui vient APRES le tonemapping SDR, comme si on appliquait un filtre HDR sur une image SDR sans avoir les info HDR [...] on gagne pas de richesse dans les zones sombres parce que cette richesse n'est deja plus la dans l'image qu'on traite [...] et le boost de luminosite dans la lumiere est faked ce qui donne ces contrastes completement debiles. [...] Bah je suis pas d'accord ! dans le noir on va pas aller chercher a couvrir du 0 a 2,54x [...] mais c'est un panel bien plus large que 0 a 1, et on peut en tirer un maximum partie du coup !

### 2026-09-11
> donc ca veut dire que pour le chantier HDR, on peut garder le Redmi, a 500 nits c'est top ! Donc on l'utilisera pour l'HDR aussi !

### 2026-09-11
> pour le chantier HDR, on peut garder le Redmi, a 500 nits c'est top ! Donc on l'utilisera pour l'HDR aussi !

## Ce qui a ete mesure, et sur quel ecran

- HONOR (jusqu'au 10/09) : marge accordee 2 251, hautes lumieres livrees 1 445, ombres 17->127,
  hautes lumieres 17->128, assombrissement 0 %. CES CHIFFRES NE VALENT QUE POUR CET ECRAN.
- Le Honor a annonce 480 nits pendant des jours en accordant un rapport de 1,000 : l'image ON
  etait l'image SDR exacte. ANNONCER N'EST PAS ACCORDER.
- REDMI (a partir du 11/09, appareil de preuve) : annonce HDR10, HLG, HDR10+ a 500 nits,
  extensions EGL bt2020_pq / scrgb_linear / fp16 / SMPTE2086 presentes. Tout est a REMESURER.

## Pourquoi ce fichier existe

L'owner, 11/09 : « faudrait pas perdre des infos, sinon justement le principe iteratif est un
peu detruit ». Chaque refus ajoute un verdict ; la consigne est plafonnee. Ce qui en sort
atterrit ICI, jamais a la poubelle.
