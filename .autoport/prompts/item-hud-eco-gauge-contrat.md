# La jauge d'éco du HUD rechargé : base vide, jauge pleine masquée en camembert selon l'éco active, embout qui suit le remplissage — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

SPEC HUD §4. Assets jak_gauge_empty / jak_gauge_{blue,red,yellow}_full / jak_gauge_{blue,red,yellow}_end. Owner : « c'est une rotation, donc une sorte de masque en forme de camembert » ; « les end-caps doivent suivre la rotation ».

18/09 01:45 ARBITRAGE OWNER, sur le build 9d3aa9-cad029 (PORTE MACHINE VERTE, hud_gauge_defects==0 : la porte ne voyait AUCUN des trois defauts ci-dessous — elle mesure le remplissage et le rythme, pas l'aspect). « c'est vraiment, VRAIMENT tres bien ! Mais c'est quand meme pas parfait. » TROIS POINTS, perimetre exact de la reprise : (1) sur les derniers pourcents l'embout DEBORDE sur le quart bas-droit de la jauge, celui qui ne peut jamais etre rempli ; l'owner demande un MASQUE du quart bas-droit sur l'embout (« quelques pixels… mais c'est derangeant ») ; (2) des particules parasites sous la jauge, a gauche, qui ressemblent a de l'eco verte reteintee a la couleur de l'eco en cours : A SUPPRIMER (« c'est moche ») ; (3) le creux au centre de la jauge est VOULU : il doit porter la VRAIE particule d'eco en cours, le modele 3D du jeu comme pour le reste du HUD, dimensionnee pour deborder un peu SANS recouvrir la jauge (la lecture reste facile). Le remplissage, la couleur, le rythme de vidage et le suivi de l'embout sont ACQUIS et ne se retouchent pas. L'owner a demande « j'ai peut-etre teste sur un build pas fini ? » : NON, verifie — aucun fichier de game/, goal_src/, common/, android/ n'a change apres le commit publie 9d3aa9af6d ; ce qui a suivi n'etait que de la comptabilite de harnais.

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

HUD en jeu apres un ramassage d'eco bleue, rouge ou jaune, sur le build nomme dans le commentaire « build publie ». Trois questions : (1) sur les tout derniers pourcents, l'embout deborde-t-il encore sur le quart bas-droit de la jauge (celui qui ne se remplit jamais) ? (2) reste-t-il des particules parasites sous la jauge, a gauche ? (3) le creux au centre de la jauge porte-t-il la vraie particule d'eco en cours, en 3D, assez grande pour deborder un peu mais sans gener la lecture ?

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-17
> Ah j'ai peut-être testé sur un build pas fini ?

### 2026-09-17
> Alors c'est vraiment, VRAIMENT très bien ! Mais c'est quand même pas parfait. Le end cap suit bien la déplétion d'eco, super, mais sur les derniers % (je sais pas si c'est en % mais tu vois l'idée, ça va overlap par dessus le quart de la jauge qui ne peut pas être rempli d'Eco (le quart bas-droit). C'est un tout petit détail de quelques pixels , ça se tient que ça se produise en fait… mais c'est dérangeant. Tu devrais avoir un masque pour le quart droit-bas sur le endcap pour que ça ne se voit pas !  Deuxième point, il y a en dessous (sur la gauche de la jauge) des particules bizarre qui ressemblent un peut à des particules d'Eco vert qu'on aurait teinté à la couleur de l'Eco en cours… alors ça faut le dégager, c'est moche ! Par contre, le centre de la jauge est creux et vide… c'est pour une raison ! Ce que j'aimerais, c'est qu'il y ait une vraie particule de l'Eco en cours (telle qu'on la trouve in game, le vrai modèle 3D comme on a fait pour le reste du HUD) par dessus ce vide de la jauge ! Bien dimensionné of course pour que ça overlap un peu mais que ça ne recouvre pas la jauge (que la lecture reste facile)  Donc c'est pas validé, mais on est VRAIMENT pas mal !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

