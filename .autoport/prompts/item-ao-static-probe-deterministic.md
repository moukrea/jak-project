> LIS D'ABORD `prompts/item-ao-static-probe-deterministic-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La mesure de stabilite de l'AO echantillonne le MEME instant de scene a chaque course — puis dit si l'AO bouge

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Ne du blocage de lighting-ao-indirect (13 essais). Handoff de l'essai 13, mesure : quatre courses du MEME binaire au meme vantage ont rendu `ao_static_cam_delta_px` = 0 / 387 / 1079 / 62 alors qu'entre la 2e et la 3e le binaire ne differait que par du code de MESURE (aucun appel GL). La sonde est ancree sur `g_frame % kProbeEvery` pendant une course de 150 s de MONTRE a cadence NON plafonnee (2460 / 2220 / 2280 images) : les 8 images de recensement tombent a des moments DIFFERENTS de la scene. Le zero des essais 10-12 n'etait pas une propriete du code. Le « ca bouge dans tous les sens » de l'owner ne peut pas etre juge tant que la sonde bouge elle-meme. ACQUIS DE lighting-ao-indirect A NE PA […suite dans le contrat]

## Livrable
`ao_static_defects` = 0, somme de termes publies SEPAREMENT.
1. LA SONDE EST DETERMINISTE : deux courses du MEME binaire, meme vantage, echantillonnent le MEME jeu d'instants de scene (ancrage sur le temps de jeu ou un etat de scene, jamais sur un numero d'image a cadence libre) ; publier `ao_probe_nondeterminism` = compte d'instants qui different entre les deux courses : zero, avec le compte d'instants echantillonnes (non nul) a cote.
2. L'AO NE BOUGE PAS CAMERA FIXE, MESURE PAR LA SONDE STABLE : `ao_static_cam_delta_px` = texels d'AO changeant entre deux images consecutives, camera et scene immobiles, vent coupe pour la mesure : zero a tous les paliers.
3. LE FLOU QUI BOUGE EST DISTINGUE D […suite dans le contrat]

## Preuve exigee
`ao_static_defects == 0` dans `reports/ao-static-probe-deterministic/proof.txt`.
Le proof se produit par `lib/proof_run.sh ao-static-probe-deterministic device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir seul : c'est l'instrument qui rend le juge fiable. L'owner regardera l'AO a la fin d'ao-prepass-tie-alpha..

## Hors perimetre
Ne touche pas a l'alpha-test de la prepasse ni au TIE : c'est ao-prepass-tie-alpha. Tout ce qui n'est pas cet item.
