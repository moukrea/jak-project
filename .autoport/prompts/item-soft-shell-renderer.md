# La coque remplace le sol dans les trois passes, sans encore se deformer : les 3-4 cm, a l'oeil

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC sections 2 et 6. Trois vertex shaders projettent le terrain (tfrag3.vert, prepass_world.vert, pbr_depth.vert) et seul le premier voit les deplacements. La coque a SES programmes couleur / prepasse / ombre soleil, tous incluant `soft_displace.glsl` (Shader::expand_includes). Au chargement, les triangles cedes sortent de l'index du terrain. Deux boucles de dispatch (PC et Android), deux CMakeLists, kChunks. C'est ici que l'owner juge la fine epaisseur.

## Livrable
`soft_shell_defects` = 0, somme de termes publies SEPAREMENT.
1. UN SEUL CODE DE SOMMET, TROIS PASSES : compte de programmes lies incluant `soft_displace.glsl` = 3 ; ecart de profondeur de la coque entre prepasse, ombre et couleur sur vantages nommes = 0 (sonde refset_read_scene_depth).
2. LE TERRAIN CEDE, LA COQUE REMPLACE : compte de triangles cedes = compte de triangles eligibles ; compte de pixels de couture (ecart de profondeur > 1 quantum le long des frontieres) = zero ; aucun z-fight mesure.
3. L'APPARENCE AU REPOS EST HERITEE : UV, color_index (couleur du jour) et normale des enfants interpoles des parents ; ecart de couleur coque/terrain sur un vantage a epaisseur forcee a 0 = zero.
4. OFF = ABSENCE : binaire-temoin sans la couche compilee, image bit-identique ; compagnon absent = `soft_missing=1` et terrain intact ; temps de chargement asynchrone, 0 ms bloque.
PREUVE : `FEATURE soft-shell-renderer armed=1 hits=<triangles de coque dessines par image>` + la ligne `soft_shell_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_shell_defects == 0` dans `reports/soft-shell-renderer/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-shell-renderer device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur la neige compacte de Snowy Mountain et le sable de Geyser Rock, a angle rasant et dans l'ombre de contact : Jak parait s'enfoncer de quelques centimetres, sans marche ni scintillement aux bords. C'est le reglage des 3-4 cm que tu juges ; la deformation viendra apres..

## Hors perimetre
Aucune deformation dynamique, aucune tuile, aucun interacteur. Ne touche pas aux shaders du terrain autrement que pour ceder des index. Tout ce qui n'est pas cet item.
