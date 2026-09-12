# L'occlusion ambiante multiplie l'indirect, plus l'image finale — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. ao_composite.frag multiplie l'image opaque FINALE, apres l'encodage gamma, ce qui assombrit aussi le direct — d'ou le masque de luminance, qui est le symptome du mauvais emplacement. SPEC 4.7.

## Livrable — le contrat, en entier

Prepasse profondeur+normale+rugosite. L'AO ecrit une texture ; shade() l'applique au SEUL terme indirect, en lineaire, avant le tone map. SPEC 4.6, 4.7. PREUVE : `FEATURE lighting-ao-indirect armed=1 hits=<px dont l'indirect a recu l'AO>` + `ao_direct_leak_px=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene. Acquis 10/09 a tenir : l'ancienne AO n'est pas compilee, les deux chemins sont comptes, la ligne vit dans « Recharged Lighting ». S'AJOUTE (refus 10/09 au soir) : (a) AUCUN MOTIF VISIBLE, A TOUTE QUALITE : pas de damier ni de pixelisation dans le resultat. Publier, par palier de qualite, la force du motif periodique mesuree dans le tampon d'AO ; elle reste sous un plafond declare. Une passe de lissage bon marche est autorisee et son cout est publie. Un palier de qualite plus laid qu'AO ETEINTE est un DEFAUT, pas un compromis. (b) L'ALPHA EST RESPECTE : aucun fragment transparent de geometrie a decoupe (shrubs, feuillages) ne recoit d'AO. Publier le compte de fragments sous le seuil d'alpha ayant recu de l'AO : il vaut 0. Plus d'ombre flottant au-dessus des brins d'herbe. S'AJOUTE (REFUS DE L'OWNER, 2026-09-12, teste sur le HONOR, mot pour mot) : « L'occlusion Ambiante... toujours pareil sur les plantes, et en faible qualite le flou cache le damier mais n'est pas bon pour autant, c'est un flou vraiment degueulasse qui bouge dans tous les sens c'est pas agreable. »
(c) LES PLANTES, ENCORE. La porte a rendu `ao_on_alpha_px=0` sur 11 160 041 pixels couverts, avec son temoin desarme a 8 742 : la mesure est falsifiable et elle tient. L'owner voit pourtant LE MEME defaut. La porte ne mesure donc PAS ce qu'il regarde. Trouver ce qu'il voit AVANT de recoder : le fragment juge par l'estimateur n'est peut-etre pas celui qui est DESSINE — autre passe, autre niveau de detail, autre chemin (shrub contre tfrag contre TIE), ou une ombre qui ne vient pas de l'AO du tout. Publier ce qui est mesure AU POINT DE DESSIN du brin d'herbe, pas a l'entree de l'estimateur. Une porte verte que l'oeil de l'owner contredit est une porte qui mesure a cote.
(d) LE FLOU BOUGE. En qualite faible, le lissage cache le damier mais devient lui-meme le defaut : « un flou vraiment degueulasse qui bouge dans tous les sens ». C'est de l'INSTABILITE TEMPORELLE, une grandeur que rien ne mesure aujourd'hui : la force du motif periodique est un chiffre PAR IMAGE et ne dit rien de ce qui change d'une image a l'autre. Publier une mesure de variation TEMPORELLE du tampon d'AO, camera immobile, scene immobile : elle doit rester sous un plafond declare, a CHAQUE palier. Et cacher un defaut derriere un flou n'est pas le corriger — si le palier faible ne peut pas etre propre, il vaut mieux qu'il n'applique pas d'AO du tout. S'AJOUTE (REFUS N°2 DE L'OWNER, 2026-09-12 au soir, teste sur le HONOR, quatre captures dans reports/lighting-ao-indirect/owner-honor/ — ENTREE, PAS PREUVE) : « pour l'occlusion ambiante par contre je remarque que en qualite faible j'ai le damier (teste en SSAO, premier screen), en qualite elevee j'ai le damier (teste en GTAO, deuxieme screen), troisieme screen AO off, et j'ai joint un screen ou on voit clairement l'AO au dessus des shrubs ».
(e) LE DAMIER EST AUX DEUX BOUTS, ET DANS LES DEUX ALGORITHMES. C'est la precision qui manquait ce matin : il n'est pas un artefact de la qualite basse, il est present en SSAO faible ET en GTAO elevee. Or la porte a publie une force de motif periodique de 9, 15 et 27 pour un plafond de 1 600 aux trois paliers. CETTE MESURE EST DONC REFUTEE PAR L'OEIL AUX DEUX EXTREMITES : elle mesure le tampon d'AO, l'owner voit l'image finale. L'item doit publier une mesure de motif periodique prise SUR L'IMAGE RENDUE, au vantage de l'owner, et prouver qu'elle voit le damier qu'il voit — en le retrouvant sur le binaire d'AVANT. Une grandeur qui ne retrouve pas le defaut connu ne peut pas prouver sa disparition.
(f) LE COUT, QUE PERSONNE N'AVAIT RELEVE. Les trois captures du meme interieur portent le compteur d'images du jeu : AO eteinte 142 img/s, SSAO faible 136, GTAO elevee 27. Soit un facteur 5,3 pour le palier eleve, sur le Honor. Aucun essai de cet item n'a jamais chiffre ce cout. Publier le temps par image AO eteinte, SSAO et GTAO, au MEME vantage et sur le MEME binaire, par palier. Un palier qui coute 80 % de la cadence n'est pas un palier, c'est un defaut.
(g) LES SHRUBS, AVEC UNE IMAGE. Le quatrieme ecran montre l'AO posee au-dessus du feuillage des shrubs, en exterieur. C'est le meme defaut que le verdict (c), et il est desormais localise : exterieur, shrubs, pas seulement les brins d'herbe.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines bit-identiques : master OFF, et recharged_lighting OFF ; tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Pas de mesure visuelle. Les estimateurs SSAO/HBAO/GTAO eux-memes ne changent pas. Precision par variable dans shade() : SPEC 4.4 amendee.

## Ou l'owner regardera

Options > Recharged > Recharged Lighting > Ambient Occlusion : essaie CHAQUE palier de qualite — aucun damier ni pixelisation. Et regarde les shrubs : plus d'ombre qui flotte au-dessus des brins d'herbe.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-03
> L'occlusion Ambiante screen... Je comprend pas ca, on l'a fait tout a la fin du rendu par dessus le reste plutot qu'en composant integral du rendu comme font (je suppose, a toi de dire) les jeux modernes ?

### 2026-09-05
> Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting !

### 2026-09-10
> l'occlusion ambiante... J'ai l'impression que l'option sert toujours l'ancien chemin d'avant la refonte, et l'ancienne faut la degager complet j'ai peur que ca se colisionne. Elle doit vivre dans le sous-menu Recharged Lighting avec ses propres sous reglages (qualite, techno SSAO/HBAO/GTAO, strength et whatnot si pertinent)

### 2026-09-10
> pour l'occlusion ambiante, en qualite faible (je sais plus en qualite moyenne ou elevee) ca fait des damiers bugges/pixelises la ou elle s'applique, c'est tellement derangeant que c'est mieux a off... j'imagine un souci de resolution [...] devrait y avoir une compensation non couteuse en perf genre un flou rapide ou un truc du style [...] Aussi, sur les shrubs, ca ignore la partie transparente et y applique quand meme l'occlusion ambiante dessus, donc on a des ombres d'occlusion ambiante qui flottent au dessus des brins d'herbe/feuilles/plantes qui composent les shrubs, c'est distrayant, ca devrait tenir compte de l'alpha !

### 2026-09-12
> L'occlusion Ambiante... toujours pareil sur les plantes, et en faible qualite le flou cache le damier mais n'est pas bon pour autant, c'est un flou vraiment degueulasse qui bouge dans tous les sens c'est pas agreable.

### 2026-09-12
> pour l'occlusion ambiante par contre je remarque que en qualite faible j'ai le damier (teste en SSAO, premier screen), en qualite elevee j'ai le damier (teste en GTAO, deuxieme screen), troisieme screen AO off, et j'ai joint un screen ou on voit clairement l'AO au dessus des shrubs

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

