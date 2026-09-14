# Plus de bande eclairee sans occlusion au contact des surfaces — acquis verrouille

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md sections 4.1, 4.2, 4.6. ACQUIS DE lighting-ao-indirect (essais 6 a 11, preuves Redmi du 14/09) A NE PAS ROUVRIR : fuite du direct = 0 ; damier des facades sous le plafond (0) ; alpha respecte sur l'appareil vent allume (0) ; palier Eleve en pleine resolution (0). Decision de l'owner du 14/09 15:30 : « ok, si ca bloque decoupe en trois comme tu proposes ». Terme 6 de lighting-ao-indirect : la bande de quelques pixels sans AO le long des aretes de contact (« c'est distrayant », owner 13/09). Mesure : 850 px sur PC le matin, 5 puis 9 sur le Redmi, puis 0 aux deux dernieres courses appareil (15:00 et 15:53). ACQUIS a prouver et a garder par une porte.

## Livrable
`ao_contact_band_px` = 0, somme de termes publies SEPAREMENT.
1. LA BANDE EST NULLE SUR L'APPAREIL : pixels d'arete de contact (discontinuite de profondeur detectee) ou AO = 1 alors que les deux voisins sont occlus = zero, Redmi, 2 000 images, avec le compte d'aretes examinees (non nul).
2. A TOUS LES PALIERS : le meme compte a Faible, Moyen, Eleve, publie separement.
3. LA GARDE VIT : un temoin elargit la zone de rejet des discontinuites d'un pixel et le compte devient non nul ; deux bras publies.
4. RIEN D'AUTRE NE CHANGE : OFF = absence, image bit-identique hors instrument.
PREUVE : `FEATURE lighting-ao-contact-band armed=1 hits=<pixels d aretes de contact examines>` + la ligne `ao_contact_band_px=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`ao_contact_band_px == 0` dans `reports/lighting-ao-contact-band/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-ao-contact-band device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien de nouveau a voir : la garde qui empeche le retour de la bande claire au pied des murs..

## Hors perimetre
Ne touche ni au filtre du damier ni a la prepasse. Ne rouvre AUCUN des quatre acquis. Tout ce qui n'est pas cet item.
