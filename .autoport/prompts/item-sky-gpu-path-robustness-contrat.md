# Le chemin GPU du ciel cesse de reposer sur des defauts implicites et sur un ASSERT nu — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

QUATRE SIGNALEMENTS DU 12/09 (reports/hdr-sky-gpu-alpha/FINDINGS.txt), sur un chemin que la mesure vient d'ouvrir apres des mois sans aucune preuve.
1. `SkyBlendGPU.cpp:71` : `glBindBuffer(GL_ARRAY_BUFFER, old_framebuffer)` en fin de constructeur. `old_framebuffer` vient d'un `glGetIntegerv(GL_FRAMEBUFFER_BINDING)` : c'est un nom de FRAMEBUFFER passe comme nom de tampon de SOMMETS. Les deux espaces de noms n'ont aucun rapport.
2. `shaders/sky_blend.frag:33` : `tex_T0` n'est jamais pose par un `glUniform1i`. Le code repose sur la valeur par defaut d'un echantillonneur, l'unite 0. `tex_prev` est pose explicitement sur l'unite 1 par le chantier precedent : les deux echantillonneurs du meme shader suivent donc deux regles differentes.
3. `SkyBlendGPU.cpp:143` : `ASSERT(adgif.alpha().data == 0x8000000068)`. Le chemin suppose le melange PS2 `Cs+Cd` et n'a AUCUN repli si le jeu envoie un autre mode. Le chemin CPU porte le meme ASSERT. Meme classe que l'ASSERT nu des reductions du halo : le processus MEURT, et le symptome ne ressemble pas a sa cause.
4. `BucketRenderer.h:43` : `use_sky_cpu` vaut vrai par defaut et n'a AUCUN reglage persistant — seule la case ImGui « Sky CPU » le bascule. Aucun fichier de reglages, aucune propriete. Le chantier precedent a du ajouter `OG_SKY_GPU` pour que le harnais puisse seulement l'exercer.

## Livrable — le contrat, en entier

`sky_gpu_robustness_defects` = 0, somme de termes publies SEPAREMENT.
1. La liaison de fin de constructeur vise le bon espace de noms, et la preuve publie l'etat RELU apres coup : le nom de tampon lie et le nom de framebuffer lie, les deux, pas une affirmation.
2. Chaque echantillonneur du shader recoit son unite EXPLICITEMENT. Publier le compte d'echantillonneurs et le compte de ceux dont l'unite a ete posee : les deux doivent etre egaux.
3. L'ASSERT devient un repli MESURE : si le mode de melange n'est pas celui attendu, le chemin le dit et retombe, il ne tue pas le processus. Publier le compte de modes rencontres, par valeur. Faire la meme chose sur le chemin CPU, qui porte le meme ASSERT.
4. `use_sky_cpu` devient un reglage lisible et persistant comme les autres, pas une case ImGui seule. Publier la valeur observee au demarrage et sa provenance.
5. Rien de ce que `hdr-sky-gpu-alpha` a mesure ne regresse : reprendre ses cles d'alpha et montrer qu'elles gardent leurs valeurs, controles semes compris.

## Hors perimetre

Ne touche pas au chemin CPU du ciel, sauf pour son ASSERT. Ne change ni la courbe, ni la borne d'alpha posee par le chantier precedent.

## Ou l'owner regardera

Le ciel sur PC. Sur l'appareil ce chemin ne tourne pas.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

