# Une nouvelle AO : l'ancienne à la poubelle, la nouvelle calculée dans l'éclairage sur le seul indirect, plus jamais un filtre posé à la fin — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

17/09 18:35 ARBITRAGE OWNER : « Option a, mais 0,009 % c'est infime, et tu parles d'un truc mobile j'ai l'impression ». 2 essais, PERIMETRE UNIQUE : le point F « rien ne bouge camera fixe » (1802 texels sur 21 M, bords de buissons) et les 2 px de `ao_sway_gap_px`. Tout le reste est acquis et ne se retouche pas (A-E, G). ORDRE : (1) d'abord NOMMER la source du changement image a image sur une scene immobile par ablation, en une course : (i) la prepasse echantillonne-t-elle le feuillage autrement que la passe couleur (mip, filtre, seuil alpha) ? publier les deux etats d'echantillonnage ; (ii) l'estimateur utilise-t-il un bruit / une rotation PAR IMAGE (texture de bruit, jitter temporel) ? publier le compte de texels qui changent avec le feuillage exclu de la population : s'il reste non nul, la cause est dans l'estimateur, pas dans l'alpha ; (2) ensuite corriger LA cause nommee : echantillonnage de la prepasse identique a la couleur (meme mip, meme filtre, meme alpha_min) et/ou bruit de l'estimateur fixe par pixel (pas par image). Un texel qui change alors que TOUT est immobile est le defaut ; ce n'est pas un objet mobile : vent coupe et temoin `ao_sway_moved_px` publie, acteurs et particules exclus.

Owner 17/09 : « AO legacy poubelle → Nouvelle AO plus en filtre à la fin », puis « être clair sur ce qu'on veut exactement par rapport à la spec » : le livrable recopie la spec (4.2 lignes 2-6, 4.6, 4.7), il ne la resume pas. Et : « une bande claire à la zone de contact… l'AO est juste posée par-dessus comme un filtre ». Ce ticket REMPLACE lighting-ao-indirect (14 essais, livrable devenu illisible) : memes mesures, contrat lisible. Prepasse (ao-prepass-tie-alpha) et sonde stable (ao-static-probe-deterministic) sont faites et se gardent. Ne pas chasser la bande dans le flou : la cause probable est le masque de luminance de la composition finale, qui disparait avec elle (A).

## Livrable — le contrat, en entier

`ao_owner_defects` = 0, somme de termes publies SEPAREMENT ; un terme non mesure compte 1. CE QUE LA SPEC DIT, EXACTEMENT (SPEC lumiere 4.2, 4.6, 4.7) :

A. L'ANCIENNE AO EST SUPPRIMEE (4.7) : la passe qui composait l'AO sur l'image opaque finale (`ao_composite.frag`, `GL_ZERO / GL_ONE_MINUS_SRC_COLOR`, espace gamma, tout le pixel), son masque de luminance `1 - smoothstep(0.45, 0.90, luma)` et la copie de scene `m_scene_tex` n'existent plus dans le binaire : sites = 0, temoin de compilation, aucun chemin ne les rappelle.

B. LA NOUVELLE AO EST UNE TEXTURE (4.7) : les trois estimateurs SSAO / HBAO / GTAO ne changent pas ; leur ENTREE est la prepasse (4.6 : `depth` partagee, normale `RG16F` octaedrique, rugosite `R8`, opaque monde + acteurs opaques, feuillage alpha-teste inclus, pas l'eau ni les particules) et leur SORTIE une texture `R8` en lineaire, plus jamais un blend.

C. ELLE EST APPLIQUEE DANS shade() (4.2) : `screen_ao` est echantillonnee en P4 ; `ao_total = screen_ao * ao_map * ao_baked` (produit explicite avec l'AO de matiere et l'AO cuite, ligne 3) ; elle multiplie le SEUL indirect : `L_diffuse = albedo/pi * E_ind * ao_total` (ligne 5) et le speculaire ambiant via `occ_spec = clamp(pow(N.V + ao, roughness^2) - 1 + ao, 0, 1)` (ligne 2), JAMAIS le direct (ligne 4 : `E_ind` cuit ; regle : « La lumiere directe n'est jamais multipliee par l'AO »). Temoins : `ao_direct_leak_px = 0` (pixel direct seul identique AO allumee/eteinte) ; un pixel indirect seul assombri exactement de `ao_total` ; aucun masque de luminance.

D. TRANSPARENTS ET EAU (4.7) : les transparents sont ombres comme le reste (plus « exclus par construction ») ; l'eau passe par `SURF_WATER`, traitee par la matiere, plus par stencil. Publier le compte de fragments transparents ombres (non nul) et le compte de fragments alpha-testes du feuillage recevant de l'AO hors de leur texture (`ao_on_alpha_device_px = 0`, sur l'appareil, vent allume, prepasse qui suit le vent : `ao_sway_gap_px = 0`).

E. LE RACCORD DE LA HUTTE (retour owner du 17/09) : sur les aretes mur/toit trouvees automatiquement, pour CHAQUE estimateur et CHAQUE qualite, bande claire = 0 (`ao_contact_band_px`, `ao_hutedge_bright_excess_x1000` par mode/qualite).

F. PAS DE DAMIER, RIEN NE BOUGE : motif periodique sur l'image rendue sous le plafond a toutes les qualites (`ao_pattern_over_ceiling = 0`), Eleve en pleine resolution ou filtre bilateral conscient de la profondeur publie (`ao_high_not_fullres = 0`) ; camera fixe, vent coupe : variation du tampon d'AO entre deux images = 0 texel (`ao_static_cam_delta_px = 0`).

G. LE COUT : temps par image AO eteinte / SSAO / HBAO / GTAO, meme vantage, >= 300 images chacun, publie ; la prepasse est partagee (4.6, amendement du 09/09 : une seule passe Z merc), pas une seconde passe Z.

PREUVE : `FEATURE ao-indirect-clean armed=1 hits=<pixels dont l'indirect a recu l'AO>` + la ligne `ao_owner_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` : AO absente, image = eclairage sans AO.

PRECISION OWNER 17/09 sur F (« faut être sûrs que ce qui est mesuré est vraiment immobile ! Pas une plante qui bouge au vent ») : la mesure « rien ne bouge » ne compte QUE ce qui est immobile par construction : vent coupe (epingle dans proof_env, et le temoin `ao_sway_moved_px` doit lire 0 sur la course), aucun acteur anime ni particule dans la population (masque par famille de dessin, publie `ao_static_excluded_px` et la liste de ce qui est exclu), cadence figee (deux images consecutives du MEME etat de jeu). Un texel qui change alors que tout est immobile est un vrai defaut (c'est le scintillement que l'owner voit) ; un texel qui change parce qu'un objet bouge n'en est pas un et doit etre exclu AVANT de compter. Publier `ao_static_cam_delta_px` avec son denominateur (`ao_static_cam_pop_px`) et le compte exclu.

PRECISION OWNER 17/09 (suite) : « attention au cycle jour/nuit, ça peut peut-être jouer ? Et aux acteurs divers et variés, caisses, collectibles… ». Pour F : l'heure du jeu est FIGEE pendant la paire d'images (le cycle jour/nuit change l'eclairage, donc l'indirect, donc l'image, pas l'AO ; mais le tampon d'AO se compare entre deux images du MEME instant : publier l'heure de jeu lue aux deux images, egale) ; caisses, collectibles, orbes, mouches, PNJ et tout acteur qui tourne, flotte ou clignote sont exclus par famille de dessin comme les acteurs animes, et comptes dans `ao_static_excluded_px`. Ce qui reste dans la population : le decor immobile (tfrag/TIE) et les acteurs sans animation.

ARBITRAGE OWNER 17/09 (fin) : « faudrait que ce soit prouvé ça parce que si c'est imperceptible juste à cause d'un alpha de texture filtrée mais imperceptible bon… on peut passer à autre chose ! Donc ok pour les deux essais, mais preuve demandée pour le grain qui bouge en cas d'échec ! ». Le point F se juge donc SUR L'IMAGE FINALE, pas sur le tampon d'AO : publier `ao_static_visible_px` = nombre de pixels de l'image rendue (telephone, resolution reelle) dont la luminance change de plus de 2/255 entre deux images consecutives d'une scene immobile (vent coupe, acteurs/particules/collectibles exclus, heure figee), avec son denominateur. REGLE : si `ao_static_visible_px` = 0, le point F est TENU meme si le tampon d'AO change (imperceptible = on passe a autre chose) ; s'il est > 0, joindre au ticket la paire d'images (les deux captures et une image de difference amplifiee) par `linear_sync.py --comment ... --attach`, en illustration pour l'owner, jamais comme porte. `ao_static_cam_delta_px` reste publie a titre d'information et ne compte plus dans `ao_owner_defects`.

OBSERVATION OWNER 17/09, sur le Redmi pendant la mesure : « je vois qu'il y a des lanternes d'intérieur… ces dernières bougent ! Donc oui tu vas avoir des variations ! » Les LANTERNES (et tout luminaire, flamme, objet suspendu ou balancant : acteurs et objets a animation propre, meme sans vent) sont EXCLUS de la population du point F par famille de dessin, au meme titre que les acteurs animes, particules et collectibles ; et le vantage de la paire d'images doit etre choisi SANS lanterne ni objet mobile dans le champ, ou les masquer et publier la surface exclue. Un texel qui change a cause d'une lanterne qui bouge n'est pas un defaut.

## Hors perimetre

Pas de nouveau modele d'AO, pas de reglage en plus dans le menu. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Options > Recharged > Eclairage recharge > Occlusion ambiante, chaque mode et chaque qualite, force au maximum, sur le dernier build de jak-builds : le raccord mur/toit de la hutte porte une ombre de contact sans bande claire ; les facades n'ont ni damier ni grain ; l'AO n'a plus l'air d'un filtre pose sur l'image ; les buissons n'ont pas d'ombre flottante ; camera immobile, rien ne bouge.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-17
> alors ils sont cools tes commetaires d'update, mais on pourrait au moins avoir une raison des échecs et possiblement des preuves à l'appui ! Et pareil pour les succès / réusites partielles d'ailleurs (avec des screens, de la donnée quoi !) Parce que là bah ok je vois qu'il y a eu un échec et que c'est au deuxième essai… mais aucune info !

### 2026-09-17
> Je cite ton extrait de mesures:  source=device  duration_s=610  crash=0  frames=5100  ao_blocky_ceiling_x1000=400  ao_blocky_gtao_q0_x1000=357  ao_blocky_gtao_q1_x1000=259  ao_blocky_gtao_q2_x1000=222  ao_blocky_hbao_q0_x1000=354  ao_blocky_hbao_q1_x1000=253  ao_blocky_hbao_q2_x1000=287  ao_blocky_legacy_gtao_q0_x1000=197  ao_blocky_legacy_gtao_q1_x1000=211  ao_blocky_legacy_gtao_q2_x1000=186  ao_blocky_legacy_hbao_q0_x1000=231  ao_blocky_legacy_hbao_q1_x1000=190  ao_blocky_legacy_hbao_q2_x1000=191  ao_blocky_legacy_ssao_q0_x1000=186  ao_blocky_legacy_ssao_q1_x1000=219  ao_blocky_legacy_ssao_q2_x1000=257  ao_blocky_pop_gtao_q0=4406036  ao_blocky_pop_gtao_q1=4743366  ao_blocky_pop_gtao_q2=3804304  ao_blocky_pop_hbao_q0=5540917  ao_blocky_pop_hbao_q1=4958034  ao_blocky_pop_hbao_q2=4781376  ao_blocky_pop_legacy_gtao_q0=3786042  ao_blocky_pop_legacy_gtao_q1=3315708  ao_blocky_pop_legacy_gtao_q2=2388040  ao_blocky_pop_legacy_hbao_q0=4322394  ao_blocky_pop_legacy_hbao_q1=2998955  ao_blocky_pop_legacy_hbao_q2=3153246  ao_blocky_pop_legacy_ssao_q0=3782976  ao_blocky_pop_legacy_ssao_q1=3582522  ao_blocky_pop_legacy_ssao_q2=3324768  ao_blocky_pop_ssao_q0=4508020  ao_blocky_pop_ssao_q1=4081590  ao_blocky_pop_ssao_q2=4723472  ao_blocky_ssao_q0_x1000=328  ao_blocky_ssao_q1_x1000=194  ao_blocky_ssao_q2_x1000=189  ao_blocky_worst_delivered_x1000=357  ao_blocky_worst_legacy_x1000=257  ao_contact_band_gtao_q0=0  ao_contact_band_gtao_q1=0  ao_contact_band_gtao_q2=0  ao_contact_band_hbao_q0=0  ao_contact_band_hbao_q1=0  ao_contact_band_hbao_q2=0  ao_contact_band_legacy_gtao_q0=78  ao_contact_band_legacy_gtao_q1=60  ao_contact_band_legacy_gtao_q2=65  ao_contact_band_legacy_hbao_q0=42  ao_contact_band_legacy_hbao_q1=10  ao_contact_band_legacy_hbao_q2=66  ao_contact_band_legacy_ssao_q0=156  ao_contact_band_legacy_ssao_q1=96  ao_contact_band_legacy_ssao_q2=114  ao_contact_band_measured=1  ao_contact_band_ssao_q0=0  Tu penses vraiment que c'est le genre de truc que je peux intelligiblement comprendre sérieux ? ça n'apporte vraiment rien pour un humain, ça n'a AUCUN sens !

### 2026-09-17
> Alors ton échec sur truc machin qui viole le critère… oui d'accord, mais c'est quoi le critère et pourquoi ça le viole ? C'est ça que j'attends sur les retours sinon c'est pas bien mieux qu'un rapport brut sans âme ! Et si c'est ça les retours que se prennent les agents pas étonnant que ça tourne en rond d'ailleurs !

### 2026-09-17
> Alors faut p'tetre être sûrs que ce qui est mesuré est vraiment immobile ! Pas une plante qui bouge au vent ou trucs du style, sinon ça réussira jamais !

### 2026-09-17
> Et aussi, attention au cycle jour/nuit, ça peut peut-être jouer ? Et aux acteurs divers et variés, caisses, collectibles …

### 2026-09-17
> Option a, mais 0,009% c'est infime, et tu parle d'un truc mobile j'ai l'impression

### 2026-09-17
> Alors ça se voit comme du grain qui bouge… faudrait que ce soit prouvé ça parce que si c'est imperceptible juste à cause d'un alpha de texture filtrée mais imperceptible bon… on peut passer à autre chose ! Donc ok pour les deux essais, mais preuve demandé pour le grain qui bouge en cas d'échec !

### 2026-09-17
> Alors si ça peut t'aider, je vois les mesures tourner sur le Redmi… (c'est pas toujours le cas car je suis souvent à distance), et je vois qu'il y a des lanternes d'intérieur… je sais pas si t'es au courant mais ces dernières bougent ! Donc oui tu va avoir des variations !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

