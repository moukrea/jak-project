> LIS D'ABORD `prompts/item-sky-gpu-path-robustness-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le chemin GPU du ciel cesse de reposer sur des defauts implicites et sur un ASSERT nu

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
QUATRE SIGNALEMENTS DU 12/09 (reports/hdr-sky-gpu-alpha/FINDINGS.txt), sur un chemin que la mesure vient d'ouvrir apres des mois sans aucune preuve.
1. `SkyBlendGPU.cpp:71` : `glBindBuffer(GL_ARRAY_BUFFER, old_framebuffer)` en fin de constructeur. `old_framebuffer` vient d'un `glGetIntegerv(GL_FRAMEBUFFER_BINDING)` : c'est un nom de FRAMEBUFFER passe comme nom de tampon de SOMMETS. Les deux espaces de noms n'ont aucun rapport.
2. `shaders/sky_blend.frag:33` : `tex_T0` n'est jamais pose par un `glUniform1i`. Le code repose sur la valeur par defaut d'un echantillonneur, l'unite 0. `tex_prev` est pose explicitement sur l'unite 1 par le chantier precedent : les deux echantillonneurs du meme shad […suite dans le contrat]

## Livrable
`sky_gpu_robustness_defects` = 0, somme de termes publies SEPAREMENT.
1. La liaison de fin de constructeur vise le bon espace de noms, et la preuve publie l'etat RELU apres coup : le nom de tampon lie et le nom de framebuffer lie, les deux, pas une affirmation.
2. Chaque echantillonneur du shader recoit son unite EXPLICITEMENT. Publier le compte d'echantillonneurs et le compte de ceux dont l'unite a ete posee : les deux doivent etre egaux.
3. L'ASSERT devient un repli MESURE : si le mode de melange n'est pas celui attendu, le chemin le dit et retombe, il ne tue pas le processus. Publier le compte de modes rencontres, par valeur. Faire la meme chose sur le chemin CPU, qui porte le meme ASSERT […suite dans le contrat]

## Preuve exigee
`sky_gpu_robustness_defects == 0` dans `reports/sky-gpu-path-robustness/proof.txt`.
Le proof se produit par `lib/proof_run.sh sky-gpu-path-robustness x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Le ciel sur PC. Sur l'appareil ce chemin ne tourne pas..

## Hors perimetre
Ne touche pas au chemin CPU du ciel, sauf pour son ASSERT. Ne change ni la courbe, ni la borne d'alpha posee par le chantier precedent.
