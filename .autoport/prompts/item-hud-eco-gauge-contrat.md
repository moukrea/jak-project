# La jauge d'éco du HUD rechargé : base vide, jauge pleine masquée en camembert selon l'éco active, embout qui suit le remplissage — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

SPEC HUD §4. Assets jak_gauge_empty / jak_gauge_{blue,red,yellow}_full / jak_gauge_{blue,red,yellow}_end. Owner : « c'est une rotation, donc une sorte de masque en forme de camembert » ; « les end-caps doivent suivre la rotation ».

18/09 01:45 ARBITRAGE OWNER, sur le build 9d3aa9-cad029 (PORTE MACHINE VERTE, hud_gauge_defects==0 : la porte ne voyait AUCUN des trois defauts ci-dessous — elle mesure le remplissage et le rythme, pas l'aspect). « c'est vraiment, VRAIMENT tres bien ! Mais c'est quand meme pas parfait. » TROIS POINTS, perimetre exact de la reprise : (1) sur les derniers pourcents l'embout DEBORDE sur le quart bas-droit de la jauge, celui qui ne peut jamais etre rempli ; l'owner demande un MASQUE du quart bas-droit sur l'embout (« quelques pixels… mais c'est derangeant ») ; (2) des particules parasites sous la jauge, a gauche, qui ressemblent a de l'eco verte reteintee a la couleur de l'eco en cours : A SUPPRIMER (« c'est moche ») ; (3) le creux au centre de la jauge est VOULU : il doit porter la VRAIE particule d'eco en cours, le modele 3D du jeu comme pour le reste du HUD, dimensionnee pour deborder un peu SANS recouvrir la jauge (la lecture reste facile). Le remplissage, la couleur, le rythme de vidage et le suivi de l'embout sont ACQUIS et ne se retouchent pas. L'owner a demande « j'ai peut-etre teste sur un build pas fini ? » : NON, verifie — aucun fichier de game/, goal_src/, common/, android/ n'a change apres le commit publie 9d3aa9af6d ; ce qui a suivi n'etait que de la comptabilite de harnais.

18/09 07:15 REGRESSION SIGNALEE PAR L'OWNER : « la jauge d'Eco a disparue (c'est toujours l'ancienne sur les builds que je lance) je pense qu'un autre ticket a ecrase un truc ». CE QUI EST MESURE, PAS SUPPOSE (superviseur) : (a) la jauge EST LIVREE — `hud-recharged-power` apparait 2 fois dans GAME.CGO extrait de l'APK publie de 06:47 (CGO batis a 06:42), 0 dans ENGINE.CGO comme attendu ; (b) le lancement est inconditionnel dans `activate-hud-pc` (hud-classes-pc.gc:4968) ; l'extinction est A L'EXECUTION sur `recharged-master?` + `recharged-hud?` ; (c) l'owner VOYAIT notre jauge le 18/09 vers 01:45 sur le build 9d3aa9 (00:57) et ne la voit plus sur celui de 06:42 ; (d) ENTRE LES DEUX, le seul chantier a avoir touche `hud-classes-pc.gc` est hud-heart : 805 lignes reecrites (7a388bd8c6 « Le coeur recharge sort du drapeau de compilation », 0c48f70e80), plus f0f1b7e9b9/3b14dc298a pour la lueur. PERIMETRE : trouver ce qui eteint notre jauge entre 9d3aa9af6d et HEAD — bisect sur ces commits — et le corriger SANS defaire le coeur ni la lueur. Les trois points du 18/09 sont acquis et ne se retouchent pas. A verifier en premier, c'est gratuit : le meme binaire eteint-il AUSSI le coeur recharge (alors le defaut est commun aux deux, cote reglage/maitre) ou la jauge SEULE (alors il est dans la reprise du coeur) ?

18/09 07:20 REPONSE A LA QUESTION DISCRIMINANTE : l'owner a VALIDE le coeur recharge sur CE MEME BUILD (« C'est bon pour moi ! Bien joue ! », JAK-175). Donc `recharged-master?` et `recharged-hud?` sont ACTIFS sur son appareil et le defaut ne touche QUE la jauge. Ne pas chercher du cote des reglages : chercher dans la reprise du coeur ce qui eteint la jauge (bisect 9d3aa9af6d -> HEAD sur hud-classes-pc.gc, suspects 7a388bd8c6 et 0c48f70e80).

19/09 RETOUR OWNER (JAK-176) : « je saurais dire si la particule est la bonne car oui je l'apercois par le trou au centre de la jauge, mais du coup elle est EN DESSOUS, pas au dessus ! Donc c'est pas bon ! » PERIMETRE UNIQUE : l'ordre de dessin de la nuee centrale — elle doit passer APRES la jauge (par-dessus l'anneau), pas avant. Aujourd'hui `draw-particles` consomme la nuee AVANT `draw-hud` (hud.gc:228, note de la reprise du 18/09) : c'est exactement l'inversion vue. Options a chiffrer : emettre la nuee depuis draw-hud apres l'anneau, ou lui donner un bucket/priorite au-dessus du HUD. PORTE : sur une image ou la nuee et l'anneau se recouvrent, l'ordre d'emission publie place la nuee apres l'anneau (compteur d'ordre par image), et le test de profondeur/occlusion ne la masque pas ; la position et la taille du 18/09 restent identiques.

20/09 RETOUR OWNER (JAK-176) : « c'est par dessus mais la lueur est tres muted… et j'ai l'impression que c'est le truc d'eco vert avec les sparks et teinte de l'Eco Bleue, mais pas le vrai truc d'eco bleu (les sparks d'eco bleue bougent pas comme sur la particule d'Eco Bleue mais exactement comme sur la particule d'Eco verte) ». L'ORDRE DE DESSIN EST ACQUIS. PERIMETRE : (1) par type d'eco, l'emetteur utilise au centre doit etre celui du RAMASSABLE DU MONDE de CE type (groupes distincts bleu/rouge/jaune, pas le groupe vert reteinte) : verifier l'identite du groupe de particules ET ses parametres de mouvement (vitesse, duree de vie, gravite, spin) champ par champ contre le vial du monde du meme type ; (2) la lueur : intensite/alpha et taille des etincelles au niveau du vial du monde (rapport de luminance emise HUD/monde entre 0,8 et 1,2), le HUD n'attenue pas. PORTE : pour chacun des 3 types, groupe identique a celui du monde (id) et champs de mouvement egaux a 5 % ; rapport de lueur dans [0,8 ; 1,2]. Capture jointe.

20/09 11:10 RETOUR OWNER (JAK-176) : « Les eclairs de l'Eco Bleue debordent un peu trop sur la jauge (l'ensemble est trop gros par rapport au trou, pas de beaucoup mais quand meme). Et la teinte est pas assez opaque, ca fait presque transparent ». L'emetteur du bon type est ACQUIS. RESTE : (1) TAILLE : la demi-largeur de 15,0 unites (reprise du 18/09) est trop grande : viser la nuee dans le trou avec un debordement <= 10 % du rayon du trou (mesure sur la boite des sommets emis contre le rayon interieur de l'anneau) ; (2) OPACITE : l'alpha des etincelles rendu a l'ecran est trop bas — chercher pourquoi (alpha du groupe, mode de fusion additif sur fond sombre, taille reduite qui dilue), viser un alpha effectif >= 0,8 au coeur de la nuee, comme le vial du monde. PORTE : debordement <= 10 % du rayon du trou sur les 3 types ; alpha effectif au coeur >= 0,8 ; le mouvement et le type d'emetteur ne changent pas.

20/09 12:15 SUPERVISEUR : essai 8 a CODE la taille et l'opacite (hud-classes-pc.gc, commits d165bf9566 + 1a7e1b405e, DANS le build publie) puis a echoue sur SON PROPRE instrument neuf : terme t10 « bande », band_bad=16223 sur cover=16226 (99,98 % de mauvais) — un taux de base a ~1000 pour mille ne classe RIEN (regle du 14/09 : decoupage muet). L'instrument est suspect, pas forcement la nuee. Budget epuise (2/2). Regle de l'owner (19/09) : ne pas bruler d'essai sur une mesure qui bute sans cause nommee -> l'owner tranche a l'oeil sur le build qui porte l'essai 8. Si un essai suivant est accorde, il commence par calibrer t10 sur un controle positif ET negatif (une nuee volontairement trop grande / trop pale doit rougir, la nuee du vial du monde doit verdir) AVANT de toucher au code.

20/09 13:45 RETOUR OWNER (JAK-176) : « maintenant elle est tellement minuscule que c'est un petit point au milieu du trou, le probleme d'opacite de la lueur bleue n'est en plus pas corrige du tout ». L'essai 8 a SURCORRIGE la taille (un point) et n'a RIEN change a l'opacite visible. ORDRE IMPOSE POUR L'ESSAI SUIVANT : (1) d'abord CALIBRER l'instrument : mesurer la nuee du VIAL DU MONDE (bleu) avec le meme instrument — taille relative et alpha effectif au coeur — et publier ces deux nombres : ils sont LA CIBLE, pas un seuil invente ; puis verifier que l'instrument rougit sur un controle trop petit ET sur un controle trop pale (sinon il est muet, comme t10 a l'essai 8 : 99,98 % de mauvais) ; (2) ensuite regler : rayon de la nuee = 0,85-0,95 du rayon du trou (mesure sur la boite des sommets emis, PAS sur un parametre) ; alpha effectif au coeur >= celui du vial du monde x 0,9 — si le mode de fusion additif sur fond sombre dilue, changer le mode ou la texture, pas juste la constante ; (3) capture COTE A COTE jointe : nuee du HUD et vial du monde dans la meme image. Deux essais.

## Livrable — le contrat, en entier

`hud_gauge_defects` = 0, somme de termes publies SEPAREMENT.

1. L'ANGLE : par image, angle du masque = fraction d'eco x angle plein, ecart publie (< 0,5 degre).

2. L'EMBOUT : l'embout de la couleur active est dessine a la frontiere du remplissage, tourne du meme angle (ecart publie < 0,5 degre), et disparait a 0 %.

3. LA COULEUR : pleine et embout de l'eco ACTIVE (bleu/rouge/jaune), jamais d'une autre.

4. LE VIDAGE : la fraction suit la quantite d'eco du jeu, et sa vitesse de vidage est celle d'origine (memes valeurs aux memes images sur un ramassage scripte).

5. LA POSITION : base, pleine et embout au rectangle de la jauge d'origine (ecart 0 px).

6. ETEINT = ORIGINE.

PREUVE : `FEATURE hud-eco-gauge armed=1 hits=<images ou la jauge rechargee est dessinee>` + la ligne `hud_gauge_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` et le HUD d'origine bit-identique.

## Hors perimetre

Ne touche pas au coeur, aux objets 3D ni aux polices. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

HUD en jeu apres un ramassage d'eco bleue. Deux oui/non : (1) la nuee REMPLIT-elle le trou de la jauge (elle touche presque la couronne, deborde a peine), ni minuscule ni envahissante ? (2) la lueur bleue est-elle pleine et opaque comme sur le vial du monde ?

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-17
> Ah j'ai peut-être testé sur un build pas fini ?

### 2026-09-17
> Alors c'est vraiment, VRAIMENT très bien ! Mais c'est quand même pas parfait. Le end cap suit bien la déplétion d'eco, super, mais sur les derniers % (je sais pas si c'est en % mais tu vois l'idée, ça va overlap par dessus le quart de la jauge qui ne peut pas être rempli d'Eco (le quart bas-droit). C'est un tout petit détail de quelques pixels , ça se tient que ça se produise en fait… mais c'est dérangeant. Tu devrais avoir un masque pour le quart droit-bas sur le endcap pour que ça ne se voit pas !  Deuxième point, il y a en dessous (sur la gauche de la jauge) des particules bizarre qui ressemblent un peut à des particules d'Eco vert qu'on aurait teinté à la couleur de l'Eco en cours… alors ça faut le dégager, c'est moche ! Par contre, le centre de la jauge est creux et vide… c'est pour une raison ! Ce que j'aimerais, c'est qu'il y ait une vraie particule de l'Eco en cours (telle qu'on la trouve in game, le vrai modèle 3D comme on a fait pour le reste du HUD) par dessus ce vide de la jauge ! Bien dimensionné of course pour que ça overlap un peu mais que ça ne recouvre pas la jauge (que la lecture reste facile)  Donc c'est pas validé, mais on est VRAIMENT pas mal !

### 2026-09-18
> Alors il la jauge d'Eco a disparue (dans le sens où c'est toujours l'ancienne sur les build que je lance…) je pense qu'un autre ticket a écrasé un truc ! Alors faut trouver pourquoi et corriger ! En attendant je vérifie les autres tickets en attente de retour

### 2026-09-18
> Non le cœur est bon, t'aurais dû le voir par toi même j'ai validé son ticket !

### 2026-09-19
> Alors je saurais dire si la particule est la bonne car oui je l'aperçoit par le trou au centre de la jauge, mais du coup elle est en dessous, pas au dessus ! Donc c'est pas bon !

### 2026-09-19
> Alors tu m'a même pas répondu… et tu continues à me lister que c'est dans le build X… oui mais t'as pris mon feedback et tu l'as traité ?

### 2026-09-20
> Alors c'est par dessus mais la lueur est très muted… et aussi j'ai l'impression que c'est le truc d'eco vert avec les sparks et teinte de l'Eco Bleue, mais pas le vrai truc d'eco bleu (les sparks d'eco bleue bougent pas comme sur la particule d'Eco Bleue mais plutôt exactement comme sur la particule d'Eco verte donc c'est pas bon)

### 2026-09-20
> Les éclairs de l'Eco Bleue débordent un peu trop sur la jauge (l'ensemble est trop gros par rapport au trou, pas de beaucoup mais quand même).  Et la teinte est pas assez opaque, ça fait presque transparent, t'avais l'air d'exprimer que ça pourrait être un soucis dans les commentaires précédents, ça l'est

### 2026-09-20
> Débile, maintenant elle est tellement minuscule que c'est un petit point au milieu du trou, le problème d'opacité de la lueur bleue n'est en plus pas corrigé du tout, à chier

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

