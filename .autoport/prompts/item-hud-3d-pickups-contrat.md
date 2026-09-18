# Mécamouche, orbe, particule d'éco verte et pile d'énergie du HUD : les vrais modèles du jeu à la place des sprites — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

17/09 20:55 REFUS OWNER (build 4833ab) : orbe, mecamouche, eco vert acquis ; la PILE D'ENERGIE apparait minuscule et « squeezee » au centre de l'ecran, avec la bonne animation mais pas la bonne place ni la bonne echelle (positionnement absolu suspecte, aspect faux). La mesure de position de l'essai 2 a rendu 0 px pour la pile : elle mesurait a cote. Corriger la mesure d'abord, puis la pile. Ne pas toucher aux trois autres elements.

17/09 REFUS OWNER (build ae4272) : mecamouche au milieu de l'ecran des la premiere image tant que le HUD n'a pas ete affiche ; pile d'energie minuscule toujours visible, positionnement absolu en pixels sur une petite resolution (aspect faux) ; mecamouche un peu trop haute une fois le HUD affiche ; pile pas placee. Les deux captures sont dans owner-feedback/hud-3d-pickups/ (regarde-les). La porte de l'essai 1 etait aveugle : mesurer sur l'IMAGE RENDUE de l'appareil, et suivre la visibilite du HUD d'origine.

SPEC HUD §5, mots de l'owner du 17/09 : « la vraie mecamouche du jeu et plus un sprite dégueu », « une vraie orbe », « une vraie particule d'eco verte comme celles qu'on ramasse in game », « pour la pile d'énergie, idem ».

17/09 23:25 SUPERVISEUR — owner (JAK-177) : « si tu bute sur une mesure, je peux faire la vérif moi même… suffit de me dire quoi vérifier ». Essai 3 : 1 seul defaut restant (la pile) ; cause nommee par l'agent : draw-bones-hud-merc ne dessine qu'une partie du modele (effets sans envmap) et color-mult/color-emissive sont inertes sur un dessin de HUD. Essai 4 en vol (22:51) applique le correctif. REGLE : si l'essai 4 rougit sur la MESURE, PAS d'essai 5 : l'item passe a tester par l'owner avec les 4 questions de `where`.

18/09 00:10 ESSAI 4 — ETABLI par l'agent : la cause de « la pile minuscule et ecrasee » est TROUVEE ET CORRIGEE (la pile etait le seul des quatre emplacements route vers Merc2, qui n'a aucun chemin HUD et divise par le w du monde ; elle passe desormais par dma-add-process-drawable-hud-with-cell-lights, le chemin des trois emplacements que l'owner declare bons ; commit a656d3da9e, DANS le build publie 0ed531-cad029). Le seul defaut restant est le terme §9 (stabilite de la boite mesuree par difference d'images) : CHIFFRE INEXPLOITABLE sur cet appareil — derive de 2,8 a 3,4 niveaux de luminance par pixel entre deux images identiques, seuil 6, 0 pixel retenu, controle compris. Le bruit de l'appareil est au-dessus du signal. L'agent demande l'autorisation avant de construire un instrument exact (boite des sommets transformes lue dans Generic2). PAS d'essai 5 : l'owner tranche (regle du 17/09 23:15).

18/09 00:20 ARBITRAGE OWNER, sur photo (owner-feedback/hud-3d-pickups/20260917T2215-1.jpg) : « elle est bien à son emplacement attendu ! Mais […] une pile d'énergie in game a un effet lumineux, la nôtre dans le HUD ne l'a pas ! […] c'est pas tout à fait validé vu qu'il manque l'effet lumineux, mais bien joué ! ». PERIMETRE UNIQUE DE LA REPRISE : donner a la pile du HUD l'effet lumineux qu'elle a dans le monde. Position, taille et les trois autres emplacements sont ACQUIS par l'owner et NE SE RETOUCHENT PAS. Le terme §9 (stabilite par difference d'images) reste inexploitable sur l'appareil, il ne motive aucun essai. La porte de cette reprise se lit sur une grandeur de l'effet lui-meme (l'element lumineux du monde est-il emis pour l'icone de HUD, et combien de fois par image), jamais sur une image. Si la mesure bute sans cause nommee : demander a l'owner, ne pas relancer un essai.

18/09 02:50 ARBITRAGE OWNER : « l'effet lumineux est bien la mais il n'est pas au meme niveau que la pile d'energie ! La pile est au bon niveau, l'effet lumineux est plus bas (en dessous de la pile) alors qu'il devrait etre au meme niveau ». PERIMETRE UNIQUE : la hauteur de la lueur, a recaler sur celle de la pile. La presence de la lueur, la position de la pile, sa taille et les trois autres emplacements sont ACQUIS. L'ecart est VERTICAL seulement. Et : « t'aurais pu joindre un screen ca aurait accelere les choses » -> joindre une capture de la zone au commentaire de passage en test (DIRECTIVES, Ticket Linear).

18/09 04:25 SUPERVISEUR : essai 5 a RECALE la lueur (ancrage sur la jointure 3 du modele, celle que le jeu utilise, au lieu du centre de la sphere declaree, 4096 unites trop haut dans les donnees d'art ; commits 3b14dc298a + f0f1b7e9b9, DANS le build publie c97d1e-cad029). L'essai 6 n'a laisse aucune note et n'a touche aucun code : plafond epuise sur un essai vide. La porte machine reste bloquee sur des termes que l'appareil ne peut pas mesurer (bruit au-dessus du signal, etabli a l'essai 4). Application de la regle de l'owner : c'est LUI qui tranche la hauteur, une seule question, pas d'essai supplementaire a l'aveugle.

18/09 07:15 ARBITRAGE OWNER : « j'ai l'impression que c'est bon ! Mais la pile d'energie est un peu ETIREE EN LARGEUR par rapport a celles qu'on voit in game… peut-etre une histoire d'aspect ratio, a verifier et ajuster ». La hauteur de la lueur est ACQUISE. PERIMETRE UNIQUE : les proportions de la pile du HUD, a ramener sur celles du modele pose dans le monde. INSTRUMENT AUTORISE (l'agent l'avait demande a l'essai 4, refus de le batir sans accord) : la BOITE DES SOMMETS TRANSFORMES lue au moment du dessin de HUD, pas de lecture d'image, pas de seuil statistique, une image suffit ; la grandeur est le rapport largeur/hauteur de cette boite, compare au meme rapport pour le ramassable du monde. C'est exactement la mesure que le bruit de l'appareil interdisait par difference d'images. La porte se lit sur ce rapport, et le vantage doit couvrir 21:9 ET 4:3 basse resolution (l'owner joue en 4:3 basse resolution).

## Livrable — le contrat, en entier

`hud_model_defects` = 0, somme de termes publies SEPAREMENT.

1. QUATRE EMPLACEMENTS, QUATRE MODELES : mecamouche (vue de face), orbe, particule d'eco verte, pile ; par emplacement, l'identifiant du modele dessine est publie et c'est celui du jeu (le meme que l'objet ramassable).

2. PLUS DE SPRITE : allume, le nombre d'appels du chemin sprite d'origine pour ces quatre elements = 0.

3. LA POSITION ET LA TAILLE : chaque modele est cadre dans le rectangle de l'element d'origine (rectangles publies, ecart 0 px).

4. LE COUT : temps par image du HUD allume contre eteint, >= 300 images, publie (< 0,3 ms sur le telephone).

5. ETEINT = ORIGINE.

PREUVE : `FEATURE hud-3d-pickups armed=1 hits=<emplacements du HUD dessines avec un modele>` + la ligne `hud_model_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` et le HUD d'origine bit-identique.

S'AJOUTE (REFUS DE L'OWNER, 17/09, build ae4272, deux captures dans owner-feedback/hud-3d-pickups/) : « tant que le hud n'a pas été affiché in game, dès la première frame du jeu on l'a [la mécamouche] en plein milieu de l'écran » ; « une pile d'énergie tout minuscule juste en dessous… on la voit tout le temps in game, je pense que t'as fait du positionning absolu pour la pile d'énergie sur une petite résolution » ; « in game, la mécamouche trouve bien sa place dans le hud quand on l'affiche (la pile d'énergie non) mais est un poil trop haute par rapport à où était originalement son sprite ». La porte a rendu 0 sur 15 720 images : son terme de position etait un MIROIR (calcule depuis les variables du placement, pas depuis l'image). Verdicts ajoutes :

6. LA VISIBILITE EST CELLE DU HUD D'ORIGINE : un modele n'est dessine QUE dans les images ou le sprite d'origine l'aurait ete (ecran titre et premieres images comprises, HUD replie compris). Publier, sur la course entiere, le compte d'images « modele dessine sans sprite d'origine correspondant » (bras `--off` = temoin) : 0, et le compte d'images ou le HUD est visible (non nul).

7. LA POSITION SE MESURE SUR L'IMAGE RENDUE DE L'APPAREIL : pour chaque element, boite englobante du modele lue sur l'image finale du telephone (masque d'identite de dessin, resolution et aspect reels : 2400x1080, 21:9), contre la boite du sprite d'origine lue de la MEME facon sur le bras `--off` : centre a 2 px pres, taille a 5 % pres, publies par element. Aucune coordonnee absolue en pixels : le placement est une fraction de l'espace HUD d'origine, aspect compris.

8. LA MECAMOUCHE N'EST PAS TROP HAUTE : ecart vertical de son centre contre le centre du sprite d'origine, en pixels sur l'appareil, publie : <= 2 px.

CLARIFICATION OWNER 17/09 : « pas de trucs over-engineered qui coûtent du calcul au binaire final […] je parle du positionnement et compagnie ». Les verdicts 6-8 sont des MESURES DE PREUVE (bras de preuve, masque d'identite de dessin, lecture d'image) : elles n'existent pas dans le binaire livre hors preuve. Le placement lui-meme reste celui du HUD d'origine : les memes coordonnees HUD que le sprite remplace, la meme logique d'apparition/disparition/echelle, une transformation par element et par image, rien de plus. Verdict 4 (cout par image) le verifie : le surcout hors dessin des modeles doit etre nul au bruit pres, publie a part du cout des modeles.

RETOUR OWNER 17/09 20:55 (build 4833ab) : « l'orbe Precursor c'est good, la mecamouche c'est good (elle est un peu sombre) et l'eco vert c'est good, mais la pile d'énergie elle apparaît minuscule et squeezée au centre de l'écran quand on montre le HUD (elle semble faire l'animation d'apparition et disparition, mais pas au bon endroit et pas à la bonne échelle ! C'est ce qui m'avait fait dire que tu utilisais peut-être une sorte de positionning absolu !) ». TROIS des quatre elements sont acquis ; ne pas y toucher. Reste LA PILE D'ENERGIE :
9. LA PILE EST A SA PLACE ET A SA TAILLE : boite englobante de la pile rendue, lue sur l'image finale du telephone (2400x1080), contre la boite du sprite d'origine lue de la meme facon sur le bras `--off`, au moment ou le HUD s'affiche ET pendant son animation d'apparition : centre a 2 px, largeur ET hauteur a 5 % chacune (une pile « squeezee » = rapport largeur/hauteur faux : publier les deux rapports, ecart < 5 %). Publier aussi POURQUOI le verdict 7 de l'essai 2 rendait 0 pour la pile alors qu'elle est au centre de l'ecran : la mesure lisait-elle un autre dessin, un autre espace de coordonnees, ou la boite calculee au lieu de l'image ? Une mesure qui a dit « 0 px » sur un element visiblement faux est corrigee AVANT le code.
Note (pas un verdict) : la mecamouche est « un peu sombre » ; si l'eclairage du modele dans le HUD est facile a aligner sur celui du sprite d'origine (luminance moyenne comparee), le faire, sinon le signaler dans FINDINGS.

OWNER 17/09 21:15 : « Attention le téléphone run en 4:3 sur une résolution basse, au risque de me répéter, c'est ce qui me fait penser que tu utilisais du positionnement absolu ! ». Les verdicts 7 et 9 se mesurent dans DEUX configurations, toutes deux sur l'appareil : (a) native 21:9 pleine resolution, (b) ASPECT FORCE 4:3 A BASSE RESOLUTION (le reglage de l'owner). Le placement est une fraction de l'espace HUD d'origine, donc identique dans les deux ; publier les boites et les ecarts pour chacune. Un element juste en 21:9 et faux en 4:3 est un defaut. Toute coordonnee en pixels absolus dans le code de placement est un defaut (publier le nombre de sites de placement et la forme de chacun : fraction d'espace HUD, jamais des pixels).

## Hors perimetre

Ne touche ni au coeur ni a la jauge. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

HUD en jeu, sur le build nomme dans le commentaire « build publie ». UNE question : la pile d'energie du HUD a-t-elle les MEMES proportions que celle posee dans le monde, ou est-elle encore etiree en largeur ? (la hauteur de la lueur, la position, la presence de la lueur et les trois autres emplacements sont valides par l'owner : ne pas les redemander).

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-17
> Les specs… Linear il peut pas les avoir ? ça serait pratique parce que voir que la spec existe sans pouvoir la lire…

### 2026-09-17
> Alors la mecamouche elle est bizarre… tant que le hud n'a pas été affiché in game, dès la première frame du jeu on l'a en plein milieu de l'écran, ça se règle dès qu'on ouvre le hud in game. Si tu paie bien attention au même screen, tu verra qu'on voit aussi une pile d'énergie tout minuscule juste en dessous… et elle, on l'a voit tout le temps on game, je pense que t'as fais du positionning absolu pour la pile d'énergie sur une petite résolution et du coup c'est complètement à côté de la plaque (avec un aspect ratio différent en prime je présume). Sinon, in game, la mecamouche trouve bien sa place dans le hud uand on l'affiche (la pile d'énergie non) mais est un poil trop haute par rapport à où était originalement son sprite, tu devrais pouvoir facilement régler ça   ![71422.jpg](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/6f19ebc7-9cda-42ba-9daf-b4b876156c8d/6085f020-ebfa-4e85-9d28-653fd6d46658)  ![71423.jpg](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/66db29eb-44f2-497c-935d-6cbab80bb657/e6f6d4aa-4c7c-4d4a-b3c0-e0840fe80e57) [images enregistrees : .autoport/owner-feedback/hud-3d-pickups/20260917T1225-1.jpg ; .autoport/owner-feedback/hud-3d-pickups/20260917T1225-2.jpg]

### 2026-09-17
> Alors attention avec tes trucs compliqués à pas induire des calculs gaspillage au runtime hein ! Faut bien les placer, qu'ils se comportent comme l'original (façon d'apparaître et disparaitre, échelle, position) mais pas de trucs over-engineered qui coûtent du calcul au binaire final pour y arriver ! Qu'on soit bien clair (après oui ça va coûter plus parce qu'on remplace des sprites par des modèles 3D, c'est normal, mais je parle du positionnement et compagnie)

### 2026-09-17
> Je cite encore :  "source=device  serial=eae4df44  duration_s=433  crash=0  frames=15720  hud_model_defects=0"  Tu crois vraiment que ça m'aide ? C'est ça tes mesures ? Qu'est-ce que ça dit du succès ou de l'échec ? Vraiment d'une c'est pas intelligible pour moi (p'tetre pour l'agent qui a le contexte, mais j'en vient même à douter), de deux qu'elle est la valeur de ce genre de preuves en commentaire sur les tickets ? Nan mais sérieux faut pas exaggérer, certes je demande des infos, mais faut que les infos apportent quelque chose !

### 2026-09-17
> Il est publié le build ou pas ?

### 2026-09-17
> Évite ce bruit la prochaine fois, fais les modifs nécessaires pour éviter ce bordel à l'avenir si besoin. Je vais tester et te fais mon feedback dans la foulée

### 2026-09-17
> Correction… pas d'apk sur jak-builds… c'est quoi ce bordel ???

### 2026-09-17
> Putain mais tu merdouilles là !

### 2026-09-17
> Ça fait 15 minutes et toujours rien ! C'est quoi ce bordel ???

### 2026-09-17
> Comment ça se fait que ça refuse autant c'est pas normal !

### 2026-09-17
> BUILD_INFO.txt, jak1_hd_assets.manifest.txt et jak1_ui_fonts.zip sur la release j'en ai rien a taper… tu peux les supprimer et t'assurer qu'ils soient plus poussés ça pollue pour rien. Prochain commentaire de ma part sera un feedback.

### 2026-09-17
> Alors l'orbe Precursor c'est good, la mecamouche c'est good (elle est un peu sombre) et l'eco vert c'est good, mais la pile d'énergie elle apparaît minuscule et squeezée au centre de l'écran  quand on montre le HUD (elle semble faire l'animation d'apparition et disparition, mais pas au bon endroit et pas à la bonne échelle ! C'est ce qui m'avais fait dire que tu utilisais peut être une sorte de positionning absolu !)

### 2026-09-17
> Attention le téléphone run en 4:3 sur une résolution basse, au risque de me répéter, c'est ce qui me fait penser que tu utilisais du positionnement absolu !

### 2026-09-17
> Je l'ai déjà dit, si tu bute sur une mesure, je peux faire la vérif moi même et suffit de me dire quoi vérifier, plutôt que perdre du temps et gaspiller des tokens

### 2026-09-17
> Alors elle est bien à sont emplacement attendu ! Mais il y a un mais que tu peux voir sur le screen, une pile d'énergie in game a un effet lumineux, la nôtre dans le HUD ne l'a pas ! Sinon c'est vraiment pas mal ! Donc c'est pas tout à fait validé vu qu'il manque l'effet lumineux, mais bien joué ! Encore une fois, plutôt que se fatiguer en preuves visuelles que t'arrives pas à prendre… j'ai répondu en quelques minutes !  ![71492.jpg](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/0a99d129-a2ee-424d-bbb3-7bc5042efece/69fb552b-fc1f-4d50-96f1-be7be1edd055) [images enregistrees : .autoport/owner-feedback/hud-3d-pickups/20260917T2215-1.jpg]

### 2026-09-18
> Alors t'aurais pu joindre un screen ça aurait accéléré les choses… j'ai glané sur le Redmi étant à côté, chargé une partie, affiché le HUD… bah l'effet lumineux est bien là mais il n'est pas au même niveau que la pile d'énergie ! La pile d'énergie est au bon niveau, l'effet lumineux est plus bas (en dessous de la pile d'énergie alors qu'il devrait être au même niveau !

### 2026-09-18
> Alors j'ai l'impression que c'est bon ! Mais la pile d'énergie est un peu étirée en largeur il semblerait par rapport à celles qu'on voit in game… peut-être une histoire d'aspect ratio, à vérifier si tu peux et ajuster en conséquence

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

