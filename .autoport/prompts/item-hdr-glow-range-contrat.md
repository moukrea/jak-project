# Le halo mesure pour de vrai : la sonde du chantier A n'a jamais tourne, et le cout en cadence n'est pas chiffre — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

RELEVE DU 11/09 SUR LA PREUVE ET LES SIGNALEMENTS DE `hdr-source-range` (reports/hdr-source-range/proof.txt et FINDINGS.txt).
LE FAIT CENTRAL : sur 10 560 images d'appareil et 8 573 images x86 — dont un teleport dans village1 — `GlowRenderer::flush()` (GlowRenderer.cpp:859) est sorti sur `!m_next_sprite` A CHAQUE FOIS. Pas UN sprite de halo n'a ete soumis. D'ou `hdr_src_glow_state` = 2, que hdr.cpp:695 traduit par « JAMAIS TENTE », et 0 image, 0 pixel, 0 depassement. Ce zero ne dit pas « pas de depassement » : il dit « pas de mesure ». Le chemin du halo — sonde plus cinq reductions, 2,18 Mo — n'est couvert par AUCUNE porte d'AUCUN item, et AUCUNE scene connue du harnais ne l'exerce. Il peut etre casse depuis des mois sans que rien le voie.
DEUX DECLARATIONS FAUSSES DEJA CORRIGEES PAR LE CHANTIER A, a ne pas re-supposer : le site GlowRenderer.cpp:574 declarait lire la COULEUR de scene vers une cible 8 bits alors que le blit de la ligne 587 ne copie que `GL_DEPTH_BUFFER_BIT` — le halo ne lit jamais la couleur de scene ; et PLAN.md §2.2 (« le glow lit la scene dans une cible 8 bits : un soleil a 15x y contribue comme un blanc a 1,0 ») reposait sur cette declaration.
AVERTISSEMENT DE MESURE (reports/hdr-curve-input/FINDINGS.txt) : `ref_peak_now` (hdr_output.cpp) et `probe_scene` (hdr.cpp) font des relectures SYNCHRONES pendant qu'on mesure. Toute cadence relevee sous instrument est fausse par construction.

## Livrable — le contrat, en entier

`hdr_glow_range_defects` = 0, somme de termes publies SEPAREMENT.
1. LA COUVERTURE D'ABORD, pas le depassement. Publier `hdr_glow_flush_calls` et `hdr_glow_sprites_submitted` sur toute la course. Etablir si ce chemin est ATTEIGNABLE sur ce portage, et nommer ce qui l'alimente. S'il ne l'est pas, c'est CA la reponse de l'item : on la publie chiffree, on ne va pas chercher une scene qui n'existe peut-etre pas. Ne pas confondre avec le halo que l'owner VOIT sur les feux et les portails — s'il est dessine par un autre chemin, dire lequel.
2. `hdr_glow_state` dit que la sonde A TOURNE ou POURQUOI elle n'a pas tourne. Les quatre raisons du retour anticipe de `probe_glow` (mesure eteinte, largeur nulle, hauteur nulle, cible trop grande) deviennent quatre valeurs DISTINCTES : un zero ne doit plus jamais pouvoir se lire comme « pas de depassement ».
3. Si et seulement si la sonde tourne : `hdr_glow_overbright_px`, `hdr_glow_max_x1000` et leur denominateur, tous les trois. Un halo qui ne depasse jamais 1,0 est un RESULTAT, pas un echec — mais il doit etre mesure et dit comme tel, jamais suppose.
4. `ASSERT(status == GL_FRAMEBUFFER_COMPLETE)` nu a GlowRenderer.cpp:250, sans repli : sur un pilote qui accepterait la sonde et refuserait un etage, le processus MEURT a l'init du renderer et le symptome ne ressemble pas a sa cause. Repli 8 bits MESURE, compte publie.
5. Le format des etages est LATCHE a la construction (GlowRenderer.cpp:184, SkyBlendCPU.cpp:21, SkyBlendGPU.cpp:19) : basculer le maitre Recharged en jeu ne recree pas les cibles. Publier si la bascule prend effet ou si elle exige un redemarrage — une porte qui mesurerait apres bascule lirait des etages 8 bits sur un binaire correct.
6. Le cout en cadence sur le Redmi, AVANT et APRES, releve HORS course de mesure : deux courses, meme lieu, meme binaire, nombre d'images de chacune publie. La memoire est deja chiffree par le chantier A (6 904 320 o d'etages flottants, 196 608 o restes en 8 bits) : la reprendre, ne pas la refaire.

## Hors perimetre

Ne change ni la courbe ni son ancre : c'est le chantier B. Le format du tampon de scene (`hdr_src_scene_fmt` = RGBA8) n'est pas de ce chantier. Aucun appareil code en dur.

## Ou l'owner regardera

Le halo : les feux et les portails de teleportation — hutte du Sage vert, Sandover Village.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

