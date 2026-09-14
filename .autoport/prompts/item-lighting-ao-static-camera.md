# L'occlusion ambiante ne bouge pas quand rien ne bouge — acquis verrouille

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md sections 4.1, 4.2, 4.6. ACQUIS DE lighting-ao-indirect (essais 6 a 11, preuves Redmi du 14/09) A NE PAS ROUVRIR : fuite du direct = 0 ; damier des facades sous le plafond (0) ; alpha respecte sur l'appareil vent allume (0) ; palier Eleve en pleine resolution (0). Decision de l'owner du 14/09 15:30 : « ok, si ca bloque decoupe en trois comme tu proposes ». Terme 5 de lighting-ao-indirect. Mesure : 2 245 texels changeants sur PC le 14/09 08:00, 760 puis 749 sur le Redmi, puis 0 aux deux dernieres courses appareil (15:00 et 15:53). C'est un ACQUIS a prouver et a garder par une porte, pas un chantier : l'owner a refuse trois fois « un flou qui bouge dans tous les sens », il ne doit pas revenir sans qu'une porte rougisse.

## Livrable
`ao_static_cam_px` = 0, somme de termes publies SEPAREMENT.
1. CAMERA IMMOBILE, SCENE IMMOBILE, VENT COUPE : variation du tampon d'AO entre deux images consecutives = 0 texel a CHAQUE palier (Faible, Moyen, Eleve) et chaque mode (SSAO, HBAO, GTAO), sur le Redmi, 300 images par palier ; publier le pire par palier.
2. LE ZERO N'EST PAS UNE ABSENCE : compte de texels d'AO non nuls dans la scene mesuree, non nul (denominateur).
3. LA GARDE VIT : un temoin pose une camera qui BOUGE d'un pixel et le compte devient non nul ; les deux bras publies cote a cote.
4. RIEN D'AUTRE NE CHANGE : image bit-identique a l'arbre livre hors instrument (OFF = absence).
PREUVE : `FEATURE lighting-ao-static-camera armed=1 hits=<texels d AO compares entre deux images consecutives>` + la ligne `ao_static_cam_px=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`ao_static_cam_px == 0` dans `reports/lighting-ao-static-camera/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-ao-static-camera device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien de nouveau a voir : c'est la garde qui empeche le retour du flou qui bougeait..

## Hors perimetre
Ne touche pas au filtre, ni a la prepasse. Ne rouvre AUCUN des quatre acquis. Tout ce qui n'est pas cet item.
