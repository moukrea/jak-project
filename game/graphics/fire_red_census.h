#pragma once

// fire_red_census — LE RECENSEMENT DE CE QUI DESSINE EN ROUGE SUR OU AU-DESSUS DES FEUX
// (item `fire-red-particles`, owner 2026-09-10 : « un truc louche au dessus des feux, ca fait
// des particules rouges bizarres, probablement un des tests/debugs qui est reste la »).
//
// CE QU'IL COMPTE, ET POURQUOI CES COMPTEURS-LA.
// ---------------------------------------------
// Le foyer du maire de Sandover (`goal_src/jak1/levels/village1/village1-part.gc:505`,
// `group-village1-mayor-fire`) est fait de cinq parts d'ORIGINE :
//   * 410 / 412  `bigpuff`  — la fumee.
//   * 2292 (x60) `hotdot`   — les braises. `:r 256 :g 128 :b 128`, `fade-g/-b -0.711` : elles
//                             VIREENT au rouge en vieillissant. C'est le jeu d'origine.
//   * 411        `middot`   — `:r 256 :g 0 :b 0` et surtout `:a 0.0` SANS `fade-a` : un PORTEUR
//                             invisible, pose a 1..1,5 m AU-DESSUS du foyer, dont le seul role
//                             est de jouer « fire-pop » et de porter (`:binding 2292`) les
//                             braises. Le jeu d'origine ne le montre JAMAIS.
//   * 413        aux-list   — le distordeur de chaleur.
// Donc « une particule rouge au-dessus du feu que le jeu d'origine ne dessine pas » a une
// signature exacte et falsifiable : un sprite de texture `middot`, rouge pur (g et b nuls),
// qui ATTEINT le tampon. Il l'atteint de deux facons, et les deux sont comptees separement :
//   - `carrier_alpha` : son alpha passe le test d'alpha du chemin sprite (`a >= alpha_min`) ;
//   - `carrier_afail` : son alpha ECHOUE le test, mais le melange de son seau ne pondere pas
//                       par l'alpha source (`SRC_0_FIX_DST` / `SRC_DST_FIX_DST`, fix=128/64) et
//                       la seconde passe `AFAIL_NO_DEPTH_WRITE` le dessine quand meme.
// S'y ajoutent deux familles qui ne peuvent appartenir a aucun jeu d'origine :
//   - `nonfinite`   : un sprite dont la position n'est pas finie ou sort du monde. C'est le mode
//                     de panne connu des particules LIEES sur arm64 (`sparticle_launcher.cpp:694`
//                     — quaternion NaN, enfant ne a ±1e9..1e13).
//   - `debug_draw`  : un tirage issu d'un site de dessin rouge de DEBUG (DirectRenderer
//                     `DEBUG_RED`, sondes du GlowRenderer, effacement rouge du TextureAnimator).
//                     Tous sont derriere une case ImGui ; les compter rend leur zero MESURE au
//                     lieu de suppose.
// `fire_debug_particles` est la somme de ces quatre-la, prise au MAXIMUM sur une image : la
// borne demandee par l'item. Les braises d'origine ne sont PAS dedans — elles sont publiees a
// part (`fire_red_sprites_max`) parce que le perimetre interdit d'y toucher.
//
// LE DENOMINATEUR. Un zero obtenu parce que l'instrument n'a rien vu ne vaut rien. On publie
// donc aussi le nombre d'images recensees et le nombre de sprites de feu REELLEMENT dessines :
// un `fire_debug_particles=0` avec `fire_sprites_seen=0` n'est pas un verdict, c'est un silence.

#include <cstdint>

namespace fire_red_census {

// Vrai quand le harnais n'a pas desarme CET item. Defaut : arme (le binaire de l'owner).
bool armed();

// Un sprite de monde d'un seau dont la texture est nommee `texture_name`, tel qu'il part au
// tampon. `x,y,z` = sa position monde brute (unites GOAL), `r,g,b,a` = sa couleur de sommet
// APRES l'empaquetage 8 bits de Sprite3 (donc dans [0,1]), `alpha_min` = le plancher du test
// d'alpha en vigueur pour ce seau, `alpha_blend` = `(int)DrawMode::AlphaBlend` du seau,
// `double_draw` = ce seau fait-il la seconde passe AFAIL.
void note_sprite(const char* texture_name,
                 float x,
                 float y,
                 float z,
                 float r,
                 float g,
                 float b,
                 float a,
                 float alpha_min,
                 int alpha_blend,
                 bool double_draw);

// UN SPRITE 2D AU POINT D'EMPAQUETAGE — l'oracle de la couleur.
//
// POURQUOI CE COMPTEUR EXISTE. `Sprite3::do_block_common` empaquete la couleur que GOAL a ecrite
// (des flottants a l'echelle 0..255, que RIEN ne borne par le HAUT : le seul clamp du chemin
// sparticle est le `vmaxx ... vf0` a >= 0) en quatre octets. Depuis l'amont `f4941706a6`
// (« wrap sprite rgba to 0-255 », 2024-06-04) cet empaquetage etait un REPLIEMENT `(int)v & 0xff`.
// Un `defpart` d'origine qui ecrit `:r 256.0` — le foyer du maire (411, 2292) et le portail de
// teleportation le font — voyait donc son canal rouge rendu NUL, puis basculer d'un coup a 255
// des que le `fade-r` du launcher suivant le faisait passer sous 256. C'est une couleur que la
// donnee de Naughty Dog ne decrit nulle part : elle n'appartient pas au jeu d'origine.
//
// L'ORACLE. On donne a l'instrument la couleur SOURCE et les quatre octets REELLEMENT ecrits
// dans le sommet. La reference est calculee a part, depuis la source seule : la SATURATION
// `v < 0 -> 0 ; v > 255 -> 255 ; sinon (int)v`. Trois grandeurs en sortent :
//   * `pack_foreign`  — le sommet differe de la reference. C'est la grandeur de la PORTE : elle
//                       entre dans `fire_debug_particles` et doit tomber a 0.
//   * `pack_oldwrap`  — le nombre de sprites sur lesquels l'ANCIENNE politique `& 0xff` donnait
//                       une autre couleur que la reference. Ce compte reste NON NUL apres la
//                       correction : c'est lui qui prouve que l'oracle a des dents, et c'est la
//                       taille exacte du defaut que l'owner voyait.
//   * `pack_oor`      — le nombre de sprites dont une composante SOURCE sort de [0,255]. Sans
//                       lui, un `pack_foreign=0` pourrait n'etre qu'une condition absente.
// LE HUD EST A PART, ET CE N'EST PAS UN AMENAGEMENT. Le clignotement « eco bas » du HUD
// (`goal_src/jak1/engine/ui/hud-classes.gc:1276-1279` : `(set! arg3 (* arg3 2))` sur un canal
// vert a 128) s'appuie DELIBEREMENT sur le repliement — c'est ce que la PR amont #3549
// retablissait. Ce n'est pas une particule du monde, l'owner ne parle pas de lui, et la
// correction ne le touche pas : il est compte separement (`fire_pack_foreign_hud`) et n'entre
// pas dans la porte. Tout sprite du monde, lui, y entre.
//
// `sr,sg,sb,sa` : la couleur source, echelle 0..255, non bornee. `pr,pg,pb,pa` : les octets
// ecrits. `texture_name` : l'emetteur, publie nommement dans `fire_pack_emitters`.
void note_pack(const char* texture_name,
               bool hud,
               float sr,
               float sg,
               float sb,
               float sa,
               int pr,
               int pg,
               int pb,
               int pa);

// LE CHEMIN DISTORTEUR — L'ECHANTILLONNEUR, ET CE QU'IL DESSINE.
// ---------------------------------------------------------------
// POURQUOI LUI. L'owner decrit de GRANDES FORMES POLYGONALES qui RECOUVRENT le feu ET le
// portail, avec l'effet correct DESSOUS. Dans tout le chemin sprite, un seul dessinateur
// produit des EVENTAILS de 3 a 11 cotes au lieu de quads : `Sprite3_Distort`. Et un seul
// remplace ses pixels au lieu de s'y ajouter : lui encore. Sa cible est
// `2 * u_color * texture(copie-de-scene)` et son alpha vaut 1 — la copie de scene n'a PAS de
// canal alpha (`GL_RGB`), donc `texture().a` rend 1,0 et le melange `(Cs-Cd)*As+Cd` ecrase le
// fond. Une copie de scene qui n'a pas eu lieu donne donc, exactement, un APLAT OPAQUE de la
// forme du polygone. C'est la seule construction du moteur qui produise la signature decrite,
// et elle est PARTAGEE par le feu et le portail : tous deux emettent des particules `aux-list`,
// et `sprite-draw-distorters` est leur unique consommateur.
//
// CE QUE CET INSTRUMENT MESURE, ET CE QU'IL NE MESURE PAS. Il ne lit aucun reglage et aucun
// drapeau : il lit l'etat REEL de l'echantillonneur au point de dessin (statut du framebuffer
// de copie, erreur GL de la recopie, et une comparaison pixel a pixel entre la scene et sa
// copie), et la geometrie REELLE de chaque eventail, recalculee sur les MEMES entrees que le
// nuanceur (table sinus + donnees d'instance). Un « tout va bien » deduit d'un booleen serait
// un miroir ; ici la grandeur vient du pilote et de la table.

// Un sprite de distorsion tel que le nuanceur va le dessiner.
//   `res`    : son nombre de cotes. Hors [3,11], l'index de table est lu HORS BORNES.
//   `area`   : la fraction de l'ecran couverte par son eventail, dans [0,1].
//   `st_lo`, `st_hi` : l'intervalle des coordonnees de texture qu'il echantillonne. Hors
//              [0,1] l'echantillonneur rend la couleur du BORD, etalee — donc un aplat.
//   `mismatch` : L'ORACLE ANALYTIQUE, et il n'a besoin d'AUCUNE seconde plateforme.
//              L'effet consiste a redessiner ce qui est DERRIERE l'eventail, deplace. Le sommet
//              CENTRAL, lui, n'est pas deplace : il doit donc echantillonner la copie de scene
//              EXACTEMENT a sa propre position ecran. L'algebre le confirme sur la donnee
//              d'origine : le nuanceur pose u = st.x et le producteur GOAL pose
//              st.x = (x - 1792) / 512, qui est precisement (ndc_x + 1) / 2 avec
//              ndc_x = (x - 2048) / 256 ; de meme v = (1 - st.y) - (1 - 448/512)/2 vaut
//              (2176 - y) / 256, qui est (ndc_y + 1) / 2 avec ndc_y = -(y - 2048)/128 — mais
//              SEULEMENT si `screen-hy` vaut 112 (NTSC) et `SCISSOR_HEIGHT` 448. En PAL
//              (`screen-hy` = 128) l'accord se rompt de 1/16 d'ecran, l'echantillonnage sort de
//              [0,1], et `GL_CLAMP_TO_EDGE` etale la couleur du BORD : un APLAT.
//              `mismatch` est cet ecart, mesure sur l'appareil seul.
//   `pos`, `scale`, `st` : la donnee BRUTE que `sprite-draw-distorters` a produite pour cet
//              eventail. `scale` est bornee a 128 par le producteur (sprite-distort.gc:215-218) :
//              au-dela, c'est que la borne n'a pas tenu.
void note_distort_sprite(int res,
                         float area,
                         float st_lo,
                         float st_hi,
                         float mismatch,
                         const float* pos,
                         const float* scale,
                         const float* st);

// L'ETAT DE L'ECHANTILLONNEUR, une fois par image ou le distorteur dessine.
//   `fbo_status`  : `glCheckFramebufferStatus` de la cible de la recopie (0x8CD5 = complet).
//   `blit_err`    : `glGetError` APRES `glBlitFramebuffer` (0 = la recopie a eu lieu).
//   `samples`     : le nombre d'echantillons du framebuffer de scene. > 1 avec des formats
//                   differents, la recopie est INTERDITE par OpenGL ES et ne fait rien.
//   `probe_px`    : pixels compares entre la scene et sa copie (0 = pas de sonde cette image).
//   `probe_diff`  : ceux qui different. C'est ce qui separe « texture resolue » de « repli ».
//   `sample`      : un couple scene/copie recopie tel quel, pour que le chiffre soit lisible.
void note_distort_frame(unsigned fbo_status,
                        unsigned blit_err,
                        int samples,
                        int sprites,
                        int draws,
                        int probe_px,
                        int probe_diff,
                        int probe_maxdelta,
                        const char* sample);

// Vrai quand le HARNAIS mesure CET item. La sonde de recopie de scene coute deux lectures de
// pixels (donc deux arrets du pipeline) : elle ne doit pas tourner dans le binaire que l'owner
// joue. Les compteurs qui ne coutent rien, eux, restent toujours actifs.
bool probe_enabled();

// LA TAILLE DU QUAD DESSINE — la seconde lecture de « GRANDE FORME ».
// ------------------------------------------------------------------
// Le distorteur ecarte, il reste une facon d'obtenir une grande forme coloree : un QUAD de
// sprite dont l'echelle a enfle. `scale-x` et `scale-y` sont VIEILLIS a chaque image, et sur
// arm64 ce vieillissement passe par un chemin NEON (`sparticle.cpp:683-742`) qui n'existe pas
// sur x86 — ou la reference scalaire (`:744-765`) tourne a sa place. Ce chemin ne borne la
// taille QUE PAR LE BAS (`vmaxx ... vf0`, :732-733) : rien, nulle part, ne la borne par le haut.
// Un sprite qui grandit sans fin finit par couvrir l'ecran, et il porte la couleur du feu
// (rouge) ou son repliement a 256 (noir). L'instrument publie donc la taille REELLEMENT
// envoyee au tampon, et nomme l'emetteur des plus grandes.
void note_sprite_size(const char* texture_name, float sx, float sy);

// L'ECHANTILLONNEUR DU DISTORTEUR, LU AU POINT DE LECTURE.
// -------------------------------------------------------
// `distort_draw_common` lie la copie de scene par un `glBindTexture` NU
// (`Sprite3_Distort.cpp`) : il atterrit sur l'unite de texture HERITEE du renderer precedent,
// alors que `setup_opengl_from_draw_mode` ne bascule sur l'unite 0 qu'APRES, et que le sampler
// `framebuffer_tex` n'est assigne nulle part (`Shader.cpp` ne traite que `tex_T1..tex_T29`,
// la boucle part a i=1) — il vaut donc 0 et le fragment lit TOUJOURS l'unite 0. Quand l'unite
// heritee n'est pas 0, la copie de scene part sur l'unite N et l'eventail — opaque, parce que
// `GL_TEXTURE_SWIZZLE_A = GL_ONE` force son alpha a 1 — etale la texture qu'un AUTRE renderer
// a laissee sur l'unite 0. C'est le site PARTAGE par tous les feux et tous les portails
// (`aux-list` -> `sprite-draw-distorters`), et la signature est exactement celle decrite : un
// aplat polygonal opaque par-dessus un effet correct dessous.
//
// Deux mesures, pas une :
//  * `note_distort_bind` — AU POINT DE LIAISON, l'unite heritee et ce que l'unite 0 portait
//    alors. C'est la REPRODUCTION : elle compte les dessins qui auraient echantillonne une
//    texture etrangere.
//  * `note_distort_sampler` — AU POINT DE TIRAGE, programme lie, ce que l'unite REELLEMENT
//    lue par le sampler porte, compare a la copie de scene. C'est la grandeur de la PORTE.
// `loc` est publie tel quel : un uniforme inactif rend -1 et lit quand meme l'unite 0 ; sans
// ce chiffre, un « 0 mismatch » ne se distingue pas d'une localisation jamais trouvee.
void note_distort_bind(int inherited_unit, unsigned bound_on_unit0, unsigned scene_copy_tex);
void note_distort_sampler(int loc, int sampler_unit, unsigned bound, unsigned scene_copy_tex);

// Un dessin du chemin sprite et l'etat de SON echantillonneur. `resolved` faux = la texture
// demandee n'existait pas et le seau dessine avec le damier de secours.
void note_sprite_sampler(bool resolved);

// Un tirage issu d'un site de dessin ROUGE de debug. `site` est son nom, publie tel quel.
void note_debug_red_draw(const char* site);

// Fin d'image : arrete les maxima et publie. Appele une fois par image, du meme endroit que
// `autoport_proof::frame_tick()`.
void end_frame();

}  // namespace fire_red_census
