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

## Hors perimetre

Pas de nouveau modele d'AO, pas de reglage en plus dans le menu. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Options > Recharged > Eclairage recharge > Occlusion ambiante, chaque mode et chaque qualite, force au maximum, sur le dernier build de jak-builds : le raccord mur/toit de la hutte porte une ombre de contact sans bande claire ; les facades n'ont ni damier ni grain ; l'AO n'a plus l'air d'un filtre pose sur l'image ; les buissons n'ont pas d'ombre flottante ; camera immobile, rien ne bouge.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

