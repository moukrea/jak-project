# Le chemin GPU du ciel : son poids de melange peut depasser 1,0 depuis que la cible est flottante

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SIGNALEMENT DU CHANTIER A, 11/09 (reports/hdr-source-range/FINDINGS.txt), SkyBlendGPU.cpp:175. Sur la cible flottante ouverte par `hdr-source-range`, l'accumulation `glBlendFunc(GL_ONE, GL_ONE)` laisse desormais l'ALPHA du ciel DEPASSER 1,0 la ou le 8 bits le saturait. Aucun facteur de melange a fonction fixe ne le bornerait sans changer sa valeur ailleurs : `GL_SRC_ALPHA_SATURATE` rend 1 sur le canal alpha. Ce chemin n'est PAS celui de l'appareil (`use_sky_cpu` vaut vrai par defaut, BucketRenderer.h:43, bascule ImGui seule) et n'est couvert par AUCUNE preuve : un poids de melange superieur a 1,0 y sur-composerait le ciel SUR BUREAU sans qu'aucune porte le voie. L'owner a valide la sortie HDR sur PC le 11/09 : ce chemin cesse d'etre un coin mort.

## Livrable
`hdr_sky_gpu_alpha_defects` = 0, somme de termes publies SEPAREMENT.
1. Le chemin GPU du ciel est EXERCE par la preuve — publier `hdr_sky_gpu_frames` et le dire explicitement si la bascule `use_sky_cpu` a du etre forcee. Un zero d'images se lit « pas mesure », jamais « pas de defaut ».
2. L'alpha maximum accumule, publie : `hdr_sky_gpu_alpha_max_x1000`, avec son denominateur en composantes relues. C'est la grandeur qui dit si le debordement existe.
3. Si elle depasse 1,0 : le supplement est borne A SA SOURCE — le poids du melange — et non par un ecretage en aval. Publier la valeur avant et apres, sur la MEME course.
4. Le chemin CPU du ciel, celui de l'appareil, reste identique AU BIT : publier son maximum et son compte de pixels differents avant/apres cet item.

## Preuve exigee
`hdr_sky_gpu_alpha_defects == 0` dans `reports/hdr-sky-gpu-alpha/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-sky-gpu-alpha x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Le ciel, chemin GPU (bureau) : `SkyBlendGPU`, bascule `use_sky_cpu` dans ImGui..

## Hors perimetre
Ne touche pas au chemin CPU du ciel, ni a la courbe, ni au format des etages. Ne fabrique aucune difference visible sur l'appareil : ce chemin n'y tourne pas.
