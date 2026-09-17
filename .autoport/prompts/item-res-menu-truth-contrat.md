# La resolution affichee est celle qui est rendue, et choisir plus petit coute moins cher — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Aucun cycle n'a etabli de cause. Deux symptomes distincts rapportes le 10/09 sur le dernier build. (a) la ligne « Resolution » n'affiche pas la valeur courante hors du sous-menu, et le sous-menu ne preselectionne pas la valeur en cours : on ne sait jamais ou l'on est. (b) en aspect force 4:3, 640x480 rend PLUS de detail que 800x600 et coute beaucoup plus cher en cadence — un rendu plus fin sous un nom plus petit, donc une resolution effective qui ne suit pas le libelle. Voir aussi l'item res-picker (livre le 30/06, jamais confirme).

## Livrable — le contrat, en entier

`res_menu_defects` = 0. (1) LIBELLE VRAI : la ligne « Resolution » affiche la resolution EFFECTIVE hors du sous-menu, qui s'ouvre presélectionné dessus ; publier libelle ET framebuffer effectif, ils correspondent. (2) MONOTONIE : a aspect donne, les pixels rendus CROISSENT avec la resolution choisie. (3) L'aspect force ne change que la liste proposee. (4) Le choix survit au redemarrage. S'AJOUTE (refus 10/09) : (5) TOUTE LA MATRICE : chaque combinaison aspect x resolution x echelle dynamique (marche/arret) ET chaque bascule de l'une a l'autre ; publier pour chacune le libelle et les pixels rendus. (6) Changer d'aspect ajuste la resolution en accord au lieu de laisser une valeur qui n'appartient plus a la liste. (7) Aucune combinaison inerte : une resolution proposee et choisie DOIT changer ce qui est rendu.

## Hors perimetre

Aucune refonte de menu : l'owner a archive ce sujet le 10/09. On corrige la verite du libelle et la resolution effective, rien d'autre.

## Ou l'owner regardera

Options > Graphismes : la ligne Resolution doit montrer ta resolution actuelle sans entrer dedans. Force le 4:3, puis compare 640x480 et 800x600 : le plus petit doit etre le moins detaille et le plus fluide.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-10
> par defaut on se met sur l'aspect ratio adapte a l'ecran, c'est top, mais le switch de resolution, je pense qu'il est un peu pete... On est jamais surs d'etre a la bonne resolution, l'entree menu resolution devrait afficher la valeur courante meme si on est pas dans le sous menu pour choisir la resolution, et preselectionner la valeur courante quand on y est. Deuxieme bug lie au meme truc... Quand on force un aspect ratio (genre 4x3) le choix de resolution change (c'est attendu) mais bizarrement le 640x480 est pete complet, j'ai beaucoup plus de details que en 800x600 et le FPS prend un mechant coup... Trop etrange !

### 2026-09-10
> la partie aspect ratio, resolution, dynamic resolution scaling on/off, bascule entre toutes ces options... C'est finiky, je sais pas comment expliquer mais j'ai l'impression que certaines resolutions marchent pas vraiment, quand on bascule de ratio la resolution s'ajuste pas toute seule en accord, etc etc.. Faut vraiment que tu testes tout la dessus, c'est pas bon en l'etat

### 2026-09-17
> Je comprend même pas pourquoi il est considéré comme bloqué, je viens de tester sur le build de… 6h et quelques ce matin, ça fonctionne ! Par contre, j'ai remarqué que dans la liste de résolutions, les résolutions sont pas classées par nombre de pixels au total, donc on peut se retrouver avec des résolutions plus basses en après des résolutions très élevées dans la liste de résolutions à choisir… P'tetre un nouveau ticket à faire pour ça.  Aussi, le truc de l'échelle de rendu… Le slider c'est chiant, je préfèrerais un sous menu avec 10, 20, 30, 40, 50, 60, 70, 80, 90 et 100… Mais avec à côté la résolution de rendu calculée live en raccord à la résolution utilisée dans le picker de résolution ! Encore une fois, p'tetre un nouveau ticket dédié pour ça  C'est aussi valable pour l'échelle de rendu min quand on est en échelle de rendu dynamique ! D'ailleurs on devrait aussi avoir un Echelle de rendu max (la value min de cette échelle étant systématiquement supérieure ou égale à l'échelle de rendu min, à ajuster automatiquement, avec les mêmes trucs de display que j'explique juste avant), p'tetre un ticket dédié pour ça aussi.

### 2026-09-17
> Je comprend même pas pourquoi il est considéré comme bloqué, je viens de tester sur le build de… 6h et quelques ce matin, ça fonctionne !

### 2026-09-17
> il est plus que validé du coup non ? C'est terminé ! Enfin dis moi si je me trompe

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

