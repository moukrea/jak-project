#include "hud_box_probe.h"

#include <cstdlib>
#include <cstring>
#include <vector>

#include "third-party/glad/include/glad/glad.h"

#include "game/system/autoport_proof.h"

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

// Ce site appartient a hud-3d-pickups : la porte doit pouvoir separer « instrument absent du
// binaire » de « instrument present, jamais atteint ».
AUTOPORT_FEATURE_SITE("hud-3d-pickups");

namespace hud_box_probe {
namespace {

// ── LE DISCRIMINANT, ET LES DEUX QUI ONT ECHOUE AVANT LUI ────────────────────────────────────
//
// Ce qu'on cherche : les pixels que l'apparition d'UN modele de HUD change dans l'image finale.
// Ce qui gene : le monde continue de bouger entre les deux images d'une paire.
//
// ESSAI A — « le pixel a change entre l'image cachee et l'image dessinee », accord a 3 paires sur
// 4. Mesure x86 du 17/09 : le slot de CONTROLE — deux images du MEME etat, donc rien a voir —
// gardait 57 pixels, et les quatre boites d'elements etaient faites de ce meme paquet. Les
// animations du monde sont periodiques : une paire prise toujours au meme intervalle retombe sur
// la meme phase, donc sur les memes pixels.
//
// ESSAI B — meme regle, intervalle entre paires jitter et accord monte a 19 sur 20. Le controle
// tombe bien a 0, mais l'element AUSSI (1 pixel retenu). Un pixel couvert par le modele ne
// « change » que si le decor derriere lui differe assez du modele, et sur 48 tirages il arrive
// toujours quelques fois que non. Les deux distributions se recouvrent entierement : palier 50 %
// = 9008 pour notre pile contre 8581 pour le controle, palier 90 % = 0 pour les deux.
//
// ESSAI C — CELUI-CI, et il ne repose pas sur la meme propriete. La pose des modeles est FIGEE
// pendant la sequence (cote GOAL, `hud3d-px-freeze`). Donc :
//   * un pixel couvert par le modele vaut, a chaque image « dessine », LA MEME VALEUR ;
//   * un pixel du decor vaut, a chaque image « dessine », une valeur qui derive avec le monde.
// Le test devient une CONJONCTION : le pixel doit (1) differer de l'image de reference — sinon
// c'est du decor immobile — ET (2) valoir la MEME chose que lors de la premiere image
// « dessine » — ce que seul un pixel du modele fait. Le decor mobile echoue sur (2), le decor
// immobile echoue sur (1). Le slot de CONTROLE juge le tout : deux images du meme etat n'ont, par
// construction, aucun pixel qui satisfasse les deux ; ce qui y survit est le plancher de
// l'instrument, il est publie, et non nul il invalide la mesure au lieu de la decorer.

// Ecart de luminance au-dela duquel un pixel est dit DIFFERENT de l'image de reference.
constexpr int kThresh = 10;
// Ecart de luminance en deca duquel deux images « dessine » sont dites IDENTIQUES en ce pixel.
// Plus serre que kThresh : c'est la stabilite du modele fige qui porte toute la separation.
constexpr int kStable = 6;
// Un pixel n'est retenu que s'il satisfait la conjonction dans 19 paires sur 20.
constexpr int kAgreeNum = 19;
constexpr int kAgreeDen = 20;
// Plafond de paires par emplacement : au-dela la mesure ne bouge plus, et chaque paire coute une
// relecture de l'image finale — le banc de cout (§4 du contrat) mesurerait notre instrument.
constexpr int kMaxPairs = 48;

struct SlotState {
  std::vector<uint8_t> agree;    // par pixel, paires ou la conjonction tient (sature a 255)
  std::vector<uint8_t> ref_lum;  // la premiere image « dessine » de ce slot, en luminance
  bool ref_set = false;
  int samples = 0;
  int empty = 0;
  bool dirty = true;
  int min_x = 0, min_y = 0, max_x = 0, max_y = 0, pixels = 0;
  // DIAGNOSTIC : ce que la paire a retenu AVANT le filtre d'accord. Sans lui, un slot a 0 pixel
  // ne dit pas si rien n'a bascule ou si le filtre a tout mange : meme zero, causes opposees.
  uint64_t raw_sum = 0;
  int raw_max = 0;
  int excluded = 0;
};

bool g_checked = false;
bool g_armed = false;
int g_pending = -1;

std::vector<uint8_t> g_base_lum;  // l'image de reference, en luminance
int g_region_w = 0;
int g_region_h = 0;
bool g_base_valid = false;

int g_captures = 0;
int g_read_errors = 0;
bool g_error_named = false;
int g_base_lum_mean = 0;
unsigned g_last_fbo = 0;
int g_source = 0;  // 0 = la fenetre (l'image finale), 1 = la cible de rendu interne

SlotState g_slots[kSlotCount];
std::vector<uint8_t> g_rgba;  // tampon de relecture, reutilise
std::vector<uint8_t> g_lum;   // sa conversion en luminance, reutilisee

bool probe_key_matches() {
  const char* want = "hud-3d-pickups";
  const char* env = std::getenv("AUTOPORT_COST_PROBE");
  if (env && env[0]) {
    return std::strcmp(env, want) == 0;
  }
#if defined(__ANDROID__)
  char pv[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.costprobe", pv) > 0 && pv[0]) {
    return std::strcmp(pv, want) == 0;
  }
#endif
  return false;
}

// LIRE UNE REGION QUELCONQUE, Y COMPRIS DANS LE TAMPON DE FENETRE. La fenetre (FBO 0) n'a pas
// d'attachement de couleur — elle se lit par `GL_BACK` — et l'image composee y vit a un decalage.
// On garde la discipline de `ao_contact_readback` : sauvegarde et restauration completes de
// l'etat de pack et des liaisons de lecture, erreur nommee par etage.
bool read_region(GLuint fbo, GLenum buffer, int x, int y, int w, int h, const char*& why) {
  why = nullptr;
  if (w <= 0 || h <= 0 || (size_t)w > (64u * 1024u * 1024u) / (size_t)h) {
    why = "invalid-dimensions";
    return false;
  }
  while (glGetError() != GL_NO_ERROR) {
  }
  try {
    g_rgba.resize((size_t)w * (size_t)h * 4);
  } catch (const std::exception&) {
    why = "allocation";
    return false;
  }
  GLint read_fbo = 0, read_buffer = 0, pack_buffer = 0;
  GLint alignment = 0, row_length = 0, skip_rows = 0, skip_pixels = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read_fbo);
  glGetIntegerv(GL_READ_BUFFER, &read_buffer);
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pack_buffer);
  glGetIntegerv(GL_PACK_ALIGNMENT, &alignment);
  glGetIntegerv(GL_PACK_ROW_LENGTH, &row_length);
  glGetIntegerv(GL_PACK_SKIP_ROWS, &skip_rows);
  glGetIntegerv(GL_PACK_SKIP_PIXELS, &skip_pixels);

  bool ok = true;
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
  GLint prev_target = 0;
  glGetIntegerv(GL_READ_BUFFER, &prev_target);
  glReadBuffer(buffer);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glPixelStorei(GL_PACK_ROW_LENGTH, 0);
  glPixelStorei(GL_PACK_SKIP_ROWS, 0);
  glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
  if (glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    why = "incomplete-read-framebuffer";
    ok = false;
  } else {
    glReadPixels(x, y, w, h, GL_RGBA, GL_UNSIGNED_BYTE, g_rgba.data());
    if (glGetError() != GL_NO_ERROR) {
      why = "readback-gl-error";
      ok = false;
    }
  }
  glReadBuffer(prev_target);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, read_fbo);
  glReadBuffer(read_buffer);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, pack_buffer);
  glPixelStorei(GL_PACK_ALIGNMENT, alignment);
  glPixelStorei(GL_PACK_ROW_LENGTH, row_length);
  glPixelStorei(GL_PACK_SKIP_ROWS, skip_rows);
  glPixelStorei(GL_PACK_SKIP_PIXELS, skip_pixels);
  while (glGetError() != GL_NO_ERROR) {
  }
  return ok;
}

void to_luminance(size_t n) {
  g_lum.resize(n);
  for (size_t i = 0; i < n; i++) {
    // Rec.601 en entiers. La chroma seule ne porte pas la separation, et une luminance par pixel
    // divise par quatre la memoire que la sonde immobilise sur le telephone.
    const int r = g_rgba[i * 4 + 0], g = g_rgba[i * 4 + 1], b = g_rgba[i * 4 + 2];
    g_lum[i] = (uint8_t)((77 * r + 150 * g + 29 * b) >> 8);
  }
}

// CE QUE LE CONTROLE VOIT SURVIVRE N'APPARTIENT A AUCUN ELEMENT : deux images du meme etat.
bool ctrl_holds(size_t i) {
  const SlotState& c = g_slots[kControl];
  if (c.samples <= 0 || c.agree.size() <= i) {
    return false;
  }
  const int need = (c.samples * kAgreeNum + kAgreeDen - 1) / kAgreeDen;
  return (int)c.agree[i] >= need;
}

void recompute(SlotState& s) {
  s.dirty = false;
  s.min_x = s.min_y = s.max_x = s.max_y = s.pixels = s.excluded = 0;
  if (s.samples <= 0 || g_region_w <= 0 || g_region_h <= 0 ||
      s.agree.size() != (size_t)g_region_w * (size_t)g_region_h) {
    return;
  }
  const int need = (s.samples * kAgreeNum + kAgreeDen - 1) / kAgreeDen;
  const bool subtract = (&s != &g_slots[kControl]);
  int lo_x = g_region_w, lo_y = g_region_h, hi_x = -1, hi_y = -1, n = 0;
  for (int y = 0; y < g_region_h; y++) {
    const size_t base = (size_t)y * g_region_w;
    for (int x = 0; x < g_region_w; x++) {
      if ((int)s.agree[base + x] < need) {
        continue;
      }
      if (subtract && ctrl_holds(base + x)) {
        s.excluded++;
        continue;
      }
      n++;
      if (x < lo_x) lo_x = x;
      if (x > hi_x) hi_x = x;
      if (y < lo_y) lo_y = y;
      if (y > hi_y) hi_y = y;
    }
  }
  if (hi_x < 0) {
    return;
  }
  s.min_x = lo_x;
  s.min_y = lo_y;
  s.max_x = hi_x;
  s.max_y = hi_y;
  s.pixels = n;
}

void note_error(const char* why) {
  g_read_errors++;
  if (!g_error_named) {
    g_error_named = true;
    autoport_proof::publish_text("hud3d_px_error", why);
  }
}

void publish_diag() {
  autoport_proof::publish("hud3d_px_captures", (uint64_t)g_captures);
  autoport_proof::publish("hud3d_px_read_errors", (uint64_t)g_read_errors);
  autoport_proof::publish("hud3d_px_thresh", (uint64_t)kThresh);
  autoport_proof::publish("hud3d_px_stable", (uint64_t)kStable);
  autoport_proof::publish("hud3d_px_agree_pct", (uint64_t)(100 * kAgreeNum / kAgreeDen));
  autoport_proof::publish("hud3d_px_region_w", (uint64_t)(g_region_w < 0 ? 0 : g_region_w));
  autoport_proof::publish("hud3d_px_region_h", (uint64_t)(g_region_h < 0 ? 0 : g_region_h));
  autoport_proof::publish("hud3d_px_base_lum",
                          (uint64_t)(g_base_lum_mean < 0 ? 0 : g_base_lum_mean));
  autoport_proof::publish("hud3d_px_fbo", (uint64_t)g_last_fbo);
  autoport_proof::publish("hud3d_px_source_is_internal_fbo", (uint64_t)g_source);
  if (!g_error_named) {
    autoport_proof::publish_text("hud3d_px_error", "-");
  }
}

void reset_all() {
  g_base_valid = false;
  for (auto& s : g_slots) {
    s.agree.clear();
    s.ref_lum.clear();
    s.ref_set = false;
    s.samples = 0;
    s.empty = 0;
    s.raw_sum = 0;
    s.raw_max = 0;
    s.dirty = true;
  }
}

}  // namespace

bool armed() {
  if (!g_checked) {
    g_checked = true;
    g_armed = probe_key_matches();
  }
  return g_armed;
}

void request(int slot) {
  if (!armed() || slot < 0 || slot >= kSlotCount) {
    return;
  }
  // Le plafond porte sur les paires deja retenues ; la reference reste capturable pour que le
  // dernier etat connu ne devienne pas perime.
  if (slot != kBase && g_slots[slot].samples >= kMaxPairs) {
    return;
  }
  g_pending = slot;
}

void end_of_frame(unsigned fbo_id,
                  int fbo_w,
                  int fbo_h,
                  int win_x,
                  int win_y,
                  int win_w,
                  int win_h) {
  if (!armed()) {
    return;
  }
  const int slot = g_pending;
  g_pending = -1;
  if (slot < 0) {
    return;
  }

  // LA FENETRE D'ABORD : c'est l'image que la dalle recoit. La cible de rendu interne peut etre
  // celle de la resolution dynamique, ou le HUD n'est PAS composite — mesure x86 du 17/09 :
  // 480x216 contre 1200x540, et montrer ou cacher une icone n'y changeait rien. La source servie
  // est publiee : une mesure qui ne dit pas ce qu'elle a lu ne se relit pas.
  const char* why = nullptr;
  int w = win_w, h = win_h, source = 0;
  bool ok = win_w > 0 && win_h > 0 && read_region(0, GL_BACK, win_x, win_y, win_w, win_h, why);
  if (!ok) {
    w = fbo_w;
    h = fbo_h;
    source = 1;
    ok = fbo_w > 0 && fbo_h > 0 &&
         read_region((GLuint)fbo_id, GL_COLOR_ATTACHMENT0, 0, 0, fbo_w, fbo_h, why);
  }
  if (!ok) {
    note_error(why ? why : "short-readback");
    return;
  }
  g_source = source;
  g_last_fbo = source ? fbo_id : 0;
  g_captures++;

  const size_t n = (size_t)w * (size_t)h;
  to_luminance(n);

  // Un changement de taille invalide tout ce qui a ete accumule : deux boites lues a des
  // resolutions differentes ne se comparent pas.
  if (w != g_region_w || h != g_region_h) {
    g_region_w = w;
    g_region_h = h;
    reset_all();
  }

  if (slot == kBase) {
    g_base_lum = g_lum;
    g_base_valid = true;
    uint64_t sum = 0;
    size_t cnt = 0;
    for (size_t i = 0; i < n; i += 16) {
      sum += g_base_lum[i];
      cnt++;
    }
    g_base_lum_mean = cnt ? (int)(sum / cnt) : 0;
    publish_diag();
    return;
  }
  if (!g_base_valid || g_base_lum.size() != n) {
    note_error("no-base");
    return;
  }

  SlotState& s = g_slots[slot];
  if (s.agree.size() != n) {
    s.agree.assign(n, 0);
    s.ref_lum.clear();
    s.ref_set = false;
    s.samples = 0;
    s.empty = 0;
    s.raw_sum = 0;
    s.raw_max = 0;
  }
  if (!s.ref_set) {
    // La PREMIERE image « dessine » de ce slot devient sa reference de stabilite. Elle ne compte
    // pas comme une paire : on ne peut pas se comparer a soi-meme.
    s.ref_lum = g_lum;
    s.ref_set = true;
    s.dirty = true;
    publish_diag();
    return;
  }

  int changed = 0;
  for (size_t i = 0; i < n; i++) {
    const int lum = g_lum[i];
    const int d_base = lum - (int)g_base_lum[i];
    const int d_ref = lum - (int)s.ref_lum[i];
    if ((d_base > kThresh || d_base < -kThresh) && d_ref <= kStable && d_ref >= -kStable) {
      changed++;
      if (s.agree[i] < 255) {
        s.agree[i]++;
      }
    }
  }
  s.samples++;
  s.raw_sum += (uint64_t)changed;
  if (changed > s.raw_max) {
    s.raw_max = changed;
  }
  if (changed == 0) {
    s.empty++;
  }
  s.dirty = true;
  publish_diag();
}

int64_t read(int slot, int field) {
  if (slot < 0 || slot >= kSlotCount || field < 0 || field >= kFieldCount) {
    return -1;
  }
  SlotState& s = g_slots[slot];
  switch (field) {
    case kRegionW:
      return g_region_w;
    case kRegionH:
      return g_region_h;
    case kSamples:
      return s.samples;
    case kEmpty:
      return s.empty;
    case kBaseLum:
      return g_base_lum_mean;
    case kRawMean:
      return s.samples > 0 ? (int64_t)(s.raw_sum / (uint64_t)s.samples) : 0;
    case kRawMax:
      return s.raw_max;
    default:
      break;
  }
  if (field == kAgreeMax || field == kP50 || field == kP75 || field == kP90 || field == kP100) {
    if (s.samples <= 0 || s.agree.empty()) {
      return 0;
    }
    if (field == kAgreeMax) {
      int m = 0;
      for (uint8_t v : s.agree) {
        if ((int)v > m) m = (int)v;
      }
      return m;
    }
    const int pct = field == kP50 ? 50 : field == kP75 ? 75 : field == kP90 ? 90 : 100;
    const int need2 = (s.samples * pct + 99) / 100;
    int64_t n2 = 0;
    for (uint8_t v : s.agree) {
      if ((int)v >= need2) n2++;
    }
    return n2;
  }
  if (s.dirty) {
    recompute(s);
  }
  switch (field) {
    case kMinX:
      return s.min_x;
    case kMinY:
      return s.min_y;
    case kMaxX:
      return s.max_x;
    case kMaxY:
      return s.max_y;
    case kPixels:
      return s.pixels;
    case kExcluded:
      return s.excluded;
    default:
      return -1;
  }
}

}  // namespace hud_box_probe
