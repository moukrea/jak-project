# La coque monte en gamme sur PC : Ultra visible et mesure

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 12 : Ultra = texel 3,1 cm, 320 chunks, 6 capsules de jambes, normales detaillees, seuils de LOD x 1,6. Le pire appareil est le banc d'essai, pas la cible (owner 09/09).

## Livrable
`soft_ultra_defects` = 0, somme de termes publies SEPAREMENT.
1. ULTRA DIFFERE DE MOYEN, MESURABLEMENT : texel, chunks actifs, capsules, seuils publies dans les deux paliers ; ecarts egaux a la matrice.
2. LE BUDGET ULTRA TIENT : `gpu_ms_soft` ≤ 6,0 ms et CPU ≤ 0,5 ms sur le vantage nomme, 300 images.
3. LA RESOLUTION SE VOIT DANS LA DONNEE : compte de texels par empreinte de pied en Ultra ≥ 4x celui de Moyen.
4. AUCUNE DIVERGENCE DE CHEMIN : memes programmes, memes producteurs ; compte de branches de code propres a Ultra = zero.
PREUVE : `FEATURE soft-pc-ultra armed=1 hits=<images mesurees en Ultra>` + la ligne `soft_ultra_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_ultra_defects == 0` dans `reports/soft-pc-ultra/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-pc-ultra x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur ton PC en Ultra : les empreintes sont fines, les bourrelets detailles, les sillons lointains conserves..

## Hors perimetre
Pas l'appareil. Tout ce qui n'est pas cet item.
