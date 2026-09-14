# La mesure de stabilite de l'AO echantillonne le MEME instant de scene a chaque course — puis dit si l'AO bouge — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Ne du blocage de lighting-ao-indirect (13 essais). Handoff de l'essai 13, mesure : quatre courses du MEME binaire au meme vantage ont rendu `ao_static_cam_delta_px` = 0 / 387 / 1079 / 62 alors qu'entre la 2e et la 3e le binaire ne differait que par du code de MESURE (aucun appel GL). La sonde est ancree sur `g_frame % kProbeEvery` pendant une course de 150 s de MONTRE a cadence NON plafonnee (2460 / 2220 / 2280 images) : les 8 images de recensement tombent a des moments DIFFERENTS de la scene. Le zero des essais 10-12 n'etait pas une propriete du code. Le « ca bouge dans tous les sens » de l'owner ne peut pas etre juge tant que la sonde bouge elle-meme. ACQUIS DE lighting-ao-indirect A NE PAS ROUVRIR NI CASSER (essai 13, appareil eae4df44) : Eleve en pleine resolution (`ao_high_not_fullres=0`), damier sous plafond (`ao_pattern_over_ceiling=0`), alpha respecte sur l'appareil vent allume (`ao_on_alpha_device_px=0`), fuite du direct nulle (`ao_direct_leak_px=0`), bande de contact nulle (`ao_contact_band_px=0`), prepasse qui suit le vent des SHRUBS (26,7 % -> 0,31 %). Ces cinq cles entrent dans la porte de cet item et doivent rester a zero.

## Livrable — le contrat, en entier

`ao_static_defects` = 0, somme de termes publies SEPAREMENT.
1. LA SONDE EST DETERMINISTE : deux courses du MEME binaire, meme vantage, echantillonnent le MEME jeu d'instants de scene (ancrage sur le temps de jeu ou un etat de scene, jamais sur un numero d'image a cadence libre) ; publier `ao_probe_nondeterminism` = compte d'instants qui different entre les deux courses : zero, avec le compte d'instants echantillonnes (non nul) a cote.
2. L'AO NE BOUGE PAS CAMERA FIXE, MESURE PAR LA SONDE STABLE : `ao_static_cam_delta_px` = texels d'AO changeant entre deux images consecutives, camera et scene immobiles, vent coupe pour la mesure : zero a tous les paliers.
3. LE FLOU QUI BOUGE EST DISTINGUE DU BRUIT : publier separement la variation due a l'estimateur (bruit spatial fixe attendu = 0 entre deux images identiques) et celle due a un temporel s'il existe ; nommer la source de tout texel qui bouge.
4. LES ACQUIS TIENNENT : les cinq cles acquises restent a zero dans la MEME preuve, publiees a cote.
PREUVE : `FEATURE ao-static-probe-deterministic armed=1 hits=<images de recensement echantillonnees>` + la ligne `ao_static_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Hors perimetre

Ne touche pas a l'alpha-test de la prepasse ni au TIE : c'est ao-prepass-tie-alpha. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Rien a voir seul : c'est l'instrument qui rend le juge fiable. L'owner regardera l'AO a la fin d'ao-prepass-tie-alpha.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

