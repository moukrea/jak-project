#include "fire_red_census.h"

#include <atomic>
#include <cmath>
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
uint64_t g_worst = 0;  // max sur une image de la somme des quatre familles non-originelles
char g_sites[192] = {0};

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

void note_debug_red_draw(const char* site) {
  if (!armed()) {
    return;
  }
  g_frame.debug_draw.fetch_add(1, std::memory_order_relaxed);
  note_site_name(site);
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
  const uint64_t worst = c_alpha + c_afail + nonfinite + debug;
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
  if (sprites > 0) {
    // Le chemin de la feature a tourne SUR des sprites de feu : c'est ce que `hits` doit dire.
    autoport_proof::note_hit(1);
  }
}

}  // namespace fire_red_census
