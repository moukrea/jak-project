# Une nouvelle AO : l'ancienne à la poubelle, la nouvelle calculée dans l'éclairage sur le seul indirect, plus jamais un filtre posé à la fin — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Owner 17/09 : « Basique : AO legacy poubelle → Nouvelle AO plus en filtre à la fin ». Et : « on a quand même (quel que soit le modèle d'AO et la qualité) une bande claire à la zone de contact… l'AO est juste posée par-dessus comme un filtre, comme si elle était calculée tout à la fin ». SPEC lumiere 4.7, table aujourd'hui/cible : aujourd'hui ao_composite.frag multiplie l'image opaque FINALE en gamma, tout le pixel, avec un masque de luminance 1-smoothstep(0.45,0.90,luma) ; cible : texture R8, lineaire, le SEUL terme indirect dans shade(), aucun masque, transparents ombres comme le reste. Ce ticket REMPLACE lighting-ao-indirect (14 essais, un livrable devenu illisible) : memes mesures, contrat court. La prepasse (ao-prepass-tie-alpha) et la sonde stable (ao-static-probe-deterministic) sont faites et se gardent. Ne pas chasser la bande dans le flou : le masque de luminance de la composition finale en est la cause la plus probable, et il disparait avec la composition.

## Livrable — le contrat, en entier

`ao_owner_defects` = 0, somme de termes publies SEPAREMENT ; un terme non mesure compte 1.

A. L'ANCIENNE AO EST A LA POUBELLE : la passe de composition finale (ao_composite.frag, GL_ZERO/GL_ONE_MINUS_SRC_COLOR) et son masque de luminance n'existent plus dans le binaire (sites = 0, temoin de compilation), aucun chemin ne les rappelle.

B. LA NOUVELLE AO EST DANS L'ECLAIRAGE : la texture d'AO (R8) est lue dans shade(), en lineaire, avant le tone map, et multiplie le SEUL terme indirect. Temoins : un pixel eclaire par le direct seul a la MEME valeur AO allumee et eteinte (`ao_direct_leak_px=0`) ; un pixel a l'ombre (indirect seul) est assombri exactement du facteur AO.

C. LE RACCORD DE LA HUTTE : sur les aretes mur/toit trouvees automatiquement, pour CHAQUE mode (SSAO, HBAO, GTAO) et CHAQUE qualite, bande claire = 0 (`ao_contact_band_px` et `ao_hutedge_bright_excess_x1000` par mode/qualite).

D. PAS DE DAMIER : motif periodique mesure sur l'image rendue sous le plafond a toutes les qualites (`ao_pattern_over_ceiling=0`) ; Eleve en pleine resolution ou filtre bilateral publie (`ao_high_not_fullres=0`).

E. LES PLANTES : aucun fragment transparent (shrubs, feuillage, herbe) ne recoit d'AO, mesure sur l'appareil vent allume (`ao_on_alpha_device_px=0`) ; la prepasse suit le vent (`ao_sway_gap_px=0`).

F. RIEN NE BOUGE CAMERA FIXE : variation du tampon d'AO entre deux images = 0 texel a tous les paliers (`ao_static_cam_delta_px=0`).

G. LE COUT : temps par image AO eteinte / SSAO / HBAO / GTAO, meme vantage, >= 300 images chacun, publie.

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

