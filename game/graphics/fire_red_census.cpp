#include "fire_red_census.h"

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>

#include "game/system/autoport_proof.h"

namespace fire_red_census {
namespace {

// Les trois textures du foyer du maire. On ne recense que les seaux qui les portent : compter
// TOUS les sprites du jeu diluerait le denominateur et rendrait le zero illisible.
bool is_fire_texture(const char* name, bool* is_middot) {
  *is_middot = false;
  if (!name) {
    return false;
  }
  // `get_debug_texture_name_from_tbp` rend « tpage/nom » ou « nom » : une recherche de
  // sous-chaine suffit, les trois noms ne sont prefixes de rien d'autre en jak1.
  const bool middot = std::strstr(name, "middot") != nullptr;
  *is_middot = middot;
  return middot || std::strstr(name, "hotdot") != nullptr ||
         std::strstr(name, "bigpuff") != nullptr;
}

// Le monde de jak1 tient tres large dans ±20 km ; au-dela, ou non fini, aucune donnee de
// niveau ne peut avoir place ce sprite.
constexpr float kWorldLimit = 4096.f * 20000.f;

bool out_of_world(float x, float y, float z) {
  if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z)) {
    return true;
  }
  return std::fabs(x) > kWorldLimit || std::fabs(y) > kWorldLimit || std::fabs(z) > kWorldLimit;
}

// SRC_0_FIX_DST (3, fix=128) et SRC_DST_FIX_DST (4, fix=64) : le facteur source est une alpha
// FIXE, pas celle du sommet. Un sprite d'alpha nul y depose donc quand meme sa couleur.
bool blend_ignores_src_alpha(int alpha_blend) {
  return alpha_blend == 3 || alpha_blend == 4;
}

struct Counters {
  std::atomic<uint64_t> sprites{0};        // sprites de feu vus dans l'image
  std::atomic<uint64_t> red_visible{0};    // ... rouges et visibles (braises d'origine incluses)
  std::atomic<uint64_t> carrier_alpha{0};  // 411 dessine parce que son alpha passe le test
  std::atomic<uint64_t> carrier_afail{0};  // 411 dessine par la seconde passe, melange a fix
  std::atomic<uint64_t> nonfinite{0};      // position non finie ou hors du monde
  std::atomic<uint64_t> debug_draw{0};     // tirages depuis un site rouge de debug
  // LES DENOMINATEURS DU BRAS PORTEUR. Sans eux, `carrier_*=0` peut vouloir dire « le porteur
  // n'atteint jamais le tampon » AUTANT QUE « aucun sprite `middot` n'a jamais ete recense » :
  // un zero dont la condition est absente ne refute rien.
  std::atomic<uint64_t> middot{0};          // sprites de texture `middot` vus dans l'image
  std::atomic<uint64_t> middot_visible{0};  // ... dont l'alpha passe le test, couleur quelconque
  // L'ORACLE DE LA COULEUR, au point d'empaquetage. Voir l'en-tete.
  std::atomic<uint64_t> pack{0};          // sprites 2D empaquetes dans l'image (denominateur)
  std::atomic<uint64_t> pack_oor{0};      // ... dont une composante SOURCE sort de [0,255]
  std::atomic<uint64_t> pack_foreign{0};  // ... dont le sommet differe de la SATURATION
  std::atomic<uint64_t> pack_oldwrap{0};  // ... que l'ancien `& 0xff` coloriait autrement
  std::atomic<uint64_t> a0_afail{0};      // sprite d'alpha NULLE que son seau dessine quand meme
  std::atomic<uint64_t> clamp255{0};      // sprite portant une composante EXACTEMENT a 255,0
  // LES DEUX SIGNATURES DE BORNAGE, une par famille signalee par l'owner. Voir note_pack.
  std::atomic<uint64_t> ember_clamped{0};  // braise 2292/2357 bornee (feu)
  std::atomic<uint64_t> warp_clamped{0};   // point 766/1969/1312/1860/2688 borne (portail)
};

Counters g_frame;   // remis a zero a chaque image
uint64_t g_frames = 0;
uint64_t g_sprites_total = 0;
uint64_t g_sprites_max = 0;
uint64_t g_red_max = 0;
uint64_t g_carrier_alpha_max = 0;
uint64_t g_carrier_afail_max = 0;
uint64_t g_nonfinite_max = 0;
uint64_t g_debug_max = 0;
uint64_t g_middot_total = 0;
uint64_t g_middot_max = 0;
uint64_t g_middot_visible_max = 0;
uint64_t g_pack_total = 0;
uint64_t g_pack_oor_total = 0;
uint64_t g_pack_foreign_max = 0;
uint64_t g_pack_oldwrap_total = 0;
uint64_t g_pack_oldwrap_max = 0;
uint64_t g_pack_olddelta_max = 0;
uint64_t g_pack_foreign_hud_total = 0;
uint64_t g_pack_foreign_a0_total = 0;
uint64_t g_clamp255_total = 0;
uint64_t g_oor_vis_total = 0;
uint64_t g_ember_clamped_total = 0;
uint64_t g_warp_clamped_total = 0;
// LES SIGNATURES DE COULEUR SOURCE des sprites hors bornes. Le nom de texture d'un porteur
// `aux-list` ne veut rien dire (son tbp porte le dernier nom televerse la), mais sa COULEUR est
// une signature exacte du `defpart` : 3277,2662,2867 = part 413, l'aux du foyer du maire
// (`village1-part.gc:679`) ; 4096,3482,3482 = part 767, l'aux du portail de teleportation
// (`training-part.gc:615`). Les publier NOMME les groupes qui etaient vivants pendant la course.
constexpr int kMaxSamples = 8;
char g_oor_samples[kMaxSamples][40] = {};
int g_oor_sample_n = 0;

void note_oor_sample(float r, float g, float b, float a) {
  char sig[40];
  std::snprintf(sig, sizeof(sig), "%.0f/%.0f/%.0f/%.0f", r, g, b, a);
  for (int i = 0; i < g_oor_sample_n; i++) {
    if (std::strcmp(g_oor_samples[i], sig) == 0) {
      return;
    }
  }
  if (g_oor_sample_n >= kMaxSamples) {
    return;
  }
  std::snprintf(g_oor_samples[g_oor_sample_n], sizeof(g_oor_samples[0]), "%s", sig);
  g_oor_sample_n++;
}
uint64_t g_a0_afail_max = 0;
unsigned g_pack_foreign_chan = 0;
// L'ECHANTILLON LE PLUS DIVERGENT, pour que le seau exclu soit NOMME et non seulement compte.
char g_worst_sample[96] = {0};
uint64_t g_worst_sample_delta = 0;
uint64_t g_worst = 0;  // max sur une image de la somme des familles non-originelles
char g_sites[192] = {0};

// LA LISTE DES EMETTEURS, nommement. L'item demande « la liste des emetteurs inspectes et le
// compte de dessins rouges etrangers par emetteur » : on tient une petite table des textures sur
// lesquelles l'ancienne politique divergeait, avec leur compte cumule.
constexpr int kMaxEmitters = 12;
struct Emitter {
  char name[40];
  uint64_t count;
};
Emitter g_emitters[kMaxEmitters] = {};
int g_emitter_n = 0;
uint64_t g_emitter_dropped = 0;
// La meme table pour le temoin de la BORNE : quels emetteurs portent une composante ramenee
// exactement a 255,0.
Emitter g_clamp_emitters[kMaxEmitters] = {};
int g_clamp_emitter_n = 0;
uint64_t g_clamp_emitter_dropped = 0;

void note_emitter_in(Emitter* tab, int* n_io, uint64_t* dropped, const char* name, uint64_t add) {
  const char* n = (name && *name) ? name : "?";
  for (int i = 0; i < *n_io; i++) {
    if (std::strcmp(tab[i].name, n) == 0) {
      tab[i].count += add;
      return;
    }
  }
  if (*n_io >= kMaxEmitters) {
    *dropped += add;
    return;
  }
  std::snprintf(tab[*n_io].name, sizeof(tab[*n_io].name), "%s", n);
  tab[*n_io].count = add;
  (*n_io)++;
}

void note_emitter(const char* name, uint64_t add) {
  note_emitter_in(g_emitters, &g_emitter_n, &g_emitter_dropped, name, add);
}

// Rend la liste « nom:compte » d'une table, jamais une chaine vide (`publish_text` garderait
// sinon la valeur de l'image precedente).
void format_emitters(char* buf, size_t cap, const Emitter* tab, int n, uint64_t dropped) {
  int off = 0;
  for (int i = 0; i < n && off < (int)cap - 1; i++) {
    off += std::snprintf(buf + off, cap - off, "%s%s:%llu", off ? "," : "", tab[i].name,
                         (unsigned long long)tab[i].count);
  }
  if (dropped && off < (int)cap - 1) {
    off += std::snprintf(buf + off, cap - off, ",+autres:%llu", (unsigned long long)dropped);
  }
  if (off == 0) {
    std::snprintf(buf, cap, "-");
  }
}

// LA REFERENCE : ce que la couleur source DECRIT, une fois ramenee a un octet. Saturation, pas
// repliement. NaN et negatifs tombent a 0 (le chemin sparticle borne deja a >= 0).
int saturate_ref(float v) {
  if (!(v > 0.f)) {
    return 0;
  }
  if (v > 255.f) {
    return 255;
  }
  return (int)v;
}

// L'ANCIENNE politique, reproduite a l'identique pour chiffrer ce qu'elle changeait. Le `(int)`
// d'un flottant non fini est indefini : on l'ecarte avant, comme le fait `saturate_ref`.
int wrap_ref(float v) {
  if (!std::isfinite(v)) {
    return 0;
  }
  if (v > 2.1e9f || v < -2.1e9f) {
    return 0;
  }
  return (int)v & 0xff;
}

void note_site_name(const char* site) {
  if (!site || !*site) {
    return;
  }
  if (std::strstr(g_sites, site)) {
    return;
  }
  const size_t len = std::strlen(g_sites);
  const size_t add = std::strlen(site);
  if (len + add + 2 >= sizeof(g_sites)) {
    return;
  }
  if (len) {
    g_sites[len] = ',';
    std::memcpy(g_sites + len + 1, site, add + 1);
  } else {
    std::memcpy(g_sites, site, add + 1);
  }
}

}  // namespace

bool armed() {
  return autoport_proof::armed_for("fire-red-particles");
}

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
                 bool double_draw) {
  if (!armed()) {
    return;
  }
  // LE TEMOIN DU SEAU EXCLU, avant tout filtre de texture : un sprite dont l'alpha ECHOUE le
  // test mais dont le seau le dessine quand meme (seconde passe AFAIL + melange a alpha FIXE).
  // Si ce compte est non nul, exclure les sprites d'alpha nulle de la porte n'est plus fonde.
  if (a < alpha_min && double_draw && blend_ignores_src_alpha(alpha_blend)) {
    g_frame.a0_afail.fetch_add(1, std::memory_order_relaxed);
  }

  bool middot = false;
  if (!is_fire_texture(texture_name, &middot)) {
    return;
  }
  g_frame.sprites.fetch_add(1, std::memory_order_relaxed);
  if (middot) {
    g_frame.middot.fetch_add(1, std::memory_order_relaxed);
  }

  if (out_of_world(x, y, z)) {
    g_frame.nonfinite.fetch_add(1, std::memory_order_relaxed);
  }

  // Le test d'alpha de la premiere passe, tel que le shader l'applique
  // (`sprite3_3d.frag` / `sprite3_3d_inst.frag` : `if (color.a < alpha_min) discard`).
  const bool alpha_passes = a >= alpha_min;
  const bool red_pure = r >= 0.5f && g <= 0.02f && b <= 0.02f;
  const bool red_dominant = r >= 0.5f && g <= 0.25f && b <= 0.25f;

  if (middot && alpha_passes) {
    g_frame.middot_visible.fetch_add(1, std::memory_order_relaxed);
  }

  if (alpha_passes && red_dominant) {
    g_frame.red_visible.fetch_add(1, std::memory_order_relaxed);
  }

  // LA SIGNATURE DU PORTEUR 411 : texture `middot`, rouge PUR (g et b nuls). Le jeu d'origine
  // lui donne `:a 0.0` sans `fade-a` ; il ne doit atteindre le tampon par AUCUN des deux
  // chemins. On separe les deux pour que la correction vise le bon.
  if (middot && red_pure) {
    if (alpha_passes) {
      g_frame.carrier_alpha.fetch_add(1, std::memory_order_relaxed);
    } else if (double_draw && blend_ignores_src_alpha(alpha_blend)) {
      g_frame.carrier_afail.fetch_add(1, std::memory_order_relaxed);
    }
  }
}

void note_pack(const char* texture_name,
               bool hud,
               float sr,
               float sg,
               float sb,
               float sa,
               int pr,
               int pg,
               int pb,
               int pa) {
  if (!armed()) {
    return;
  }
  g_frame.pack.fetch_add(1, std::memory_order_relaxed);

  const float src[4] = {sr, sg, sb, sa};
  const int got[4] = {pr, pg, pb, pa};
  bool oor = false;
  bool foreign = false;
  bool oldwrap = false;
  int olddelta = 0;
  unsigned chan_mask = 0;
  for (int i = 0; i < 4; i++) {
    const float v = src[i];
    if (!std::isfinite(v) || v < 0.f || v > 255.f) {
      oor = true;
    }
    const int ref = saturate_ref(v);
    if (got[i] != ref) {
      foreign = true;
      chan_mask |= 1u << i;
    }
    const int d = wrap_ref(v) - ref;
    if (d != 0) {
      oldwrap = true;
      const int ad = d < 0 ? -d : d;
      if (ad > olddelta) {
        olddelta = ad;
      }
    }
  }
  if (oor) {
    g_frame.pack_oor.fetch_add(1, std::memory_order_relaxed);
    note_oor_sample(sr, sg, sb, sa);
    if (!hud && pa > 0) {
      // Hors bornes ET reellement dessine : c'est la famille du defaut. Doit etre 0.
      g_oor_vis_total++;
    }
  }
  // TEMOIN INDICATIF, PAS LA PREUVE. La borne remise a la relance produit la valeur EXACTE
  // 255,0 la ou le `defpart` ecrit 256,0. Mais 239 champs de `defpart` a texture `hotdot` et 21
  // a texture `middot` ECRIVENT deja 255,0 directement (`collectables-part.gc:679` par exemple) :
  // ce compte melange les deux et ne peut pas servir de preuve que la borne a tire. Il est
  // publie pour la lecture, pas pour la porte. La preuve de presence est `fire_oor_samples`.
  // LES DEUX SIGNATURES DE BORNAGE, CHACUNE INCONTAMINABLE.
  //
  // PORTAIL — les parts 766 / 1969 / 1312 / 1860 / 2688 ecrivent `(:b 64.0 196.0)` : un tirage
  // CONTINU dans [64, 260). Un sprite `middot` dont la composante bleue vaut EXACTEMENT 255,0 a
  // donc une probabilite nulle d'exister par tirage — c'est un produit de la borne, et d'elle
  // seule. Les autres `defpart` a texture `middot` qui peuvent valoir 255,0 ecrivent ce 255 sur
  // r ou g (`weather-part.gc:488` et `:543`), jamais sur b en constante.
  //
  // FEU — la braise 2292 (et sa jumelle 2357) ecrit `(:r 256.0)` avec `(:fade-r 0.0)` : le rouge
  // reste CONSTANT pendant les 0,6 s de la premiere phase. Borne, il vaut exactement 255,0. Ses
  // canaux vert et bleu partent tous deux de 128,0 avec le MEME `fade` (-0,7111) : ils restent
  // rigoureusement EGAUX et decroissent. Un `hotdot` a r = 255,0 exact, g = b, 0 < g <= 128 est
  // donc cette braise-la.
  bool pack_middot = false;
  const bool pack_fire_tex = is_fire_texture(texture_name, &pack_middot);
  if (!hud && pack_middot && sb == 255.f) {
    g_frame.warp_clamped.fetch_add(1, std::memory_order_relaxed);
  }
  if (!hud && pack_fire_tex && !pack_middot && sr == 255.f && sg == sb && sg > 0.f &&
      sg <= 128.f) {
    g_frame.ember_clamped.fetch_add(1, std::memory_order_relaxed);
  }
  if (!hud && (sr == 255.f || sg == 255.f || sb == 255.f)) {
    g_frame.clamp255.fetch_add(1, std::memory_order_relaxed);
    note_emitter_in(g_clamp_emitters, &g_clamp_emitter_n, &g_clamp_emitter_dropped, texture_name,
                    1);
  }
  if (foreign) {
    if (hud) {
      g_pack_foreign_hud_total++;
    } else if (pa <= 0) {
      // ALPHA ECRITE NULLE : le sprite est jete par le test d'alpha du shader
      // (`if (color.a < alpha_min) discard`). C'est le cas, par conception, des porteurs
      // `aux-list` : `sp-relaunch-particle-2d` leur force `r-g-b-a w = 0.0`
      // (`sparticle-launcher.gc`), `sprite.gc:100` aussi, et leurs champs de couleur portent des
      // valeurs de LUMIERE en milliers (part 413 du foyer : `:r 3276.8` ; part 767 du portail :
      // `:r 4096.0`) que le premier lancement refuse deja de borner
      // (`sparticle_launcher.cpp:551` saute le `vminix` quand `flags & 0x100`). Les borner serait
      // une faute. Le seau est EXCLU de la porte mais CHIFFRE : `fire_pack_foreign_a0`, et
      // `fire_a0_afail_max` mesure qu'aucun d'eux n'atteint le tampon par la seconde passe.
      g_pack_foreign_a0_total++;
    } else {
      g_frame.pack_foreign.fetch_add(1, std::memory_order_relaxed);
      g_pack_foreign_chan |= chan_mask;
    }
  }
  if (oldwrap) {
    g_frame.pack_oldwrap.fetch_add(1, std::memory_order_relaxed);
    note_emitter(hud ? "HUD" : texture_name, 1);
    if ((uint64_t)olddelta > g_pack_olddelta_max) {
      g_pack_olddelta_max = (uint64_t)olddelta;
    }
    if ((uint64_t)olddelta >= g_worst_sample_delta) {
      g_worst_sample_delta = (uint64_t)olddelta;
      std::snprintf(g_worst_sample, sizeof(g_worst_sample), "%s|src=%.0f,%.0f,%.0f,%.0f|got=%d,%d,%d,%d",
                    hud ? "HUD" : ((texture_name && *texture_name) ? texture_name : "?"), sr, sg,
                    sb, sa, pr, pg, pb, pa);
    }
  }
}

void note_debug_red_draw(const char* site) {
  if (!armed()) {
    return;
  }
  g_frame.debug_draw.fetch_add(1, std::memory_order_relaxed);
  note_site_name(site);
}

// ============================== LE CHEMIN DISTORTEUR ========================================
// Voir l'en-tete pour le POURQUOI. Ici, seulement des compteurs : l'etat que le pilote rend,
// et la geometrie que la table sinus decrit. Aucune lecture de reglage.
namespace {

std::atomic<uint64_t> g_dz_sprites{0};  // eventails soumis dans l'image
uint64_t g_dz_frames = 0;               // images ou le distorteur a dessine
uint64_t g_dz_sprites_total = 0;
uint64_t g_dz_sprites_max = 0;
uint64_t g_dz_draws_total = 0;
uint64_t g_dz_res_oor = 0;      // `res` hors [3,11] : index de table lu hors bornes
int g_dz_res_lo = 99, g_dz_res_hi = -1;
uint64_t g_dz_area_max_q = 0;   // plus grande fraction d'ecran couverte, x10000
uint64_t g_dz_big = 0;          // eventails couvrant plus de 5 % de l'ecran
uint64_t g_dz_st_oob = 0;       // eventails echantillonnant hors [0,1] : bord etale = aplat
uint64_t g_dz_mismatch_max_q = 0;  // ecart CENTRE echantillonne / CENTRE dessine, x1000
uint64_t g_dz_mismatch_off = 0;    // eventails ou cet ecart depasse un pixel de 512
uint64_t g_dz_scale_max_q = 0;     // plus grande echelle vue (le producteur la borne a 128)
uint64_t g_dz_scale_over = 0;      // eventails d'echelle > 128 : la borne du producteur a cede
int64_t g_dz_st_lo_q = 0, g_dz_st_hi_q = 0;  // l'intervalle reel, x1000
// L'ETAT DE L'ECHANTILLONNEUR.
uint64_t g_dz_fbo_bad = 0;      // images ou la cible de recopie n'etait pas complete
uint64_t g_dz_blit_err = 0;     // images ou la recopie a rendu une erreur GL
unsigned g_dz_fbo_last = 0, g_dz_blit_last = 0;
int g_dz_samples_max = 0;
uint64_t g_dz_probe_frames = 0;   // images sondees
uint64_t g_dz_probe_bad = 0;      // ... dont la copie ne rendait PAS la scene
uint64_t g_dz_probe_px = 0, g_dz_probe_diff = 0;
int g_dz_probe_maxdelta = 0;
char g_dz_probe_sample[96] = {0};
char g_dz_worst[160] = {0};
double g_dz_worst_area = -1.0;
// LE CHEMIN SPRITE ORDINAIRE : combien de dessins, combien sur le damier de secours.
uint64_t g_spr_draws = 0, g_spr_fallback = 0;
// LA TAILLE DES QUADS. `scale-x`/`scale-y` sont en unites GOAL : 4096 = 1 metre.
uint64_t g_spr_size_seen = 0;       // quads mesures (denominateur)
uint64_t g_spr_size_max_cm = 0;     // la plus grande demi-taille vue, en centimetres
uint64_t g_spr_over_10m = 0;        // quads de plus de 10 m de demi-taille
uint64_t g_spr_over_100m = 0;       // ... et de plus de 100 m : hors de toute donnee de niveau
char g_spr_size_worst[96] = {0};
float g_spr_size_worst_v = -1.f;

void publish_overdraw() {
  // LA GRANDEUR DE LA PORTE : le nombre de DESSINS du chemin des particules et des sprites
  // dont l'echantillonneur n'etait pas une texture resolue. Pour le distorteur, « resolue »
  // veut dire : cible de recopie complete, recopie sans erreur, et — quand la sonde a tourne —
  // une copie qui rend REELLEMENT la scene. Pour les seaux sprite : une texture du pool, pas
  // le damier de secours.
  // Un echantillonneur peut etre PARFAITEMENT sain et rendre quand meme un aplat : il suffit
  // qu'on l'interroge au mauvais endroit. La porte compte donc les DEUX familles, et pas
  // seulement la panne de recopie — sans quoi un `0` reviendrait sur un defaut intact, ce qui
  // s'est deja produit deux fois sur cet item.
  //   * la recopie de scene : cible incomplete, erreur GL, ou copie qui ne rend pas la scene ;
  //   * l'interrogation : le centre de l'eventail lit ailleurs qu'a sa propre place
  //     (`center_off`), son echelle depasse la borne du producteur (`scale_over`), ou son
  //     nombre de cotes sort de [3,11] (`res_oor`) ;
  //   * le chemin sprite ordinaire : un seau dessine avec le damier de secours.
  // `st_oob` n'y est PAS : la console d'origine borne elle aussi la region (region-clamp,
  // sprite-distort.gc:110-114), donc un rim qui sort de [0,1] au bord de l'ecran est le
  // comportement voulu. Il reste publie comme temoin.
  autoport_proof::publish("fire_foreign_overdraw",
                          g_dz_probe_bad + g_dz_fbo_bad + g_dz_blit_err + g_spr_fallback +
                              g_dz_mismatch_off + g_dz_scale_over + g_dz_res_oor);
  // LES DENOMINATEURS. Sans eux, un zero peut n'etre qu'une condition absente : un
  // `fire_distort_frames=0` veut dire « aucun feu, aucun portail a l'ecran », pas « rien a
  // signaler ».
  autoport_proof::publish("fire_distort_frames", g_dz_frames);
  autoport_proof::publish("fire_distort_draws", g_dz_draws_total);
  autoport_proof::publish("fire_distort_sprites_seen", g_dz_sprites_total);
  autoport_proof::publish("fire_distort_sprites_max", g_dz_sprites_max);
  autoport_proof::publish("fire_sprite_draws", g_spr_draws);
  autoport_proof::publish("fire_sprite_fallback", g_spr_fallback);
  // LA TAILLE DES QUADS DESSINES. Le denominateur d'abord : un maximum a zero sur zero quad
  // mesure ne dit rien.
  autoport_proof::publish("fire_sprite_size_seen", g_spr_size_seen);
  autoport_proof::publish("fire_sprite_size_max_cm", g_spr_size_max_cm);
  autoport_proof::publish("fire_sprite_over_10m", g_spr_over_10m);
  autoport_proof::publish("fire_sprite_over_100m", g_spr_over_100m);
  autoport_proof::publish_text("fire_sprite_size_worst",
                               g_spr_size_worst[0] ? g_spr_size_worst : "-");
  // L'ETAT DE L'ECHANTILLONNEUR, detaille.
  autoport_proof::publish("fire_distort_fbo_bad", g_dz_fbo_bad);
  autoport_proof::publish("fire_distort_blit_err", g_dz_blit_err);
  autoport_proof::publish("fire_distort_fbo_status", g_dz_fbo_last);
  autoport_proof::publish("fire_distort_blit_last", g_dz_blit_last);
  autoport_proof::publish("fire_distort_fb_samples", (uint64_t)(g_dz_samples_max < 0 ? 0 : g_dz_samples_max));
  autoport_proof::publish("fire_distort_probe_frames", g_dz_probe_frames);
  autoport_proof::publish("fire_distort_probe_bad", g_dz_probe_bad);
  autoport_proof::publish("fire_distort_probe_px", g_dz_probe_px);
  autoport_proof::publish("fire_distort_probe_diff", g_dz_probe_diff);
  autoport_proof::publish("fire_distort_probe_maxdelta",
                          (uint64_t)(g_dz_probe_maxdelta < 0 ? 0 : g_dz_probe_maxdelta));
  autoport_proof::publish_text("fire_distort_probe_sample",
                               g_dz_probe_sample[0] ? g_dz_probe_sample : "-");
  // LA GEOMETRIE : « GRANDE FORME POLYGONALE » chiffree.
  autoport_proof::publish("fire_distort_area_max_q", g_dz_area_max_q);
  autoport_proof::publish("fire_distort_big", g_dz_big);
  autoport_proof::publish("fire_distort_res_oor", g_dz_res_oor);
  autoport_proof::publish("fire_distort_res_lo", (uint64_t)(g_dz_res_hi < 0 ? 0 : g_dz_res_lo));
  autoport_proof::publish("fire_distort_res_hi", (uint64_t)(g_dz_res_hi < 0 ? 0 : g_dz_res_hi));
  autoport_proof::publish("fire_distort_st_oob", g_dz_st_oob);
  // L'ORACLE ANALYTIQUE : l'ecart entre ce que le sommet central ECHANTILLONNE et l'endroit ou
  // il est DESSINE. Zero est la seule valeur que la construction de l'effet autorise.
  autoport_proof::publish("fire_distort_center_mismatch_q", g_dz_mismatch_max_q);
  autoport_proof::publish("fire_distort_center_off", g_dz_mismatch_off);
  autoport_proof::publish("fire_distort_scale_max_q", g_dz_scale_max_q);
  autoport_proof::publish("fire_distort_scale_over", g_dz_scale_over);
  autoport_proof::publish_text("fire_distort_st_range", [] {
    static char b[48];
    std::snprintf(b, sizeof(b), "%lld..%lld/1000", (long long)g_dz_st_lo_q, (long long)g_dz_st_hi_q);
    return b;
  }());
  autoport_proof::publish_text("fire_distort_worst", g_dz_worst[0] ? g_dz_worst : "-");
}

}  // namespace

bool probe_enabled() {
  return autoport_proof::feature_is("fire-red-particles") && armed();
}

void note_distort_sprite(int res,
                         float area,
                         float st_lo,
                         float st_hi,
                         float mismatch,
                         const float* pos,
                         const float* scale,
                         const float* st) {
  if (!armed()) {
    return;
  }
  g_dz_sprites.fetch_add(1, std::memory_order_relaxed);
  if (res < 3 || res > 11) {
    g_dz_res_oor++;
  }
  if (res < g_dz_res_lo) {
    g_dz_res_lo = res;
  }
  if (res > g_dz_res_hi) {
    g_dz_res_hi = res;
  }
  if (!std::isfinite(area)) {
    area = 1.f;  // une aire non finie couvre, par construction, tout ce qu'on peut voir
  }
  const uint64_t q = (uint64_t)(area * 10000.f);
  if (q > g_dz_area_max_q) {
    g_dz_area_max_q = q;
  }
  if (area > 0.05f) {
    g_dz_big++;
  }
  if (std::isfinite(st_lo) && std::isfinite(st_hi)) {
    if (st_lo < -0.001f || st_hi > 1.001f) {
      g_dz_st_oob++;
    }
    const int64_t lo = (int64_t)(st_lo * 1000.f), hi = (int64_t)(st_hi * 1000.f);
    if (lo < g_dz_st_lo_q) {
      g_dz_st_lo_q = lo;
    }
    if (hi > g_dz_st_hi_q) {
      g_dz_st_hi_q = hi;
    }
  } else {
    g_dz_st_oob++;
  }
  if (std::isfinite(mismatch)) {
    const uint64_t mq = (uint64_t)(mismatch * 1000.f + 0.5f);
    if (mq > g_dz_mismatch_max_q) {
      g_dz_mismatch_max_q = mq;
    }
    // Un pixel sur 512 : en dessous, c'est l'arrondi du flottant, pas un decalage.
    if (mismatch > 1.f / 512.f) {
      g_dz_mismatch_off++;
    }
  } else {
    g_dz_mismatch_off++;
  }
  {
    const float sx = std::fabs(scale[0]), sy = std::fabs(scale[1]);
    const float smax = sx > sy ? sx : sy;
    if (std::isfinite(smax)) {
      const uint64_t sq = (uint64_t)smax;
      if (sq > g_dz_scale_max_q) {
        g_dz_scale_max_q = sq;
      }
      if (smax > 128.f) {
        g_dz_scale_over++;
      }
    } else {
      g_dz_scale_over++;
    }
  }
  if (area > g_dz_worst_area) {
    g_dz_worst_area = area;
    std::snprintf(g_dz_worst, sizeof(g_dz_worst),
                  "res=%d|aire=%.4f|uv=%.3f,%.3f|plage=%.2f..%.2f|ecart=%.4f|p=%.0f,%.0f|e=%.1f,%.1f,%.1f",
                  res, (double)area, (double)st[0], (double)st[1], (double)st_lo, (double)st_hi,
                  (double)mismatch, (double)pos[0], (double)pos[1], (double)scale[0],
                  (double)scale[1], (double)scale[2]);
  }
}

void note_distort_frame(unsigned fbo_status,
                        unsigned blit_err,
                        int samples,
                        int sprites,
                        int draws,
                        int probe_px,
                        int probe_diff,
                        int probe_maxdelta,
                        const char* sample) {
  if (!armed()) {
    return;
  }
  g_dz_frames++;
  g_dz_sprites.store(0, std::memory_order_relaxed);
  g_dz_sprites_total += (uint64_t)(sprites < 0 ? 0 : sprites);
  if ((uint64_t)sprites > g_dz_sprites_max) {
    g_dz_sprites_max = (uint64_t)sprites;
  }
  g_dz_draws_total += (uint64_t)(draws < 0 ? 0 : draws);
  g_dz_fbo_last = fbo_status;
  g_dz_blit_last = blit_err;
  if (fbo_status != 0x8CD5u) {  // GL_FRAMEBUFFER_COMPLETE
    g_dz_fbo_bad++;
  }
  if (blit_err != 0) {
    g_dz_blit_err++;
  }
  if (samples > g_dz_samples_max) {
    g_dz_samples_max = samples;
  }
  if (probe_px > 0) {
    g_dz_probe_frames++;
    g_dz_probe_px += (uint64_t)probe_px;
    g_dz_probe_diff += (uint64_t)(probe_diff < 0 ? 0 : probe_diff);
    if (probe_maxdelta > g_dz_probe_maxdelta) {
      g_dz_probe_maxdelta = probe_maxdelta;
    }
    // UNE TOLERANCE, ET ELLE EST DITE. La recopie est un `glBlitFramebuffer` NEAREST entre
    // deux tampons de MEMES dimensions : elle est censee etre exacte. On laisse 2/255 de jeu
    // pour un format de copie plus court (RGB8 contre RGBA8), et rien de plus.
    if (probe_diff > 0 && probe_maxdelta > 2) {
      g_dz_probe_bad++;
    }
    if (sample && sample[0]) {
      std::snprintf(g_dz_probe_sample, sizeof(g_dz_probe_sample), "%s", sample);
    }
  }
}

void note_sprite_size(const char* texture_name, float sx, float sy) {
  if (!armed()) {
    return;
  }
  g_spr_size_seen++;
  const float ax = std::fabs(sx), ay = std::fabs(sy);
  const float m = ax > ay ? ax : ay;
  if (!std::isfinite(m)) {
    g_spr_over_100m++;
    g_spr_over_10m++;
    return;
  }
  const uint64_t cm = (uint64_t)(m * (100.f / 4096.f));
  if (cm > g_spr_size_max_cm) {
    g_spr_size_max_cm = cm;
  }
  if (m > 10.f * 4096.f) {
    g_spr_over_10m++;
  }
  if (m > 100.f * 4096.f) {
    g_spr_over_100m++;
  }
  if (m > g_spr_size_worst_v) {
    g_spr_size_worst_v = m;
    std::snprintf(g_spr_size_worst, sizeof(g_spr_size_worst), "%s|sx=%.2fm|sy=%.2fm",
                  texture_name ? texture_name : "?", (double)(sx / 4096.f),
                  (double)(sy / 4096.f));
  }
}

void note_sprite_sampler(bool resolved) {
  if (!armed()) {
    return;
  }
  g_spr_draws++;
  if (!resolved) {
    g_spr_fallback++;
  }
}

void end_frame() {
  if (!armed()) {
    return;
  }
  const uint64_t sprites = g_frame.sprites.exchange(0, std::memory_order_relaxed);
  const uint64_t red = g_frame.red_visible.exchange(0, std::memory_order_relaxed);
  const uint64_t c_alpha = g_frame.carrier_alpha.exchange(0, std::memory_order_relaxed);
  const uint64_t c_afail = g_frame.carrier_afail.exchange(0, std::memory_order_relaxed);
  const uint64_t nonfinite = g_frame.nonfinite.exchange(0, std::memory_order_relaxed);
  const uint64_t debug = g_frame.debug_draw.exchange(0, std::memory_order_relaxed);
  const uint64_t middot = g_frame.middot.exchange(0, std::memory_order_relaxed);
  const uint64_t middot_vis = g_frame.middot_visible.exchange(0, std::memory_order_relaxed);
  const uint64_t pack = g_frame.pack.exchange(0, std::memory_order_relaxed);
  const uint64_t pack_oor = g_frame.pack_oor.exchange(0, std::memory_order_relaxed);
  const uint64_t pack_foreign = g_frame.pack_foreign.exchange(0, std::memory_order_relaxed);
  const uint64_t pack_oldwrap = g_frame.pack_oldwrap.exchange(0, std::memory_order_relaxed);
  const uint64_t a0_afail = g_frame.a0_afail.exchange(0, std::memory_order_relaxed);
  const uint64_t clamp255 = g_frame.clamp255.exchange(0, std::memory_order_relaxed);
  const uint64_t ember_cl = g_frame.ember_clamped.exchange(0, std::memory_order_relaxed);
  const uint64_t warp_cl = g_frame.warp_clamped.exchange(0, std::memory_order_relaxed);

  g_frames++;
  g_sprites_total += sprites;
  if (sprites > g_sprites_max) {
    g_sprites_max = sprites;
  }
  if (red > g_red_max) {
    g_red_max = red;
  }
  if (c_alpha > g_carrier_alpha_max) {
    g_carrier_alpha_max = c_alpha;
  }
  if (c_afail > g_carrier_afail_max) {
    g_carrier_afail_max = c_afail;
  }
  if (nonfinite > g_nonfinite_max) {
    g_nonfinite_max = nonfinite;
  }
  if (debug > g_debug_max) {
    g_debug_max = debug;
  }
  g_middot_total += middot;
  if (middot > g_middot_max) {
    g_middot_max = middot;
  }
  if (middot_vis > g_middot_visible_max) {
    g_middot_visible_max = middot_vis;
  }
  g_pack_total += pack;
  g_pack_oor_total += pack_oor;
  g_pack_oldwrap_total += pack_oldwrap;
  if (pack_foreign > g_pack_foreign_max) {
    g_pack_foreign_max = pack_foreign;
  }
  if (pack_oldwrap > g_pack_oldwrap_max) {
    g_pack_oldwrap_max = pack_oldwrap;
  }
  g_clamp255_total += clamp255;
  g_ember_clamped_total += ember_cl;
  g_warp_clamped_total += warp_cl;
  if (a0_afail > g_a0_afail_max) {
    g_a0_afail_max = a0_afail;
  }
  const uint64_t worst = c_alpha + c_afail + nonfinite + debug + pack_foreign;
  if (worst > g_worst) {
    g_worst = worst;
  }

  // LA GRANDEUR DE LA PORTE, et rien d'autre dedans : le compte, par image, de ce qui dessine
  // en rouge sur ou au-dessus du feu sans appartenir au jeu d'origine.
  autoport_proof::publish("fire_debug_particles", g_worst);
  // Les temoins qui rendent ce zero falsifiable.
  autoport_proof::publish("fire_census_frames", g_frames);
  autoport_proof::publish("fire_sprites_seen", g_sprites_total);
  autoport_proof::publish("fire_sprites_max", g_sprites_max);
  // Le detail, famille par famille.
  autoport_proof::publish("fire_carrier_alpha_max", g_carrier_alpha_max);
  autoport_proof::publish("fire_carrier_afail_max", g_carrier_afail_max);
  autoport_proof::publish("fire_nonfinite_max", g_nonfinite_max);
  autoport_proof::publish("fire_debug_draw_max", g_debug_max);
  // Le denominateur du bras porteur : `fire_carrier_*_max=0` n'est un verdict que si
  // `fire_middot_seen` est non nul — sinon la condition testee etait simplement absente.
  autoport_proof::publish("fire_middot_seen", g_middot_total);
  autoport_proof::publish("fire_middot_max", g_middot_max);
  autoport_proof::publish("fire_middot_visible_max", g_middot_visible_max);
  // Les braises d'ORIGINE (2292), hors perimetre : publiees pour que leur presence ne puisse
  // pas etre confondue avec un zero de l'instrument.
  autoport_proof::publish("fire_red_sprites_max", g_red_max);
  autoport_proof::publish_text("fire_debug_sites", g_sites[0] ? g_sites : "-");

  // L'ORACLE DE LA COULEUR. `fire_pack_foreign_max` est la part de `fire_debug_particles` qui
  // vient d'ici ; les trois suivants sont ce qui la rend falsifiable.
  autoport_proof::publish("fire_pack_foreign_max", g_pack_foreign_max);
  autoport_proof::publish("fire_pack_seen", g_pack_total);
  // `fire_pack_oor_seen` > 0 : il EXISTE des sprites dont la couleur source sort de [0,255],
  // donc des sprites sur lesquels repliement et saturation ne disent pas la meme chose. Un
  // `fire_pack_foreign_max=0` avec ce compte a zero ne serait qu'une condition absente.
  autoport_proof::publish("fire_pack_oor_seen", g_pack_oor_total);
  // LA TAILLE DU DEFAUT, mesuree dans la MEME course : le nombre de sprites que l'ancienne
  // politique `& 0xff` coloriait autrement que ce que la donnee decrit, et de combien.
  autoport_proof::publish("fire_pack_oldwrap_max", g_pack_oldwrap_max);
  autoport_proof::publish("fire_pack_oldwrap_seen", g_pack_oldwrap_total);
  autoport_proof::publish("fire_pack_olddelta_max", g_pack_olddelta_max);
  // Le HUD, hors porte et nomme : son repliement est voulu.
  autoport_proof::publish("fire_pack_foreign_hud", g_pack_foreign_hud_total);
  autoport_proof::publish("fire_pack_foreign_a0", g_pack_foreign_a0_total);
  autoport_proof::publish("fire_pack_oor_vis", g_oor_vis_total);
  // LA PREUVE QUE LA BORNE A TIRE, famille par famille. Un zero ici ne dit pas « la borne n'a
  // rien fait » mais « cette famille n'etait pas a l'ecran pendant la course » : les deux se
  // lisent ensemble avec `fire_sprites_seen`.
  autoport_proof::publish("fire_ember_clamped", g_ember_clamped_total);
  autoport_proof::publish("fire_warp_clamped", g_warp_clamped_total);
  {
    char buf[352];
    int off = 0;
    for (int i = 0; i < g_oor_sample_n && off < (int)sizeof(buf) - 1; i++) {
      off += std::snprintf(buf + off, sizeof(buf) - off, "%s%s", off ? "," : "", g_oor_samples[i]);
    }
    autoport_proof::publish_text("fire_oor_samples", off ? buf : "-");
  }
  autoport_proof::publish("fire_a0_afail_max", g_a0_afail_max);
  autoport_proof::publish_text("fire_pack_worst", g_worst_sample[0] ? g_worst_sample : "-");
  {
    char ch[8];
    int n = 0;
    const char* names = "rgba";
    for (int i = 0; i < 4; i++) {
      if (g_pack_foreign_chan & (1u << i)) {
        ch[n++] = names[i];
      }
    }
    ch[n] = 0;
    autoport_proof::publish_text("fire_pack_foreign_chan", n ? ch : "-");
  }
  {
    // Chaine VIDE interdite : `publish_text` garderait la valeur de l'image precedente.
    char buf[320];
    format_emitters(buf, sizeof(buf), g_emitters, g_emitter_n, g_emitter_dropped);
    autoport_proof::publish_text("fire_pack_emitters", buf);
    format_emitters(buf, sizeof(buf), g_clamp_emitters, g_clamp_emitter_n,
                    g_clamp_emitter_dropped);
    autoport_proof::publish_text("fire_src255_emitters", buf);
  }
  autoport_proof::publish("fire_src255_seen", g_clamp255_total);
  // Le distorteur publie a CHAQUE image, meme quand il n'a rien dessine : sinon la porte
  // n'aurait aucune valeur a lire dans une course ou aucun feu n'est passe a l'ecran, et un
  // champ absent ne se distingue pas d'un zero.
  publish_overdraw();
  if (sprites > 0) {
    // Le chemin de la feature a tourne SUR des sprites de feu : c'est ce que `hits` doit dire.
    autoport_proof::note_hit(1);
  }
}

}  // namespace fire_red_census
