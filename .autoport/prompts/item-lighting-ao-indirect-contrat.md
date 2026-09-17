# L'occlusion ambiante multiplie l'indirect, plus l'image finale — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

17/09 OWNER (Linear) : « Toujours pertinent ? Bloqué pourquoi ? ». Reponse : c'est le ticket PARENT de l'AO. Ses 7 termes sont tous mesures ; 5 sont acquis (Eleve pleine resolution, damier des facades, alpha appareil, fuite du direct, bande de contact), le 6e (sonde stable) est fait, le 7e est le raccord mur/toit de la hutte, en cours dans ao-prepass-tie-alpha. Quand l'enfant passe, cet item se rejoue UNE fois pour mesurer les 7 termes ensemble sur le meme binaire et fermer l'AO. Pas de redecoupage.

LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. ao_composite.frag multiplie l'image opaque FINALE, apres l'encodage gamma, ce qui assombrit aussi le direct — d'ou le masque de luminance, qui est le symptome du mauvais emplacement. SPEC 4.7.

## Livrable — le contrat, en entier

`ao_owner_defects` = 0 — LA PORTE LIT DESORMAIS TOUS LES POINTS DE L'OWNER, plus un seul terme. Somme publiee SEPAREMENT de : (1) `ao_direct_leak_px` ; (2) `ao_pattern_over_ceiling` = 1 si `ao_flatstep_worst_delivered` > 10 a un palier quelconque (le damier des facades) ; (3) `ao_sway_gap_px` (prepasse contre scene sous vent, shrub ET TIE : `ao_geom_tie_absent_px` compte dedans) ; (4) `ao_on_alpha_device_px` (alpha respecte SUR L'APPAREIL, vent allume) ; (5) `ao_static_cam_delta_px` (camera fixe, vent coupe : 0 texel bouge) ; (6) `ao_contact_band_px` (largeur de la bande sans AO aux contacts) ; (7) `ao_high_not_fullres` = 1 si `ao_scale_q2` < 1,0 (Eleve doit etre pleine resolution ou son filtre bilateral publie). Chaque terme est publie avec son denominateur.
RENVOYE PAR LE SUPERVISEUR le 14/09 (pas un refus de l'owner) : l'essai 7 a ete promu « a tester » sur `ao_direct_leak_px == 0` alors que son propre rapport dit : « le palier ELEVE a la MEME resolution que le MOYEN », « ao_flatstep_worst_delivered=19 pour un plafond de 10, inchange », « sur l'appareil ao_geom_* est ABSENT du binaire », bande de contact non mesuree. Acquis de l'essai 7 a GARDER : la prepasse suit le vent des shrubs (26,7 % -> 0,31 % de pixels d'AO sur une geometrie qui n'y est pas) ; le stencil de preuve nomme la famille.

Prepasse profondeur+normale+rugosite. L'AO ecrit une texture ; shade() l'applique au SEUL terme indirect, en lineaire, avant le tone map. SPEC 4.6, 4.7. PREUVE : `FEATURE lighting-ao-indirect armed=1 hits=<px dont l'indirect a recu l'AO>` + `ao_direct_leak_px=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene. Acquis 10/09 a tenir : l'ancienne AO n'est pas compilee, les deux chemins sont comptes, la ligne vit dans « Recharged Lighting ». S'AJOUTE (refus 10/09 au soir) : (a) AUCUN MOTIF VISIBLE, A TOUTE QUALITE : pas de damier ni de pixelisation dans le resultat. Publier, par palier de qualite, la force du motif periodique mesuree dans le tampon d'AO ; elle reste sous un plafond declare. Une passe de lissage bon marche est autorisee et son cout est publie. Un palier de qualite plus laid qu'AO ETEINTE est un DEFAUT, pas un compromis. (b) L'ALPHA EST RESPECTE : aucun fragment transparent de geometrie a decoupe (shrubs, feuillages) ne recoit d'AO. Publier le compte de fragments sous le seuil d'alpha ayant recu de l'AO : il vaut 0. Plus d'ombre flottant au-dessus des brins d'herbe. S'AJOUTE (REFUS DE L'OWNER, 2026-09-12, teste sur le HONOR, mot pour mot) : « L'occlusion Ambiante... toujours pareil sur les plantes, et en faible qualite le flou cache le damier mais n'est pas bon pour autant, c'est un flou vraiment degueulasse qui bouge dans tous les sens c'est pas agreable. »
(c) LES PLANTES, ENCORE. La porte a rendu `ao_on_alpha_px=0` sur 11 160 041 pixels couverts, avec son temoin desarme a 8 742 : la mesure est falsifiable et elle tient. L'owner voit pourtant LE MEME defaut. La porte ne mesure donc PAS ce qu'il regarde. Trouver ce qu'il voit AVANT de recoder : le fragment juge par l'estimateur n'est peut-etre pas celui qui est DESSINE — autre passe, autre niveau de detail, autre chemin (shrub contre tfrag contre TIE), ou une ombre qui ne vient pas de l'AO du tout. Publier ce qui est mesure AU POINT DE DESSIN du brin d'herbe, pas a l'entree de l'estimateur. Une porte verte que l'oeil de l'owner contredit est une porte qui mesure a cote.
(d) LE FLOU BOUGE. En qualite faible, le lissage cache le damier mais devient lui-meme le defaut : « un flou vraiment degueulasse qui bouge dans tous les sens ». C'est de l'INSTABILITE TEMPORELLE, une grandeur que rien ne mesure aujourd'hui : la force du motif periodique est un chiffre PAR IMAGE et ne dit rien de ce qui change d'une image a l'autre. Publier une mesure de variation TEMPORELLE du tampon d'AO, camera immobile, scene immobile : elle doit rester sous un plafond declare, a CHAQUE palier. Et cacher un defaut derriere un flou n'est pas le corriger — si le palier faible ne peut pas etre propre, il vaut mieux qu'il n'applique pas d'AO du tout. S'AJOUTE (REFUS N°2 DE L'OWNER, 2026-09-12 au soir, teste sur le HONOR, quatre captures dans reports/lighting-ao-indirect/owner-honor/ — ENTREE, PAS PREUVE) : « pour l'occlusion ambiante par contre je remarque que en qualite faible j'ai le damier (teste en SSAO, premier screen), en qualite elevee j'ai le damier (teste en GTAO, deuxieme screen), troisieme screen AO off, et j'ai joint un screen ou on voit clairement l'AO au dessus des shrubs ».
(e) LE DAMIER EST AUX DEUX BOUTS, ET DANS LES DEUX ALGORITHMES. C'est la precision qui manquait ce matin : il n'est pas un artefact de la qualite basse, il est present en SSAO faible ET en GTAO elevee. Or la porte a publie une force de motif periodique de 9, 15 et 27 pour un plafond de 1 600 aux trois paliers. CETTE MESURE EST DONC REFUTEE PAR L'OEIL AUX DEUX EXTREMITES : elle mesure le tampon d'AO, l'owner voit l'image finale. L'item doit publier une mesure de motif periodique prise SUR L'IMAGE RENDUE, au vantage de l'owner, et prouver qu'elle voit le damier qu'il voit — en le retrouvant sur le binaire d'AVANT. Une grandeur qui ne retrouve pas le defaut connu ne peut pas prouver sa disparition.
(f) LE COUT N'A JAMAIS ETE CHIFFRE. CORRECTION DU SUPERVISEUR, 12/09 : j'avais lu les compteurs d'images des captures de l'owner comme une mesure. C'EST FAUX et il l'a corrige — « pour le framerate attention c'est juste fortement variable, non on passe pas de 136 a 27, prend pas ca pour une mesure ». Trois captures prises a trois instants ne comparent rien. Il reste que le cout de l'AO n'a ete chiffre par AUCUN essai de cet item. Publier le temps par image, AO eteinte puis SSAO puis GTAO, au MEME vantage, sur le MEME binaire, camera immobile, avec le nombre d'images de chaque releve. Un releve de moins de 300 images ne compte pas, et une cadence lue sur une image ne compte pas du tout.
(g) LES SHRUBS, AVEC UNE IMAGE. Le quatrieme ecran montre l'AO posee au-dessus du feuillage des shrubs, en exterieur. C'est le meme defaut que le verdict (c), et il est desormais localise : exterieur, shrubs, pas seulement les brins d'herbe.
S'AJOUTE (TROISIEME REFUS DE L'OWNER, 2026-09-13, GTAO/SSAO/HBAO en Eleve et force au maximum, puis Faible) :
(h) LA BANDE DE CONTACT SANS AO DISPARAIT. Aux contacts entre deux surfaces, quelques pixels restent eclaires sans AO (la zone de rejet des discontinuites de profondeur). Publier la largeur en pixels de la bande ou AO = 1 le long des aretes de contact detectees, par palier : elle vaut 0 ou est declaree et justifiee, jamais « quelques pixels ».
(i) L'AO SUIT LE VENT ET LE CONTACT. FAIT MESURE (investigation du 13/09) : `prepass_world.vert:29-38` lit `position_in` BRUTE (commentaire « Pas de vent » a la ligne 8) alors que `shrub.vert:20-21` applique `tie_sway.glsl` et `vegetation_contact.glsl` dans la passe couleur. La prepasse doit appliquer le MEME deplacement de sommet que la couleur pour shrub, TIE (et herbe si elle y participe). Publier l'ecart de position, en pixels, entre la profondeur de prepasse et la profondeur de scene sur des shrubs en mouvement : zero au quantum pres.
(j) L'ALPHA EST RESPECTE DANS LA PREPASSE, SUR L'APPAREIL, VENT ALLUME. La porte precedente a rendu zero et l'owner voit encore de l'AO hors des textures : mesurer sur le Redmi, shrubs en mouvement, le compte de pixels d'AO < 1 dont le fragment de couleur est transparent (alpha sous le seuil de decoupe) : zero. Publier aussi le compte de fragments transparents testes, non nul.
(k) RIEN NE BOUGE CAMERA FIXE. Camera immobile, scene immobile, vent COUPE pour la mesure : variation du tampon d'AO entre deux images consecutives = 0 texel a tous les paliers. Le « ca bouge dans tous les sens » est ce compte.
(l) LA RESOLUTION EST CELLE DU PALIER, ET LE FILTRE EST CONSCIENT DE LA PROFONDEUR. Publier par palier l'echelle effective du tampon d'AO, la taille et le type du filtre de remontee ; en Eleve l'AO est pleine resolution ou filtree par un flou bilateral qui ne traverse pas les aretes (compte de texels ou le filtre a melange deux profondeurs a plus de 1 % d'ecart = zero). Un palier plus laid qu'AO ETEINTE reste un DEFAUT ; Faible doit etre exploitable ou retire du menu.
REFUS DU SUPERVISEUR AVANT L'OWNER (2026-09-14 08:25) : la porte `ao_direct_leak_px` a passe SEULE alors que le verdict (a) est VIOLE dans la meme preuve — force du motif `ao_flatstep_*_x1000` au-dessus du plafond 10 a 12 paliers sur 12 (GTAO 11-12, SSAO 18-19 ; plafond 10), et le rapport du worker l'ecrit lui-meme (« inchange »). La verification (j) sur l'appareil n'a pas eu lieu (`ao_geom_*` absent du binaire arm64 : population de bureau seule, 4 464 px de shrub sur 38 images). LA PORTE AGREGE : `ao_owner_defects` (posee le 14/09 08:24 par l'autre session superviseur, sept termes publies separement, `device: true`) est la seule porte ; mes termes (a) a (l) s'y rangent, et un terme NON MESURE compte comme un defaut nomme. On ne renvoie pas a l'owner un quatrieme passage avec la meme pixelisation des facades.

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

### 2026-09-13
> Occlusion ambiante : j'ai poussé à l'extrême les tests... Du coup GTAO en qualité élevé et force plus fort (pour exagérer au plus possible)... Sur les façades même en élevé on a un aspect pixelisé, comme si c'était un filtre collé par dessus en pauvre qualité au final (d'ailleurs étrangement aux contact on a comme une petite bande ou l'ao n'a pas d'effet, laissant une bande de quelques pixels éclairée sans AO, c'est distrayant. Idem en SSAO en élevé, idem en HBAO. L'effet est pire en qualité faible, là c'est carrément dégueulasse et inexploitable (plus un damier comme avant c'est mieux hein, mais c'est inconsistant, avec des bandes, pixelisés, ça bouge, c'est laid. Il y a toujours l'occlusion ambiante sur tous les shrubs en dehors de la zone occupée par une texture, donc des ombres qui flottent dans le vide... D'ailleurs à ce propos, les shrubs qui bougent avec le vent... Leur AO reste à la place initiale (en plus de d'avoir de l'AO sur les parties transparentes) alors que le "vent" les fait bouger (un feature qu'on a terminé il y a quelques jours) et ça aussi c'est un désastre.

### 2026-09-14
> ok, si ça bloque découpe en trois comme tu proposes

### 2026-09-17
> Toujours pertinent ? Bloqué pourquoi ? Besoin de redécouper ? C'est quoi le problème ?

### 2026-09-17
> Top, mais étrangement je vois aucun ticket liés à ce dernier, ils devraient être clairement liés, avec des blocked by, depends on, etc etc. pour tous les sujets sinon on s'y retrouvera jamais, pas étonnant que tu fasse un peu de la merde si on a pas des dépendances claires… C'est un feedback à chaud qui concerne plus le harnais et sa façon de travailler, mais c'est important !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

