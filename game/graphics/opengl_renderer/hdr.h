#pragma once

// hdr — LA CHAINE HDR ET SON RECENSEMENT (item `lighting-hdr`, SPEC-refonte-lumiere §4.5).
//
// LE DEFAUT. §2.3 cause 6 : `make_fbo(..., GL_RGBA8, ...)` partout, et un genou de compression
// ecrit A LA MAIN dans chaque chemin d'ombrage (`RT_KNEE` et ses jumeaux, chacun dans son
// morceau de GLSL). Aucune marge au-dessus de 1 : un eclat speculaire,
// un bloom, une adaptation d'exposition n'ont pas la place d'exister, et « combien de fois
// l'image est-elle compressee avant l'ecran » n'a pas de reponse.
//
// CE QUE L'ITEM LIVRE. Le tampon de scene passe en RGBA16F (repli declare et mesure), les
// genoux quittent les shaders, et UNE seule compression de plage subsiste sur le chemin
// d'affichage : le programme `tonemap`, tire depuis un seul endroit du code.
//
// LA GRANDEUR DE LA PORTE, ET POURQUOI ELLE N'EST PAS UN MIROIR.
// -------------------------------------------------------------
// `tonemap_sites` n'est pas un booleen « j'ai fait le refactor » publie par le refactor. C'est
// une SOMME de trois recensements independants, chacun publie a cote :
//
//   `tonemap_sites_explicit`  nombre d'emplacements de code DISTINCTS (fichier:ligne) d'ou le
//                             programme de tone map a REELLEMENT ete tire pendant la course.
//                             Deux appels a `tonemap_draw` depuis deux endroits => 2.
//   `tonemap_sites_shader`    nombre de programmes fragment, AUTRES que `tonemap`, dont le
//                             texte REELLEMENT COMPILE (releve dans `Shader::build`, apres
//                             l'expansion des `#include`) porte encore une compression de
//                             plage. Oublier un `RT_KNEE` le fait monter.
//   `tonemap_sites_implicit`  nombre d'emplacements DISTINCTS du chemin d'affichage ou une
//                             couleur de scene flottante a ete recopiee dans une cible 8 bits
//                             pendant la course. Une conversion de format est une compression
//                             de plage que personne n'a ecrite : elle compte comme un site.
//
// CE QUI N'EST PAS COMPTE, ET POURQUOI. L'encodage `pow(x, 1/2.2)` des chemins d'ombrage
// RECHARGED n'est PAS une compression de plage : c'est une bijection monotone de [0,+inf) sur
// [0,+inf), sans plafond et sans perte, et c'est l'encodage COMMUN du tampon — les renderers
// d'origine (ciel, merc, sprites, eau) y ecrivent deja des couleurs d'affichage, et le melange
// PS2 est defini dans cet espace. Le retirer d'un seul chemin melangerait deux encodages dans
// le meme tampon. Il est neanmoins recense et publie sous `hdr_oetf_progs` : rien n'est cache.
// De meme, les lectures de la scene faites par les EFFETS (AO, glow, distorsion, capture de
// fond de menu) sont publiees sous `hdr_aux_clamped_reads`, avec leur denominateur. La copie
// couleur de distorsion, recomposee dans la scene, alimente aussi le verdict d'ecretage
// intermediaire ; les lectures de profondeur ou les masques ne lui sont pas assimiles.

#include <cstdint>
#include <string>

#include "common/versions/versions.h"

#include "game/graphics/pipelines/opengl.h"

class Shader;

namespace hdr {

// -------------------------------------------------------------------------------- regime ----

// La chaine HDR est-elle active pour cette image ? Master RECHARGED arme, reglage
// `recharged_hdr` a vrai, et feature ARMEE (`armed_for("lighting-hdr")` — le bras `--off` du
// harnais eteint donc la chaine POUR DE VRAI : l'ablation est causale, pas seulement muette).
// Le mode ORIGINE (master OFF) ne passe JAMAIS par ici.
bool chain_active();

// Fige le regime HDR pour un render ; l'echelle de repli des formats reste mutable.
class FrameScope {
 public:
  FrameScope();
  ~FrameScope();

  FrameScope(const FrameScope&) = delete;
  FrameScope& operator=(const FrameScope&) = delete;

 private:
  bool m_previous_active;
  bool m_previous_chain;
};

// Le format d'attachement couleur demande pour le tampon de scene, apres l'echelle de repli.
// GL_RGBA16F -> GL_R11F_G11F_B10F -> GL_RGBA8 (§4.5).
GLenum scene_color_format();

// Le FBO de scene vient d'etre construit avec ce format : complet ou non. Fait descendre
// l'echelle de repli d'un cran quand il ne l'est pas. Retourne vrai s'il faut re-essayer.
bool note_scene_fbo_result(GLenum requested, bool complete);

bool format_is_float(GLenum fmt);

// ── (ao-indirect-clean, terme 5) UNE VALEUR DU TAMPON DE SCENE, EN OCTET AFFICHE ────────────
// Le point F de `ao-indirect-clean` compte des pixels dont la LUMINANCE change de plus de 2/255
// « sur l'image rendue ». Sur l'appareil ce tampon est en RGBA16F : ses valeurs sont deja dans
// l'encodage d'affichage du jeu (tonemap.frag:7-11), mais le plafond a 1,0 n'y est pas encore
// pose et l'epaule SDR n'y est pas encore appliquee. Comparer les valeurs BRUTES mesurerait un
// ecart que l'ecran ne montre pas. Cette fonction est le miroir scalaire, PAR CANAL, de la
// branche SDR de `tonemap.frag:222-239`, avec les MEMES uniformes vivants (exposition, coude,
// courbe) : elle n'invente aucune constante, elle relit celles que la passe pousse.
// Elle vit ICI et pas chez l'appelant : une troisieme copie de l'epaule serait une constante
// qui derive en silence le jour ou la courbe change.
// Les trois parametres vivants de la courbe, relus UNE FOIS par image : `u_hdr_exposure`
// (qui contient un `pow`), `u_hdr_knee`, `u_hdr_curve`. Les appeler par pixel coutait trois
// `std::pow` par pixel — 290 millions sur une course de preuve.
struct SdrEncode {
  float exposure = 1.f;
  float knee = 1.f;
  int curve = 0;
};
SdrEncode sdr_encode_params();
uint8_t sdr_display_u8(const SdrEncode& p, float v);
const char* format_name(GLenum fmt);

// ------------------------------------------------------------------------- le site unique ----

// Tire le quad plein ecran de tone map : `src_tex` -> `dst_fbo`. `site` nomme l'emplacement de
// code appelant (`__FILE__ ":" __LINE__`) ; c'est LUI qui est recense, pas un compteur maison.
// Compte un `note_hit()` par image tone-mappee. Retourne faux si le programme n'est pas
// utilisable — l'appelant doit alors retomber sur son blit, que le recensement verra.
// hdr-curve-input : `src_w` / `src_h` sont les dimensions du TAMPON DE SCENE (celui de
// `src_tex`), pas celles de la destination. La reduction par maximum de `analyze_scene` en a
// besoin pour couvrir la totalite des pixels ; les deduire de `dst_w` / `dst_h` serait faux des
// que la scene est rendue a une autre echelle que l'interface (« upscale 3D »).
bool tonemap_draw(Shader& shader,
                  const char* site,
                  GLuint src_tex,
                  int src_w,
                  int src_h,
                  GLuint dst_fbo,
                  int dst_w,
                  int dst_h,
                  GLuint vao,
                  GLuint vbo);

// ---------------------------------------------------------------------------- recensement ----

// Releve du texte fragment TEL QUE LE PILOTE LE RECOIT (`Shader::build`, avant glShaderSource).
void note_fragment_source(const std::string& name, const std::string& expanded_frag_src);

// Une copie de couleur de scene SUR LE CHEMIN D'AFFICHAGE vient d'avoir lieu. Compte un site
// quand la source est flottante et la destination ne l'est pas.
void note_display_copy(const char* site, GLenum src_fmt, GLenum dst_fmt);

// Une lecture de la scene par un EFFET (hors chemin d'affichage). Publiee a part.
void note_aux_scene_read(const char* site, GLenum src_fmt, GLenum dst_fmt);

// Mesure de la marge : echantillonne le tampon de scene et compte les pixels dont un canal
// depasse 1,0. Ne tourne QUE lorsque le harnais mesure cet item, et une image sur N.
void probe_scene(GLuint scene_fbo, int w, int h, GLenum fmt);

// Fin d'image : publication avec le format du FBO de scene effectivement retenu.
// A appeler depuis LES DEUX renderers (bureau et Android).
void frame_end(GLenum scene_format);

// Le compte de compressions de plage de la DERNIERE image recensee par `frame_end` (le meme
// nombre que juge le verdict 5 de lighting-hdr). Lu par hdr_output::frame_end.
uint64_t last_frame_sites();

// ----------------------------------------- recensement des ENTREES du chemin de scene --------
// Pourquoi il existe (chantier `hdr-plan`). Le tampon de scene est RGBA16F et porte jusqu'a
// quinze fois le blanc (mesure : `hdr_probe_max_x1000`). Mais il est alimente par des cibles
// intermediaires que NOUS creons — le ciel, les sondes de glow, l'occlusion ambiante, les
// palettes de cycle jour/nuit — et dont la profondeur est NOTRE choix, pas une contrainte de
// l'asset. `hdr_out_src_sdr_compressions` ne les regarde pas : il rend 0 alors que la plage est
// bornee EN AMONT du tone map. Ce recensement les compte LA OU ELLES SONT CREEES, avec leur
// format et leur taille reelle, pour qu'un plan d'enrichissement chiffre ce qu'il propose au
// lieu de l'estimer.
//
// Il ne lit rien, ne dessine rien et n'a aucun effet sur le rendu : `name` identifie la source,
// `internal_fmt` est le format DEMANDE au pilote, `w`/`h` ses dimensions et `count` le nombre de
// cibles identiques creees d'un coup. Rappeler la fonction pour la meme source (redimension,
// re-format) REMPLACE l'entree : c'est l'etat courant qui compte, pas l'historique.
void note_input_source(const char* name, GLenum internal_fmt, int w, int h, int count);

// Meme chose pour une FAMILLE de cibles de tailles differentes creees dans une boucle (les cinq
// etages de reduction du glow, les deux resolutions du ciel) : la cle devient `nom-<index>`.
// Les enregistrer sous un seul nom en ferait perdre quatre sur cinq — la derniere ecrase les
// autres, et le total d'octets publie serait faux d'un facteur quatre.
void note_input_source_indexed(const char* name, int index, GLenum internal_fmt, int w, int h);

struct InputCensus {
  uint64_t sources_seen = 0;     // entrees distinctes vues pendant la course
  uint64_t sources_8bit = 0;     // ... dont la profondeur est de 8 bits par canal
  uint64_t sources_unknown = 0;  // ... dont le format n'est pas dans la table (defaut d'instrument)
  uint64_t bytes_8bit = 0;       // octets alloues par les seules sources 8 bits
  uint64_t bytes_total = 0;
};
InputCensus input_census();
bool input_source_seen(const char* name);
// "nom=format:octets" separes par des virgules, dans l'ordre alphabetique. Vide -> "-".
const char* input_census_list();

// =========================== CHANTIER A — `hdr-source-range` ==================================
// LE CHANTIER A du plan HDR (PLAN.md §7.1) : le ciel et le halo cessent d'ecreter a 1,0.
//
// CE QU'EST UN « ETAGE DE SOURCE », ET POURQUOI CE N'EST PAS TOUTE ENTREE RECENSEE.
// --------------------------------------------------------------------------------
// Le recensement ci-dessus compte TOUTES les cibles que nous creons. La porte de ce chantier,
// elle, ne peut compter que les etages qui ECRETENT REELLEMENT UNE COULEUR FLOTTANTE : une
// cible dont le contenu est COMPOSE par le moteur (addition de couches, filtrage, rasterisation)
// et dont le format decide si cette composition a le droit de depasser 1,0.
//
// Deux familles d'entrees n'entrent donc pas dans ce compte, et elles sont publiees a part,
// COMPTEES ET NOMMEES (`hdr_src_excluded`, `hdr_src_excluded_list`) — un seau « exclu » muet
// serait indistinguable d'un oubli :
//   * les palettes de cycle jour/nuit (`tod-palette-*`) ne sont pas des cibles de rendu : ce
//     sont des TELEVERSEMENTS de u32 RGBA8 lus du BSP. Elargir le conteneur ne creerait aucune
//     information ; ce qui merite de l'etre, c'est l'accumulateur d'interpolation, et il
//     appartient a `lighting-bake` (PLAN.md §2.1).
//   * l'occlusion ambiante (`ao-*`) est un FACTEUR borne a [0,1] par sa definition meme : il n'y
//     a rien au-dessus de 1,0 a y perdre. Sa cible appartient a `lighting-ao-indirect`, qui la
//     recree de toute facon.
//
// LE REGIME, EPINGLE ET PUBLIE. La conversion n'a lieu que sous le maitre Recharged ALLUME.
// Sous maitre eteint, le rendu doit rester identique AU BIT au jeu d'origine (acquis
// `lighting-origin-bitexact`) : elargir un tampon intermediaire la-bas serait une regression
// qu'aucune porte de CE chantier ne verrait. `hdr_src_master_on` publie le regime observe.
struct StageFormat {
  GLenum internal_fmt = 0;  // ce qu'il faut passer en `internalformat`
  GLenum ext_fmt = 0;       // ... en `format`
  GLenum type = 0;          // ... en `type`
  bool is_float = false;
};

// Le format a DEMANDER pour un etage de source. Rend le flottant quand le chantier est actif
// (maitre Recharged allume ET bras arme), le format historique sinon — c'est ce dernier cas que
// `proof_run.sh --off` mesure, et c'est lui qui donne le AVANT du cout en cadence.
StageFormat source_stage_format(GLenum legacy_internal, GLenum legacy_ext, GLenum legacy_type);
bool source_range_active();

// Meme contrat que `note_input_source`, mais l'entree est marquee ETAGE : c'est elle que la
// porte `hdr_src_clamped_stages` compte. Le format passe doit etre celui que le pilote a
// REELLEMENT accepte, pas celui qu'on a demande.
void note_scene_stage(const char* name, GLenum internal_fmt, int w, int h, int count);
void note_scene_stage_indexed(const char* name, int index, GLenum internal_fmt, int w, int h);

// Le pilote a refuse le flottant pour cet etage et l'appelant est retombe sur le 8 bits. On
// compte les replis : un `hdr_src_clamped_stages` non nul doit pouvoir se lire « le pilote a
// dit non » et pas seulement « le code ne l'a pas demande ».
void note_stage_fallback(const char* name);

// LE CIEL, MESURE LA OU L'ECRETAGE ETAIT. Le chemin CPU (celui de l'appareil : `use_sky_cpu`
// vaut vrai par defaut) compose ses couches en entier ; il saturait a 255 avec `_mm_adds_epu8`
// et tronquait chaque couche avec `>> 7`. Au moment de l'addition on compte DEUX choses, et il
// en faut deux : `over_px`, les composantes dont la somme NON BORNEE depasse 1,0 (la PLAGE que
// le 8 bits detruisait), et `differs_px`, celles que le u8 ne pouvait pas representer (la
// PRECISION qu'il detruisait). Un `over_px` nul avec un `differs_px` nul dirait « le changement
// ne fait rien » ; un `over_px` nul avec un `differs_px` non nul dit « il fait autre chose que
// ce que le plan supposait », et c'est une mesure, pas une excuse.
void note_sky_wide(uint64_t over_px,
                   uint64_t differs_px,
                   uint64_t seen_px,
                   uint64_t max_x1000,
                   uint64_t max_diff_x1000);

// LE HALO. Relit le dernier etage de reduction (40x40) une image sur trente et publie ce qu'il
// contient : pixels vus, pixels au-dessus de 1,0, maximum. Aucun blit, aucune passe ajoutee.
void probe_glow(GLuint fbo, int w, int h, GLenum fmt);

// ============ CHANTIER `hdr-glow-range` — LA COUVERTURE DU CHEMIN DE HALO, D'ABORD ============
// Le chantier A a elargi la sonde de halo et ses cinq reductions sans jamais les voir tourner :
// `hdr_src_glow_state=2` sur 10 560 images d'appareil. Ce zero ne disait pas « pas de
// depassement », il disait « pas de mesure ». Ce bloc-ci compte le CHEMIN, jamais la grandeur :
// combien de fois le producteur DMA est entre, combien de sprites ont ete soumis, combien de fois
// `flush` a tourne — et SURTOUT le denominateur qui rend ces zeros falsifiables : les images de
// `Sprite3::render`, le dispatch qui les a prises, et les sprites que les AUTRES chemins ont
// dessines pendant le meme temps. Un `flush_calls=0` a cote d'un `sprite_render_calls=0` ne
// prouve rien ; a cote d'un `sprite_render_calls=10000` il prouve que le chemin est inatteignable.
void note_glow_ctor(bool latched_float,
                    uint64_t ds_bytes,
                    uint64_t probe_bytes,
                    int stages_created,
                    int stages_complete,
                    int fallbacks);

// Un redimensionnement a REPRIS le format latche a la construction au lieu de reconsulter le
// regime. C'est ce compteur qui etablit, sans bascule vecue, que la bascule Recharged en jeu ne
// peut pas atteindre ces cibles : le format n'est resolu qu'UNE fois par vie du renderer.
void note_glow_fmt_reuse(uint64_t probe_bytes);

void note_glow_dma_enter();              // `Sprite3::glow_dma_and_draw` est entre
void note_glow_alloc(bool cancelled);    // un sprite a ete alloue (et peut-etre annule)
void note_glow_flush(uint64_t pending);  // `GlowRenderer::flush`, AVANT son retour anticipe

// Une image de `Sprite3::render`. `jak1_path` distingue les deux dispatchs (seul `render_jak2`
// lit le bucket glow) ; `sprites_2d` et `aux_sprites` sont les CHEMINS CONCURRENTS — c'est par
// eux que passe le halo que l'owner voit sur les feux et les portails.
void note_sprite_frame(bool jak1_path, uint64_t sprites_2d, uint64_t aux_sprites);

// ============ CHANTIER `glow-targets-not-built-on-jak1` — LES CIBLES QU'ON NE PAIE PLUS ======
// CE QUE LA MESURE DU 11/09 A ETABLI (reports/hdr-glow-range/proof.txt, appareil eae4df44) :
// sur 9 091 images de sprites jak1, `hdr_glow_flush_calls` = 0, `hdr_glow_dma_enters` = 0,
// `hdr_glow_sprites_submitted` = 0, pendant que 16 385 088 sprites 2D et 204 397 distorteurs
// passaient par les deux AUTRES chemins. `GlowRenderer` etait pourtant construit en membre de
// `Sprite3` et allouait ses six cibles — la sonde et cinq reductions — pour 6 822 400 o.
//
// LE PREDICAT EST UNIQUE, ET IL SUIT LE DISPATCH. `Sprite3::render` envoie Jak1 sur
// `render_jak1`, qui ne nomme jamais `glow_dma_and_draw` ; tous les autres jeux vont sur
// `render_jak2`, seul appelant. `glow_targets_needed()` recopie CE dispatch et rien d'autre :
// c'est la meme fonction qui decide de construire et qui est publiee par jeu, de sorte qu'une
// divergence entre la decision et ce que la preuve annonce est impossible par construction.
bool glow_targets_measuring();
bool glow_targets_needed(GameVersion version);

// Une image de `Sprite3::render`, avec le jeu OBSERVE (pas suppose : `render_state->version`),
// ce que le predicat en dit, et si une instance est detenue a cet instant.
void note_glow_targets_frame(GameVersion version_at_render,
                             bool needed,
                             bool owned,
                             uint64_t owned_bytes);

// Une construction REELLE pour le chemin de rendu. `lazy` distingue le site normal (haut de
// `Sprite3::render`) du filet pose dans `glow_dma_and_draw` : si le filet tire, c'est que la
// decision du haut a manque, et le compte le dit au lieu de le taire.
void note_glow_targets_ctor(uint64_t owned_bytes, bool lazy);

// LE TEMOIN DE REVERSIBILITE, ET LE `AVANT` DE LA MEME COURSE.
// -----------------------------------------------------------
// Un `glow_targets_bytes_after=0` sans un `avant` non nul mesure DANS LA MEME COURSE ne prouve
// rien : il se lit aussi bien « les cibles ne sont plus allouees » que « l'instrument n'a jamais
// regarde ». Et un item qui debranche du code sans montrer que le chemin debranche se rebranche
// n'a pas livre une condition, il a livre une suppression.
//
// Ce temoin resout les deux d'un seul geste : quand — et SEULEMENT quand — la course est armee
// sur cet item, `Sprite3::render` construit UNE fois un `GlowRenderer` complet, releve ce qu'il
// a reellement alloue et l'etat de ses six cibles, puis lui rend ses noms GL. Le cout est
// transitoire (une image), le chiffre est produit par le constructeur REEL, et le jeu livre a
// l'owner — non arme — ne le paie jamais.
bool glow_targets_witness_due();
void note_glow_targets_witness(uint64_t bytes,
                               int stages_created,
                               int stages_complete,
                               int gl_names_freed,
                               int gl_names_expected);

// ============ CHANTIER `hdr-sky-gpu-alpha` — LE POIDS DE MELANGE DU CIEL, CHEMIN GPU =========
// Le chantier A a ouvert la cible du ciel en flottant. Le chemin GPU (`SkyBlendGPU`, bureau
// seul : `use_sky_cpu` vaut vrai par defaut et seule une case ImGui le bascule) accumulait ses
// couches par `glBlendFunc(GL_ONE, GL_ONE)` : sur une cible flottante l'ALPHA — un POIDS DE
// MELANGE, pas une couleur — a cesse de saturer a 1,0. Ce bloc mesure la grandeur au POINT OU
// ELLE EST PRODUITE (relecture de la cible, pas du consommateur) et publie, dans la MEME course,
// la valeur d'AVANT (temoin a borne infinie) a cote de celle d'APRES.
//
// Les zeros de ce bloc sont falsifiables par construction : `frames`/`readbacks`/`components`
// sont les denominateurs, et `before_over_px` est la POPULATION QUE LE CORRECTIF VIDE — s'il est
// nul, le vert ne prouve rien et le defaut 4 le dit.
bool sky_gpu_alpha_measuring();

// Le chemin choisi pour la course. `mode` : 0 = celui du jeu (case ImGui), 1 = GPU force,
// 2 = ALTERNE (un appel sur deux) — c'est le seul mode qui exerce les DEUX chemins dans une
// course et qui donne donc au chemin CPU, celui de l'appareil, ses propres grandeurs.
void note_sky_path_mode(int mode);
void note_sky_cpu_call();  // `SkyBlendCPU::do_sky_blends` vient d'etre choisi
void note_sky_gpu_call();  // `SkyBlendGPU::do_sky_blends` vient d'etre choisi

// Une relecture de cible vient d'avoir lieu. `stage_float` dit si l'etage est REELLEMENT
// flottant : sur un etage 8 bits le materiel borne tout seul et le verdict serait vide.
// `uniform_ok` : 1 si `tex_prev` ET `alpha_limit` ont une localisation dans le programme lie
// (un uniforme non lu est RETIRE par le compilateur GLSL et rend -1 : on le teste, on ne le
// suppose pas).
void note_sky_gpu_alpha(uint64_t components,
                        uint64_t alpha_over,
                        uint64_t alpha_max_x1000,
                        uint64_t rgb_max_x1000,
                        uint64_t before_alpha_over,
                        uint64_t before_alpha_max_x1000,
                        uint64_t before_rgb_max_x1000,
                        bool stage_float,
                        int uniform_ok,
                        bool witness_ready,
                        uint64_t seed_clamped_x1000,
                        uint64_t seed_free_x1000,
                        int seed_layers);

// ============ CHANTIER `sky-gpu-path-robustness` — LE CHEMIN GPU DU CIEL, SANS DEFAUT IMPLICITE
// Quatre signalements du 12/09 sur un chemin que `hdr-sky-gpu-alpha` venait d'ouvrir a la mesure.
// Rien ici n'est un verdict : ce sont des grandeurs relues, publiees a cote du verdict que
// `publish_sky_robustness()` compose.
bool sky_robustness_measuring();

// LE MODE DE MELANGE PS2 DU CIEL, RECENSE LA OU L'ASSERT NU MOURAIT. Rend vrai pour le mode
// attendu (`Cs + Cd`, 0x8000000068) ; faux veut dire REPLI : l'appelant saute la couche et
// continue, il ne tue pas le processus. `gpu_path` separe les deux chemins, qui portaient le
// meme ASSERT. Le recensement est PAR VALEUR : une somme ne dirait pas QUEL mode est arrive.
bool sky_blend_mode_supported(bool gpu_path, uint64_t alpha_data);

// LES DEUX LIAISONS, RELUES A LA SORTIE DU CONSTRUCTEUR de `SkyBlendGPU`. Il y bindait un nom de
// FRAMEBUFFER dans `GL_ARRAY_BUFFER` : deux espaces de noms sans rapport. On ne l'affirme pas
// corrige, on relit l'etat. `prev_name_is_buffer` est le temoin de la confusion : le nom que
// l'ancien code liait comme tampon de sommets n'en etait pas un.
void note_sky_ctor_bindings(uint64_t prev_fbo_name,
                            int prev_name_is_buffer,
                            uint64_t array_buffer_binding,
                            uint64_t framebuffer_binding,
                            uint64_t gl_error,
                            uint64_t drained_errors);

// LE CONTROLE SEME DE L'ESPACE DE NOMS. Les liaisons relues ci-dessus ne disent rien tant que
// `prev_fbo_name` vaut 0 : l'ancien `glBindBuffer(GL_ARRAY_BUFFER, old_framebuffer)` liait alors
// 0, exactement comme le correctif, et le terme serait VERT sur l'ancien binaire. Ce controle
// refait le geste fautif SUR UN VRAI NOM DE FRAMEBUFFER, non nul, et publie ce que le pilote en
// fait : soit il refuse (erreur GL), soit il accepte et la liaison CHANGE pour le nom du
// framebuffer. Les deux issues prouvent la confusion ; un silence des deux cotes dirait que le
// controle lui-meme est mort.
//
// `is_buffer` est PUBLIE, jamais exige : la mesure du 12/09 rend VRAI — le nom 1 designe a la
// fois notre framebuffer et un tampon de sommets vivant appartenant a quelqu'un d'autre. C'est
// le pire cas, pas une absence de defaut : l'ancien code liait un objet ETRANGER sans la moindre
// erreur GL. Un controle qui aurait exige `is_buffer == 0` aurait pris cette demonstration pour
// une refutation.
void note_sky_namespace_seed(uint64_t fbo_name,
                             int is_buffer,
                             uint64_t bind_error,
                             uint64_t binding_before,
                             uint64_t binding_after,
                             uint64_t drained_errors);

// LES ECHANTILLONNEURS DU PROGRAMME `sky_blend`, tels que LE PILOTE les declare (un uniforme non
// lu est RETIRE par le compilateur GLSL : un grep sur le source mentirait). `assigned` ne compte
// que ceux dont l'unite a ete posee ET RELUE egale a ce qu'on voulait.
void note_sky_samplers(uint64_t declared, uint64_t assigned, const char* names);

// LE REGLAGE `use_sky_cpu` RESOLU AU DEMARRAGE, ET SA PROVENANCE. `override_val` : -1 absent,
// 0/1 pose. `roundtrip_ok` : le champ survit a un aller-retour de serialisation — c'est ce qui
// fait de lui un reglage PERSISTANT et pas un champ oublie dans `to_json`.
void note_sky_cpu_setting(int effective,
                          int compiled_default,
                          int json_present,
                          int json_has_key,
                          int json_value,
                          int override_val,
                          int roundtrip_ok,
                          const char* source);

// LA VALEUR REELLEMENT PORTEE par `SharedRenderState` au moment du bucket ciel : sans elle, un
// reglage resolu au demarrage et jamais applique serait indistinguable d'un reglage applique.
void note_sky_cpu_applied(int applied);

// ------------------------------ l'etat du recensement de chaine, relu par un autre module -----
// Les memes grandeurs que `frame_end` publie deja sous `hdr_*` / `tonemap_*`. Un module qui doit
// DECIDER sur elles (et pas seulement les publier) les lit ici, au lieu de relire un proof.txt.
struct ChainCensus {
  uint64_t progs_scanned = 0;
  uint64_t oetf_progs = 0;
  uint64_t tonemap_draws = 0;
  uint64_t frames = 0;
  uint64_t chain_frames = 0;
  uint64_t probe_px = 0;
  uint64_t overbright_px = 0;
  uint64_t probe_max_x1000 = 0;
  int probe_state = 0;  // -1 refusee par le pilote, 0 jamais tentee, 1 a tourne
  int ladder_step = 0;  // cran de l'echelle de repli des formats (0 = aucun repli)
};
ChainCensus chain_census();

}  // namespace hdr
