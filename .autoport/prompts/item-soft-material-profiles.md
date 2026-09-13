# Trois profils de matiere, en donnees : la neige compacte n'est pas une neige profonde floue

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 16 de l'artifact et sections 2, 12 de la SPEC. Profils dans le depot d'assets Recharged (owner 29/08), pas dans l'APK ni en dur : epaisseur, durete, rayon, deplacement lateral, relaxation, vieillissement, shading ; multiplicateur par niveau. Profonde : douce, large, bourrelets ; compacte : dure, nette, persistante ; sable : s'affaisse, pas de bourrelet.

## Livrable
`soft_profile_defects` = 0, somme de termes publies SEPAREMENT.
1. UN PROFIL EST UNE DONNEE : compte de valeurs de profil ecrites en dur dans une source C++ ou GLSL = zero ; changer un profil ne recompile rien (temoin publie).
2. LES TROIS PROFILS SONT DISTINCTS, MESURABLEMENT : profondeur par pas, rayon, relaxation a 60 s publies par matiere ; ecarts au-dela des planchers declares sur au moins trois axes.
3. LE MULTIPLICATEUR PAR NIVEAU EST LU : epaisseur effective publiee par niveau, egale au profil x multiplicateur.
4. LE PROFIL NE DEPEND PAS DU PALIER : les memes valeurs publiees en Bas et en Ultra (compte d'ecarts = zero).
PREUVE : `FEATURE soft-material-profiles armed=1 hits=<brins de matiere ayant recu un profil>` + la ligne `soft_profile_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_profile_defects == 0` dans `reports/soft-material-profiles/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-material-profiles device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : La neige compacte garde des contours nets et persistants ; la profonde s'ouvre large ; le sable s'affaisse doucement..

## Hors perimetre
Pas de bourrelet fin, pas de shading de trace : items suivants. Tout ce qui n'est pas cet item.
