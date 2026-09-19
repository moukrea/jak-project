#include "hud_box_probe.h"

#include <atomic>
#include <cfloat>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
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
  // LA DERIVE DE L'IMAGE, MESUREE AU LIEU D'ETRE SUPPOSEE. Ecart absolu moyen, par pixel et par
  // paire, entre l'image « dessine » et la reference de stabilite du slot. C'est la grandeur qui
  // dit si la conjonction echoue parce que le decor bouge ou parce que l'element n'est pas la.
  uint64_t drift_sum = 0;
};

bool g_armed = false;
int g_pending = -1;

// POURQUOI L'ARMEMENT NE LIT PLUS DE PROPRIETE ICI (course appareil du 17/09, essai 3).
// Cette unite lisait `debug.opengoal.costprobe` pour son propre compte, et mettait le resultat en
// cache au PREMIER appel. La course du 17/09 a rendu, dans la MEME preuve :
//   hud3d_probe_on=1        (kmachine, meme propriete, relue a chaque image : la sonde est bien la)
//   hud3d_px_cycles=231     (GOAL a demande 2310 captures)
//   et AUCUNE des cles de `publish_diag()` dans tout le journal de la course.
// Autrement dit : `request()` a ete appele 2310 fois et n'a rien fait. Une deuxieme copie du
// meme test, armee a un autre instant et sur un autre fil, a rendu l'inverse de la premiere.
// On supprime la copie : l'instrument est arme PAR LA DEMANDE DE GOAL, c'est-a-dire par le seul
// signal dont la preuve etablit qu'il fonctionne sur l'appareil. GOAL n'appelle
// `__pc-autoport-hud-capture` que sous `(-> this probe?)`, donc le joueur ne paie toujours rien :
// hors course de preuve, `armed()` reste faux pour toujours et rien n'est alloue.
// Ce que la propriete AURAIT rendu est quand meme publie (`hud3d_px_prop_match`), avec le nombre
// de demandes et d'appels de fin d'image : si la prochaine course echoue encore, elle NOMME
// lequel des trois etages est muet au lieu de rendre trois zeros identiques.
int g_requests = 0;
int g_eof_calls = 0;
int g_prop_match = -1;

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
  // LES TROIS ETAGES, SEPAREMENT. demandes -> appels de fin d'image -> relectures reussies.
  // Un zero a un etage donne et non aux precedents dit lequel est muet ; trois zeros disaient
  // seulement « rien n'a tourne », ce qui a coute l'essai 3.
  autoport_proof::publish("hud3d_px_requests", (uint64_t)g_requests);
  autoport_proof::publish("hud3d_px_eof_calls", (uint64_t)g_eof_calls);
  // 1 = la propriete `debug.opengoal.costprobe` porte bien notre identifiant vue d'ICI ;
  // 0 = elle ne le porte pas, alors que kmachine la lit et rend 1 (hud3d_probe_on).
  autoport_proof::publish("hud3d_px_prop_match", (uint64_t)(g_prop_match < 0 ? 0 : g_prop_match));
  // LA DERIVE, EN MILLIEMES DE NIVEAU DE LUMINANCE PAR PIXEL ET PAR PAIRE. Zero = deux images
  // « dessine » consecutives sont identiques et la conjonction ne peut echouer que faute
  // d'element ; une valeur elevee dit que l'image bouge sous l'instrument.
  {
    const uint64_t px = (uint64_t)(g_region_w > 0 ? g_region_w : 0) *
                        (uint64_t)(g_region_h > 0 ? g_region_h : 0);
    static const char* kDriftKeys[kSlotCount] = {
        "hud3d_px_drift_base",   "hud3d_px_drift_cell_stock", "hud3d_px_drift_cell_ours",
        "hud3d_px_drift_buzzer", "hud3d_px_drift_orb",        "hud3d_px_drift_ctrl"};
    for (int i = 0; i < kSlotCount; i++) {
      const SlotState& d = g_slots[i];
      const uint64_t den = px * (uint64_t)(d.samples > 0 ? d.samples : 0);
      autoport_proof::publish(kDriftKeys[i], den ? (uint64_t)((d.drift_sum * 1000ull) / den) : 0ull);
    }
  }
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
    s.drift_sum = 0;
    s.dirty = true;
  }
}

// ── ESSAI 7 — LA BOITE DES SOMMETS TRANSFORMES (voir l'en-tete) ───────────────────────────────
//
// Deux fils : GOAL arme (`vbox_request`) et relit (`vbox_read`) ; le fil de rendu accumule
// (`vbox_note_draw`) et retient (`vb_end_of_frame`). L'accumulateur et les slots vivent sous UN
// mutex ; le seul chemin chaud — « y a-t-il une demande ? » a chaque appel de dessin HUD — est une
// lecture atomique sans verrou.
struct VboxAcc {
  bool any = false;
  float pre_min[2] = {FLT_MAX, FLT_MAX};
  float pre_max[2] = {-FLT_MAX, -FLT_MAX};
  float ndc_min[2] = {FLT_MAX, FLT_MAX};
  float ndc_max[2] = {-FLT_MAX, -FLT_MAX};
  int verts = 0, draws = 0, vp_w = 0, vp_h = 0, path = 0;
  float iso_sx = 0.f, iso_sy = 0.f;
};

struct VboxSlot {
  int samples = 0, verts = 0, draws = 0, vp_w = 0, vp_h = 0, path = 0, empty = 0, requests = 0;
  float pre_w = 0.f, pre_h = 0.f, px_w = 0.f, px_h = 0.f, px_cx = 0.f, px_cy = 0.f;
  float iso_sx = 0.f, iso_sy = 0.f;
};

// Fins d'image sans dessin HUD tolerees avant de declarer la demande VIDE : trois, comme le retard
// maximal GOAL -> rendu que la phase de quatre images couvre.
constexpr int kVboxBudget = 3;

std::atomic<int> g_vb_pending{-1};
int g_vb_budget = 0;
VboxAcc g_vb_acc;
VboxSlot g_vb_slots[kVboxSlots];
std::mutex g_vb_mu;
int g_vb_requests = 0;
int g_vb_commits = 0;
int g_vb_empty = 0;

// LES TROIS ETAGES, SEPAREMENT, comme pour la lecture d'image : demandes -> images retenues ->
// demandes echues. Trois zeros disent « rien n'a tourne » ; un zero au deuxieme etage seul dit
// « Generic2 n'a jamais vu de dessin HUD pendant la demande », ce qui nomme la cause.
void vb_publish_diag() {
  autoport_proof::publish("hud3d_vbox_requests", (uint64_t)g_vb_requests);
  autoport_proof::publish("hud3d_vbox_commits", (uint64_t)g_vb_commits);
  autoport_proof::publish("hud3d_vbox_empty", (uint64_t)g_vb_empty);
}

// Appele a CHAQUE fin d'image par `end_of_frame` : retient l'accumulateur dans le slot arme, ou
// decompte le budget d'attente.
void vb_end_of_frame() {
  const int slot = g_vb_pending.load(std::memory_order_acquire);
  if (slot < 0) {
    return;
  }
  std::lock_guard<std::mutex> lk(g_vb_mu);
  VboxAcc& a = g_vb_acc;
  if (a.any && slot >= 0 && slot < kVboxSlots) {
    VboxSlot& s = g_vb_slots[slot];
    s.samples++;
    s.verts = a.verts;
    s.draws = a.draws;
    s.vp_w = a.vp_w;
    s.vp_h = a.vp_h;
    s.path = a.path;
    s.iso_sx = a.iso_sx;
    s.iso_sy = a.iso_sy;
    s.pre_w = a.pre_max[0] - a.pre_min[0];
    s.pre_h = a.pre_max[1] - a.pre_min[1];
    // NDC [-1, 1] -> pixels du viewport : une unite NDC vaut vp/2 pixels. Le centre y est compte
    // depuis le bord HAUT (y NDC croit vers le haut).
    s.px_w = (a.ndc_max[0] - a.ndc_min[0]) * 0.5f * (float)a.vp_w;
    s.px_h = (a.ndc_max[1] - a.ndc_min[1]) * 0.5f * (float)a.vp_h;
    s.px_cx = ((a.ndc_min[0] + a.ndc_max[0]) * 0.5f + 1.f) * 0.5f * (float)a.vp_w;
    s.px_cy = (1.f - (a.ndc_min[1] + a.ndc_max[1]) * 0.5f) * 0.5f * (float)a.vp_h;
    g_vb_commits++;
    g_vb_pending.store(-1, std::memory_order_release);
  } else if (--g_vb_budget <= 0) {
    if (slot >= 0 && slot < kVboxSlots) {
      g_vb_slots[slot].empty++;
    }
    g_vb_empty++;
    g_vb_pending.store(-1, std::memory_order_release);
  }
  a = VboxAcc{};
  vb_publish_diag();
}

int64_t vb_e3(float v) {
  return (int64_t)std::llround((double)v * 1000.0);
}

}  // namespace

void vbox_request(int slot) {
  if (slot < 0 || slot >= kVboxSlots) {
    return;
  }
  if (!g_armed) {
    // Meme geste que `request` : la premiere demande arme le module, c'est elle qui fait appeler
    // `end_of_frame` par les deux renderers (ils testent `armed()`).
    g_armed = true;
    g_prop_match = probe_key_matches() ? 1 : 0;
  }
  std::lock_guard<std::mutex> lk(g_vb_mu);
  g_vb_requests++;
  g_vb_slots[slot].requests++;
  g_vb_acc = VboxAcc{};
  g_vb_budget = kVboxBudget;
  g_vb_pending.store(slot, std::memory_order_release);
}

bool vbox_pending() {
  return g_vb_pending.load(std::memory_order_relaxed) >= 0;
}

void vbox_note_draw(const float pre_min[2],
                    const float pre_max[2],
                    const float ndc_min[2],
                    const float ndc_max[2],
                    int verts,
                    int vp_w,
                    int vp_h,
                    bool deferred,
                    float iso_sx,
                    float iso_sy) {
  if (verts <= 0 || !vbox_pending()) {
    return;
  }
  std::lock_guard<std::mutex> lk(g_vb_mu);
  VboxAcc& a = g_vb_acc;
  for (int k = 0; k < 2; k++) {
    if (pre_min[k] < a.pre_min[k]) a.pre_min[k] = pre_min[k];
    if (pre_max[k] > a.pre_max[k]) a.pre_max[k] = pre_max[k];
    if (ndc_min[k] < a.ndc_min[k]) a.ndc_min[k] = ndc_min[k];
    if (ndc_max[k] > a.ndc_max[k]) a.ndc_max[k] = ndc_max[k];
  }
  a.verts += verts;
  a.draws++;
  a.vp_w = vp_w;
  a.vp_h = vp_h;
  a.path = deferred ? 1 : 0;
  a.iso_sx = iso_sx;
  a.iso_sy = iso_sy;
  a.any = true;
}

int64_t vbox_read(int slot, int field) {
  if (slot < 0 || slot >= kVboxSlots || field < 0 || field >= kVbFieldCount) {
    return -1;
  }
  std::lock_guard<std::mutex> lk(g_vb_mu);
  const VboxSlot& s = g_vb_slots[slot];
  switch (field) {
    case kVbSamples: return s.samples;
    case kVbVerts: return s.verts;
    case kVbDraws: return s.draws;
    case kVbPreW_e3: return vb_e3(s.pre_w);
    case kVbPreH_e3: return vb_e3(s.pre_h);
    case kVbPxW_e3: return vb_e3(s.px_w);
    case kVbPxH_e3: return vb_e3(s.px_h);
    case kVbPxCx_e3: return vb_e3(s.px_cx);
    case kVbPxCy_e3: return vb_e3(s.px_cy);
    case kVbVpW: return s.vp_w;
    case kVbVpH: return s.vp_h;
    case kVbPath: return s.path;
    case kVbScaleX_e6: return (int64_t)std::llround((double)s.iso_sx * 1000000.0);
    case kVbScaleY_e6: return (int64_t)std::llround((double)s.iso_sy * 1000000.0);
    case kVbEmpty: return s.empty;
    case kVbRequests: return s.requests;
    default: return -1;
  }
}

bool armed() {
  return g_armed;
}

void request(int slot) {
  if (slot < 0 || slot >= kSlotCount) {
    return;
  }
  if (!g_armed) {
    // PREMIERE DEMANDE : c'est elle qui arme. On releve au passage ce que la lecture de propriete
    // aurait rendu, pour que la cause du silence du 17/09 soit NOMMEE par la prochaine preuve.
    g_armed = true;
    g_prop_match = probe_key_matches() ? 1 : 0;
  }
  g_requests++;
  publish_diag();
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
  g_eof_calls++;
  // essai 7 : la boite des sommets se retient a la meme fin d'image que la lecture d'image, et
  // n'a besoin ni de la FBO ni de la fenetre.
  vb_end_of_frame();
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
    s.drift_sum = 0;
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
    s.drift_sum += (uint64_t)(d_ref < 0 ? -d_ref : d_ref);
    if ((d_base > kThresh || d_base < -kThresh) && d_ref <= kStable && d_ref >= -kStable) {
      changed++;
      if (s.agree[i] < 255) {
        s.agree[i]++;
      }
    }
  }
  // REFERENCE DE STABILITE GLISSANTE. Elle etait figee sur la PREMIERE image « dessine » du slot,
  // prise au debut de la course. Mesure appareil du 17/09 22h54 : accord maximal 12 a 13 paires
  // sur 48 pour les QUATRE emplacements ET pour le CONTROLE, aucun pixel au-dela — c'est-a-dire
  // que la conjonction ne tenait plus passe le premier quart de la course, y compris au coeur
  // opaque des modeles. Une reference vieille de plusieurs minutes ne decrit plus l'image :
  // toute derive lente (exposition, adaptation, resolution) la fait sortir de +/-kStable.
  // On compare donc chaque image « dessine » a la PRECEDENTE image « dessine » du meme slot :
  // quelques secondes d'ecart au lieu de plusieurs minutes. Le bruit, lui, reste non correle.
  s.ref_lum = g_lum;
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
