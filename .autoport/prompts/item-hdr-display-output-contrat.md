# Sortir un vrai signal HDR sur les ecrans qui le supportent — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

L'ETUDE hdr-study DOIT ETRE LUE AVANT TOUTE CORRECTION : cet item en depend. Refus 11/09, cinquieme. L'owner ne voit toujours AUCUN gain dans les ombres. Le code dit pourquoi, en toutes lettres : `hdr_out_shadow_gain_x100` compare des NOMBRES DE PALIERS (10 bits contre 8), et son commentaire l'assume — « le SEUL gain que ce chemin livre quand l'ecran n'accorde aucune marge : la finesse ». 17 -> 127 niveaux est un effet de profondeur de quantification, PAS du detail visible. C'est exactement le piege « compter des paliers n'est pas mesurer une amplitude » que j'avais ferme pour les hautes lumieres et JAMAIS applique aux ombres. L'owner demande aussi si l'espace de couleur du calcul est assez riche pour commencer, et ne voit aucune mention du format retenu dans le jeu.

## Livrable — le contrat, en entier

`hdr_out_defects` = 0. Verdicts 1-8 : dans le fichier de contrat, a lire. (9) PAS D'ASSOMBRISSEMENT, sur du JEU REEL, plusieurs niveaux, images comptees. (10) ADAPTATION A L'ECRAN : seule reference = le pic ANNONCE, aucune constante ; prouve par l'EFFET a deux pics. (11) RETABLI apres perte — SOURCE AVANT COMPRESSION : la sortie HDR consomme la scene HDR AVANT le tone map vers SDR. Publier l'identite du tampon lu et le nombre de compressions SDR subies par ce chemin : il vaut 0. Elever le plafond d'un tone map qui a deja ecrase N'EST PAS lire la scene HDR. Lire une image deja compressee = DEFAUT, quel que soit le reste. (12) RICHESSE DANS LES OMBRES — DURCI apres le 5e refus : compter des PALIERS ne vaut plus verdict. `shadow_gain` compare aujourd'hui 10 bits a 8 bits de quantification ; c'est de la finesse d'encodage, pas du detail visible, et l'owner ne voit rien. Mesurer l'ECART DE LUMINANCE entre valeurs voisines dans les ombres, en nits livres a la dalle, sur du jeu reel : ce que l'oeil peut distinguer doit augmenter. Un gain qui ne tient qu'au nombre de paliers est un DEFAUT. (13) AMPLITUDE, PAS COMPTAGE : `hdr_out_hl_max_x1000` atteint l'essentiel de la marge REELLEMENT accordee. (14) ADAPTATION AU CONTENU : la courbe suit la scene dans le TEMPS ; serie publiee ; constante = DEFAUT. (15) LE FORMAT SE CHOISIT SEUL : scRGB > HDR10 > HLG, replis automatiques, format retenu publie. HDR10+ et Dolby Vision ecartes. (16) PAS DE CONTRASTE NI DE SATURATION CRAMES : excursion publiee contre la sortie SDR sur les MEMES images, plafond declare, derive de teinte publiee. (17) NEUF, refus 11/09 — ON DOIT SE VOIR : l'owner decrit « l'effet rien du tout, p'tetre un chouille plus sature ». La difference ON/OFF doit etre EVIDENTE a l'oeil et chiffree : publier, sur les memes images, ce qui separe les deux etats dans les ombres ET dans les hautes lumieres. Un ecart qui ne tient qu'a la saturation est un DEFAUT : la saturation n'est pas du detail. Preuve sur le Redmi eae4df44. (18) NEUF, refus 11/09 — LE FORMAT SE VOIT DANS LE JEU : l'owner ne lit que « HDR output On/Off ». La ligne affiche le format effectivement retenu (HDR10, HLG, scRGB) et, quand plusieurs sont utilisables, laisse choisir.

## Hors perimetre

Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.

## Ou l'owner regardera

Options > Recharged > Eclairage Recharge : la ligne « sortie HDR ». Activee sur le Redmi, les zones brillantes doivent vraiment ressortir, sans que le reste change.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

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

### 2026-09-11
> faudrait pas perdre des infos, sinon justement le principe iteratif est un peu detruit... Si trop long, faut p'tetre s'assurer que l'info soit quelque part en complement avec une instruction de le lire de facon obligatoire. [...] ca devrait s'ajuster automatiquement par le code, parce que le jeu n'est pas destine a tourner que sur le HONOR ou le Redmi, il va tourner sur tout un tas de devices avec des specs differentes, des ecrans differents, du support HDR different. Si ca supporte HDR10+ (variable) faut exploiter, si ca supporte seulement HDR10 on utilise en repli, si ca supporte uniquement HLG on utilise en repli etc... Et quand l'ecran supporte les trois on laisse le choix (enfin si ca a une incidence). Pour Dolby Vision je crois qu'il faut une licence

### 2026-09-11
> HDR10+ on drop complet alors !

### 2026-09-11
> le HDR produit un rendu tres « j'ai pousse le contraste au maximum », c'est pas beau. les warp gates aussi emettent les particules rouges degueulasses

### 2026-09-11
> C'est a chier ! On retombe litteralement sur le pas de diff ON/OFF (p'tetre un chouille plus sature a ON), on profite absolument pas des capacites offertes par les ecrans compatibles HDR ni le fait qu'on fasse tout notre rendu en HDR, on dirait toujours qu'on traite le rendu tonemape a destination du SDR et que [...] on y mette juste un poil plus de saturation, et peut-etre un hack around du blanc dans le ciel pour que ca pop un peu plus. Certes il n'y a plus l'effet filtre de l'espace, mais la en gros il y a l'effet « rien du tout », on tire pas du tout profit du HDR pour gagner en detail dans les ombres et lumieres, on tire profit de rien du tout !

### 2026-09-11
> bah ca devrait aussi avoir pour impact d'avoir plus de details dans les ombres, il me semble que c'est un des benefices du HDR.. c'est pas du tout le cas ici, juste les endroits les plus brillants brillent plus. j'ai pas vu si ca s'ajustait au fil de l'eau non plus (mais ca c'est peut-etre imperceptible) et je me demande si l'espace couleur dans lequel on calcule le HDR est assez riche pour commencer... je pense qu'avant la prochaine iteration faut vraiment creuser le sujet en profondeur (d'ailleurs je vois aucune mention de HDR10/HLG in game juste HDR output On/Off)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

