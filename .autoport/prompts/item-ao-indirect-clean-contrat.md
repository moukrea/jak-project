# Une nouvelle AO : l'ancienne à la poubelle, la nouvelle calculée dans l'éclairage sur le seul indirect, plus jamais un filtre posé à la fin — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

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

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

