#include "flip_census.h"

#ifndef __ANDROID__
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <atomic>
#include <fstream>
#include <map>
#include <mutex>
#include <regex>
#include <set>
#include <sstream>
#include <unordered_map>
#include <utility>
#include <vector>
#include "game/system/autoport_proof.h"
#include "game/system/load_gate.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "third-party/glad/include/glad/glad.h"
#endif

namespace flip_census {

#ifndef __ANDROID__
namespace {
constexpr const char* kItem = "lighting-flipped-faces-everywhere";
AUTOPORT_FEATURE_SITE(kItem);

const char* kFamNames[kFamilies] = {"tfrag", "tie", "tiewind", "shrub", "grass", "ocean", "merc"};

bool is_decor_family(Family f) {
  return f == TFRAG || f == TIE || f == TIE_WIND || f == SHRUB;
}

// Familles ou le canal y a le meme sens que x (decor rigide/statique) : GRASS et MERC en sont
// exclues, leur canal y porte autre chose.
bool is_dep_family(Family f) {
  return f == TFRAG || f == TIE || f == TIE_WIND || f == SHRUB || f == OCEAN;
}

struct Step {
  const char* continue_name;
  const char* level;
};

// Tournee en dur : 21 etapes (continuation de warp, niveau attendu).
const Step kSteps[22] = {
    {"training-start", "training"},       {"village1-hut", "village1"},
    {"beach-start", "beach"},             {"jungle-start", "jungle"},
    {"jungle-tower", "jungleb"},          {"misty-start", "misty"},
    {"firecanyon-start", "firecanyon"},   {"village2-start", "village2"},
    {"sunken-start", "sunken"},           {"sunkenb-start", "sunkenb"},
    // sunkenb-start ne montre que les shrubs de sunken : le 2e point de sunkenb montre les siens.
    {"sunkenb-helix", "sunkenb"},
    {"swamp-start", "swamp"},             {"rolling-start", "rolling"},
    {"ogre-start", "ogre"},               {"village3-start", "village3"},
    {"snow-start", "snow"},               {"maincave-start", "maincave"},
    {"darkcave-start", "darkcave"},       {"robocave-start", "robocave"},
    {"lavatube-start", "lavatube"},       {"citadel-start", "citadel"},
    {"finalboss-start", "finalboss"},
};
constexpr int kNumSteps = 22;
constexpr uint64_t kBootFrame = 900;
constexpr int kReadyStreakNeeded = 120;
constexpr uint64_t kRequestTimeout = 3600;
constexpr int kWindowFrames = 300;
// merc : une face est jugee « de face » (pas une silhouette rasante) au-dela de ce cosinus
// d'incidence (~75 degres). Les comptes a cosinus 0 (toute face avant) sont publies a cote.
constexpr float kMercSolidCos = 0.25f;

// Indices dans kSteps retenus par OG_FLIP_TOUR_LEVELS (tous par defaut). Construit une seule
// fois, au premier frame_tick actif.
std::vector<int> g_active_steps;
bool g_steps_built = false;
int g_num_active = 0;

// Vrai pendant la fenetre de mesure (State::WINDOW) : lu par kmachine.cpp pour pousser le
// stick droit a fond et balayer la camera sur 360 degres.
std::atomic<bool> g_spin{false};

enum class State { BOOT, REQUEST, WAIT_READY, WINDOW, DONE };

// Etat de la tournee (fil GL uniquement, pas de verrou requis en dehors de la demande de warp).
State g_state = State::BOOT;
int g_step = 0;
int g_attempt = 0;
uint64_t g_request_frame = 0;
int g_ready_streak = 0;
int g_window_idx = 0;  // 0..kWindowFrames-1

// Niveaux vus par les tirages, doubles-buffer (image precedente / image en cours).
std::set<std::string> g_levels_cur;
std::set<std::string> g_levels_prev;

bool g_this_frame_is_probe = false;
// L'attache se fait au PREMIER tirage sonde de l'image : c'est la que le FBO de rendu est lie.
bool g_attach_tried = false;
uint64_t g_cur_frame_idx = 0;

// Demande de teleport en attente pour le fil GOAL.
std::mutex g_warp_mutex;
bool g_warp_pending = false;
char g_warp_name[128] = {0};

struct Acc {
  uint64_t px = 0, px_no_rt = 0, flip_px = 0, defect_px = 0, dim_px = 0, latent_px = 0;
  uint64_t dep_px = 0, dep_exact_px = 0;
  uint64_t draws = 0;
};
Acc g_step_acc[kFamilies];

// diagnostic MERC-only (item lighting-flipped-faces-everywhere, quel modele/face) : libelle du
// tirage attribue via un slot pousse dans u_floor_probe. Double tampon calque sur g_pending_tex /
// g_attached ci-dessous : les libelles lus par decode_and_accumulate sont ceux de l'image
// PRECEDENTE (celle que le pending texture represente), jamais ceux de l'image en cours.
struct MercLabelAcc {
  uint64_t flip_px = 0, defect_px = 0, defect_front_px = 0;
  // Tous les pixels du modele / ceux de faces AVANT (information, plus une condition de jugement).
  // defect_solid = flip && cote vu && cosinus d'incidence >= kMercSolidCos (critere de defaut).
  // graze_px = meme cote vu, mais rasant (info, non juge).
  uint64_t px = 0, front_px = 0, defect_solid_px = 0, graze_px = 0;
};
std::unordered_map<std::string, MercLabelAcc> g_merc_step_acc;

// Slot generalise a TOUTES les familles (pas seulement merc) : cle "<niveau>|<modele>", meme
// libelle => meme slot dans l'image. Double tampon (cur/pending) analogue a l'attache de la texture sonde.
std::unordered_map<std::string, int> g_label_to_slot_cur;
std::vector<std::string> g_labels_cur;
std::vector<std::string> g_labels_pending;

// Accumulateur de TOURNEE par (niveau propre, famille) : alimente au decodage (pixels) et dans
// before_draw (draws), avec le niveau propre du tirage plutot que celui de l'ETAPE. Le jugement
// des couples se fait une seule fois, au passage en DONE, sur cette table.
std::map<std::pair<std::string, int>, Acc> g_couple_acc;
// Rayons X (voir before_draw) : couples dessines au moins une fois sans occlusion.
constexpr uint64_t kMeasuredPxMin = 500;
bool g_xray_active = false;
GLboolean g_xray_saved_depth_test = GL_TRUE;
std::set<std::string> g_xray_couples;
// merc uniquement : (niveau propre, libelle modele) -> stats, pour le tableau des modeles.
std::map<std::pair<std::string, std::string>, MercLabelAcc> g_merc_couple_label_acc;

// Totaux cumules sur toute la tournee, par famille.
Acc g_fam_totals[kFamilies];

uint64_t g_levels_visited = 0;
uint64_t g_levels_missing = 0;
std::vector<std::string> g_missing_list;
uint64_t g_couples_seen = 0;
uint64_t g_couples_measured = 0;
uint64_t g_couples_dark = 0;
uint64_t g_couples_unmeasured = 0;
uint64_t g_couples_dep = 0;
uint64_t g_couples_invisible = 0;
std::vector<std::string> g_dark_list;
std::vector<std::string> g_unmeasured_list;
std::vector<std::string> g_dep_list;
std::vector<std::string> g_invisible_list;
std::vector<std::string> g_table_rows;

uint64_t g_probe_frames = 0;
uint64_t g_refused = 0;
uint64_t g_draws_other_fbo = 0;
uint64_t g_uniform_missing[kFamilies] = {};
uint64_t g_px_badcode = 0;
uint64_t g_px_nan = 0;
uint64_t g_px_black = 0;
uint64_t g_merc_backview_px = 0;
std::map<std::string, bool> g_level_asset_ok_map;    // niveau -> au moins un sidecar applique
std::map<std::string, std::pair<bool, std::string>> g_level_asset;  // niveau -> derniere note
// ecrit par le fil du chargeur (note_level_asset), lu par le rendu (publish_summary)
std::mutex g_level_asset_mtx;

// Attache / lecture de la texture RGBA32F, calquees sur floor_probe.cpp.
GLuint g_probe_tex = 0;
int g_tex_w = 0, g_tex_h = 0;
GLint g_target_fbo = 0;
bool g_attached = false;

bool g_pending = false;
GLuint g_pending_tex = 0;
int g_pending_w = 0, g_pending_h = 0;
GLint g_pending_fbo = 0;

GLuint g_reader_fbo = 0;

GLint g_saved_draw_bufs[4] = {};
GLint g_saved_program = 0;
GLuint g_active_program = 0;
Family g_active_family = TFRAG;
bool g_draw_active = false;

std::unordered_map<GLuint, GLint> g_uniform_loc_cache;

std::string join(const std::vector<std::string>& v) {
  if (v.empty()) return "-";
  std::string out;
  for (size_t i = 0; i < v.size(); ++i) {
    if (i) out += ",";
    out += v[i];
  }
  return out;
}

std::string join_semi(const std::vector<std::string>& v) {
  std::string out;
  for (size_t i = 0; i < v.size(); ++i) {
    if (i) out += ";";
    out += v[i];
  }
  return out;
}

// Retire les commentaires // et /* */, puis tout bloc `#ifdef OG_FLIP_PROBE` /
// `#if defined(OG_FLIP_PROBE)` (en gardant la partie #else s'il y en a une), en suivant
// l'imbrication des #if/#ifdef/#ifndef vs #endif. Sert a compter les vrais retournements de
// normale du shader livre sans compter la sonde de mesure elle-meme.
std::string strip_comments_and_probe(const std::string& src) {
  // 1) commentaires.
  std::string no_comments;
  no_comments.reserve(src.size());
  for (size_t i = 0; i < src.size();) {
    if (src[i] == '/' && i + 1 < src.size() && src[i + 1] == '/') {
      while (i < src.size() && src[i] != '\n') ++i;
    } else if (src[i] == '/' && i + 1 < src.size() && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.size() && !(src[i] == '*' && src[i + 1] == '/')) ++i;
      i = (i + 1 < src.size()) ? i + 2 : src.size();
    } else {
      no_comments += src[i];
      ++i;
    }
  }

  // 2) blocs OG_FLIP_PROBE, ligne par ligne.
  std::istringstream iss(no_comments);
  std::string line;
  std::string out;
  int probe_depth = -1;  // -1 : hors sonde. >=0 : profondeur de #if a l'entree de la sonde.
  int if_depth = 0;
  bool probe_in_else = false;
  while (std::getline(iss, line)) {
    std::string trimmed = line;
    size_t a = trimmed.find_first_not_of(" \t");
    trimmed = a == std::string::npos ? "" : trimmed.substr(a);
    bool is_if = trimmed.rfind("#if", 0) == 0;
    bool is_endif = trimmed.rfind("#endif", 0) == 0;
    bool is_else = trimmed.rfind("#else", 0) == 0;
    bool is_probe_open =
        trimmed.rfind("#ifdef OG_FLIP_PROBE", 0) == 0 ||
        trimmed.rfind("#if defined(OG_FLIP_PROBE)", 0) == 0 ||
        trimmed.rfind("#if defined( OG_FLIP_PROBE )", 0) == 0;

    if (probe_depth < 0) {
      if (is_probe_open) {
        probe_depth = if_depth;
        probe_in_else = false;
      } else {
        out += line;
        out += '\n';
      }
      if (is_if) ++if_depth;
      else if (is_endif) --if_depth;
      continue;
    }

    // A l'interieur d'une sonde : suivre l'imbrication, garder la partie #else.
    if (is_if) {
      ++if_depth;
    } else if (is_endif) {
      --if_depth;
      if (if_depth == probe_depth) {
        probe_depth = -1;
        probe_in_else = false;
        continue;
      }
    } else if (is_else && if_depth == probe_depth + 1) {
      probe_in_else = true;
      continue;
    }
    if (probe_in_else) {
      out += line;
      out += '\n';
    }
  }
  return out;
}

// Compte les retournements de normale AU RUNTIME dans une source de shader deja nettoyee des
// commentaires et de la sonde OG_FLIP_PROBE. Exercee une fois au demarrage du recensement avec
// une chaine test connue (voir g_runtime_flip_selftest_ok).
uint64_t count_runtime_flips(const std::string& src) {
  static const std::regex kNegSelf(R"(\b([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)\s*=\s*-\s*\1\b)");
  static const std::regex kFaceforward(R"(\bfaceforward\s*\()");
  static const std::regex kGShadeFlip(R"(\bg_shade_flip\b)");
  static const std::regex kVtxTwin(R"(\bvtx_color_twin\b)");
  static const std::regex kFrontFacing(R"(\bgl_FrontFacing\b)");
  uint64_t n = 0;
  n += (uint64_t)std::distance(std::sregex_iterator(src.begin(), src.end(), kNegSelf),
                                std::sregex_iterator());
  n += (uint64_t)std::distance(std::sregex_iterator(src.begin(), src.end(), kFaceforward),
                                std::sregex_iterator());
  n += (uint64_t)std::distance(std::sregex_iterator(src.begin(), src.end(), kGShadeFlip),
                                std::sregex_iterator());
  n += (uint64_t)std::distance(std::sregex_iterator(src.begin(), src.end(), kVtxTwin),
                                std::sregex_iterator());
  n += (uint64_t)std::distance(std::sregex_iterator(src.begin(), src.end(), kFrontFacing),
                                std::sregex_iterator());
  return n;
}

// Une source illisible ne doit JAMAIS compter 0 : c'est le cas aveugle, pas le cas propre.
uint64_t count_runtime_flips_in_file(const std::string& rel_name, bool* out_ok = nullptr) {
  const auto path = file_util::get_jak_project_dir() / "game/graphics/opengl_renderer/shaders" / rel_name;
  std::ifstream f(path.string(), std::ios::binary);
  if (out_ok) *out_ok = f.good();
  if (!f.good()) return 1000;
  std::ostringstream ss;
  ss << f.rdbuf();
  return count_runtime_flips(strip_comments_and_probe(ss.str()));
}

// Construit la liste d'indices retenus dans kSteps, filtree par OG_FLIP_TOUR_LEVELS (liste de
// noms de niveau separes par des virgules). Vide/absente => toutes les etapes.
void build_active_steps() {
  g_steps_built = true;
  const char* e = getenv("OG_FLIP_TOUR_LEVELS");
  if (!e || !e[0]) {
    for (int i = 0; i < kNumSteps; ++i) g_active_steps.push_back(i);
    g_num_active = (int)g_active_steps.size();
    return;
  }
  std::set<std::string> wanted;
  std::string s(e);
  size_t start = 0;
  while (start <= s.size()) {
    size_t comma = s.find(',', start);
    std::string tok = s.substr(start, comma == std::string::npos ? std::string::npos : comma - start);
    if (!tok.empty()) wanted.insert(tok);
    if (comma == std::string::npos) break;
    start = comma + 1;
  }
  std::set<std::string> known;
  for (int i = 0; i < kNumSteps; ++i) known.insert(kSteps[i].level);
  for (const auto& w : wanted) {
    if (!known.count(w)) {
      printf("FLIP-CENSUS unknown level=%s\n", w.c_str());
      fflush(stdout);
    }
  }
  for (int i = 0; i < kNumSteps; ++i) {
    if (wanted.count(kSteps[i].level)) g_active_steps.push_back(i);
  }
  g_num_active = (int)g_active_steps.size();
}

// Niveau de l'ETAPE en cours (fil GL). Utilise comme repli quand un tirage ne connait pas son
// propre niveau (level_name vide).
std::string current_step_level() {
  if (g_step < 0 || g_step >= g_num_active) return std::string();
  return std::string(kSteps[g_active_steps[g_step]].level);
}

// Coupe un libelle "<niveau>|<modele>" en (niveau, modele). Niveau vide => niveau de l'etape.
void split_label(const std::string& label, std::string* level_out, std::string* model_out) {
  size_t bar = label.find('|');
  std::string lvl = bar == std::string::npos ? "" : label.substr(0, bar);
  *model_out = bar == std::string::npos ? "" : label.substr(bar + 1);
  *level_out = lvl.empty() ? current_step_level() : lvl;
}

void refused(const char* why) {
  ++g_refused;
  autoport_proof::publish("flipped_probe_refused", g_refused);
  autoport_proof::publish_text("flipped_probe_refused_why", why);
}

GLint uniform_loc(GLuint program) {
  auto it = g_uniform_loc_cache.find(program);
  if (it != g_uniform_loc_cache.end()) return it->second;
  GLint loc = glGetUniformLocation(program, "u_floor_probe");
  g_uniform_loc_cache.emplace(program, loc);
  return loc;
}

void attach_for_frame() {
  GLint fbo, samples, maxbuf;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &fbo);
  glGetIntegerv(GL_SAMPLES, &samples);
  if (!fbo || samples != 0) {
    refused("msaa_or_default_fbo");
    return;
  }
  glGetIntegerv(GL_MAX_DRAW_BUFFERS, &maxbuf);
  if (maxbuf < 5) {
    refused("mrt_unavailable");
    return;
  }
  GLint kind = GL_NONE;
  glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                       GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &kind);
  int w = 0, h = 0;
  if (kind == GL_TEXTURE) {
    GLint name = 0;
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                         GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &name);
    GLint prev_tex;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex);
    glBindTexture(GL_TEXTURE_2D, name);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &w);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &h);
    glBindTexture(GL_TEXTURE_2D, prev_tex);
  } else if (kind == GL_RENDERBUFFER) {
    GLint name = 0;
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                         GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &name);
    GLint prev_rb;
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &prev_rb);
    glBindRenderbuffer(GL_RENDERBUFFER, name);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &w);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &h);
    glBindRenderbuffer(GL_RENDERBUFFER, prev_rb);
  } else {
    refused("attachment0_missing");
    return;
  }
  if (w <= 0 || h <= 0) {
    refused("bad_size");
    return;
  }
  if (g_probe_tex == 0 || g_tex_w != w || g_tex_h != h) {
    if (g_probe_tex) glDeleteTextures(1, &g_probe_tex);
    glGenTextures(1, &g_probe_tex);
    glBindTexture(GL_TEXTURE_2D, g_probe_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, w, h, 0, GL_RGBA, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    g_tex_w = w;
    g_tex_h = h;
  }
  glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT4, GL_TEXTURE_2D, g_probe_tex, 0);
  if (glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT4, GL_TEXTURE_2D, 0, 0);
    refused("rgba32f_fbo_incomplete");
    return;
  }
  GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
  glDisable(GL_SCISSOR_TEST);
  const float zero[4] = {};
  glClearBufferfv(GL_COLOR, 4, zero);
  if (scissor) glEnable(GL_SCISSOR_TEST);
  g_target_fbo = fbo;
  g_attached = true;
}

void decode_and_accumulate(const std::vector<float>& pix,
                           int w,
                           int h,
                           const std::vector<std::string>& labels) {
  const size_t count = (size_t)w * (size_t)h;
  const std::string step_lvl = current_step_level();
  for (size_t i = 0; i < count; ++i) {
    const float* p = &pix[i * 4];
    float x = p[0], y = p[1], z = p[2], wv = p[3];
    if (wv == 0.0f) continue;
    int v = (int)std::lround(wv) - 1;
    bool flip = (v & 1) != 0;
    bool rt = (v & 2) != 0;
    int code = v >> 2;
    int fam_i = (code & 15) - 2;
    int slot = code >> 4;
    if (fam_i < 0 || fam_i >= kFamilies) {
      ++g_px_badcode;
      continue;
    }
    if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z)) {
      ++g_px_nan;
      continue;
    }
    if (z < 0.02f) {
      ++g_px_black;
      continue;
    }
    Family fam = (Family)fam_i;
    Acc& a = g_step_acc[fam];
    a.px++;
    if (is_decor_family(fam) && !rt) a.px_no_rt++;
    if (flip) a.flip_px++;
    if (fam == MERC) {
      // merc : x = ON / jumeau, y = cosinus d'incidence de la face, bit rt = face AVANT.
      if (flip && x < 0.5f) a.defect_px++;
      if (flip && x < 0.8f) a.dim_px++;
    } else {
      if (flip && x < 0.5f && y >= 0.5f) a.defect_px++;
      if (flip && x < 0.8f * y) a.dim_px++;
      if (!flip && y < 0.5f && x >= 0.5f) a.latent_px++;
    }
    if (is_dep_family(fam)) {
      if (flip && std::fabs(x - y) > 0.02f * std::max(std::max(x, y), 0.05f)) a.dep_px++;
      if (flip && x != y) a.dep_exact_px++;
    }

    // Attribution au niveau PROPRE de la geometrie (couple = (niveau propre, famille)), pas a
    // l'etape : un tirage du niveau voisin ou l'ocean global ne pollue plus son couple.
    const std::string full_label =
        (slot >= 1 && (size_t)slot <= labels.size()) ? labels[slot - 1] : "";
    std::string own_lvl, model;
    split_label(full_label, &own_lvl, &model);
    if (own_lvl.empty()) own_lvl = step_lvl;
    Acc& ca = g_couple_acc[{own_lvl, (int)fam}];
    ca.px++;
    if (is_decor_family(fam) && !rt) ca.px_no_rt++;
    if (flip) ca.flip_px++;
    if (is_dep_family(fam)) {
      if (flip && std::fabs(x - y) > 0.02f * std::max(std::max(x, y), 0.05f)) ca.dep_px++;
      if (flip && x != y) ca.dep_exact_px++;
    }
    if (fam == MERC) {
      // merc : critere de defaut = flip && cote vu (x<0.5) && de face (y >= kMercSolidCos).
      if (flip && x < 0.5f) ca.defect_px++;
      MercLabelAcc& ma = g_merc_step_acc[model.empty() ? full_label : model];
      ma.px++;
      if (rt) ma.front_px++;
      if (flip) {
        ma.flip_px++;
        if (x < 0.5f) {
          ma.defect_px++;
          if (rt) ma.defect_front_px++;
          if (y >= kMercSolidCos) {
            ma.defect_solid_px++;
          } else {
            ma.graze_px++;
          }
        }
      }
      MercLabelAcc& mc = g_merc_couple_label_acc[{own_lvl, model}];
      mc.px++;
      if (rt) mc.front_px++;
      if (flip) {
        mc.flip_px++;
        if (x < 0.5f) {
          mc.defect_px++;
          if (rt) mc.defect_front_px++;
          if (y >= kMercSolidCos) {
            mc.defect_solid_px++;
          } else {
            mc.graze_px++;
          }
        }
      }
    } else {
      if (flip && x < 0.5f && y >= 0.5f) ca.defect_px++;
    }
  }
  autoport_proof::publish("flipped_px_badcode", g_px_badcode);
  autoport_proof::publish("flipped_px_nan", g_px_nan);
  autoport_proof::publish("flipped_px_black", g_px_black);
}

void do_read_and_detach() {
  GLint old_draw, old_read;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &old_draw);
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &old_read);
  if (g_reader_fbo == 0) glGenFramebuffers(1, &g_reader_fbo);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_reader_fbo);
  glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_pending_tex, 0);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  const bool ready = glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  std::vector<float> pix;
  bool ok = false;
  if (ready) {
    GLint pack, align, row, skipx, skipy;
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pack);
    glGetIntegerv(GL_PACK_ALIGNMENT, &align);
    glGetIntegerv(GL_PACK_ROW_LENGTH, &row);
    glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipx);
    glGetIntegerv(GL_PACK_SKIP_ROWS, &skipy);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
    glPixelStorei(GL_PACK_SKIP_ROWS, 0);
    pix.resize((size_t)g_pending_w * (size_t)g_pending_h * 4);
    const GLenum prior_error = glGetError();
    if (prior_error == GL_NO_ERROR) {
      glReadPixels(0, 0, g_pending_w, g_pending_h, GL_RGBA, GL_FLOAT, pix.data());
    }
    const GLenum read_error = glGetError();
    ok = prior_error == GL_NO_ERROR && read_error == GL_NO_ERROR;
    glBindBuffer(GL_PIXEL_PACK_BUFFER, pack);
    glPixelStorei(GL_PACK_ALIGNMENT, align);
    glPixelStorei(GL_PACK_ROW_LENGTH, row);
    glPixelStorei(GL_PACK_SKIP_PIXELS, skipx);
    glPixelStorei(GL_PACK_SKIP_ROWS, skipy);
  }
  glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, old_read);
  glBindFramebuffer(GL_FRAMEBUFFER, g_pending_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT4, GL_TEXTURE_2D, 0, 0);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, old_draw);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, old_read);
  if (!ready || !ok) {
    refused("float_readback_failed_or_prior_gl_error");
    return;
  }
  ++g_probe_frames;
  autoport_proof::publish("flipped_probe_frames", g_probe_frames);
  decode_and_accumulate(pix, g_pending_w, g_pending_h, g_labels_pending);
  autoport_proof::note_hit_for(kItem, 1);
}

void reset_step_acc() {
  for (int i = 0; i < kFamilies; ++i) g_step_acc[i] = Acc{};
  g_merc_step_acc.clear();
}

void publish_step(int step) {
  // ATTENTION : ceci publie des grandeurs PAR ETAPE, a titre d'information seulement. Le
  // JUGEMENT des couples (seen/measured/dark/dep/unmeasured, flipped_table, flipped_faces_dark)
  // se fait UNE fois, a DONE, sur g_couple_acc (niveau PROPRE de la geometrie) — voir
  // judge_couples().
  const std::string lvl = kSteps[g_active_steps[step]].level;

  // merc : totaux par etape (information ; l'enroulement n'est plus un critere de jugement).
  uint64_t merc_px = 0, merc_front = 0, merc_def_front = 0, merc_def_solid = 0, merc_graze = 0;
  for (const auto& kv : g_merc_step_acc) {
    merc_px += kv.second.px;
    merc_front += kv.second.front_px;
    merc_def_front += kv.second.defect_front_px;
    merc_def_solid += kv.second.defect_solid_px;
    merc_graze += kv.second.graze_px;
  }
  const uint64_t merc_front_ppm =
      merc_px ? (uint64_t)std::lround(1e6 * (double)merc_front / (double)merc_px) : 0;

  for (int f = 0; f < kFamilies; ++f) {
    const Acc& a = g_step_acc[f];
    if (a.draws == 0 && a.px == 0) continue;
    const std::string key = lvl + "_" + kFamNames[f];
    autoport_proof::publish(("flip_px_" + key).c_str(), a.px);
    autoport_proof::publish(("flip_draws_" + key).c_str(), a.draws);
    uint64_t flipped_ppm = a.px ? (uint64_t)std::lround(1e6 * (double)a.flip_px / (double)a.px) : 0;
    autoport_proof::publish(("flip_flipped_ppm_" + key).c_str(), flipped_ppm);
    autoport_proof::publish(("flip_defect_px_" + key).c_str(), a.defect_px);
    uint64_t dim_ppm = a.px ? (uint64_t)std::lround(1e6 * (double)a.dim_px / (double)a.px) : 0;
    autoport_proof::publish(("flip_dim_ppm_" + key).c_str(), dim_ppm);
    autoport_proof::publish(("flip_latent_px_" + key).c_str(), a.latent_px);
    autoport_proof::publish(("flip_nort_px_" + key).c_str(), a.px_no_rt);
    autoport_proof::publish(("flip_dep_px_" + key).c_str(), a.dep_px);
    autoport_proof::publish(("flip_depx_px_" + key).c_str(), a.dep_exact_px);
    lg::info(
        "[flip-census] lvl={} fam={} px={} draws={} flipped_ppm={} defect={} dim_ppm={} "
        "latent={} nort={} dep={} depx={}",
        lvl, kFamNames[f], a.px, a.draws, flipped_ppm, a.defect_px, dim_ppm, a.latent_px,
        a.px_no_rt, a.dep_px, a.dep_exact_px);

    g_fam_totals[f].px += a.px;
    g_fam_totals[f].flip_px += a.flip_px;
    g_fam_totals[f].defect_px += a.defect_px;
    g_fam_totals[f].dim_px += a.dim_px;
    g_fam_totals[f].latent_px += a.latent_px;
    g_fam_totals[f].dep_px += a.dep_px;
    g_fam_totals[f].dep_exact_px += a.dep_exact_px;

    if (f == MERC) {
      autoport_proof::publish(("flip_merc_front_ppm_" + lvl).c_str(), merc_front_ppm);
      autoport_proof::publish(("flip_merc_defect_solid_px_" + lvl).c_str(), merc_def_solid);
      autoport_proof::publish(("flip_merc_graze_px_" + lvl).c_str(), merc_graze);
      autoport_proof::publish(("flip_merc_defect_back_px_" + lvl).c_str(),
                              a.defect_px > merc_def_front ? a.defect_px - merc_def_front : 0);
    }
  }

  if (!g_merc_step_acc.empty()) {
    std::vector<std::pair<std::string, MercLabelAcc>> rows(g_merc_step_acc.begin(),
                                                           g_merc_step_acc.end());
    std::sort(rows.begin(), rows.end(), [](const auto& l, const auto& r) {
      return l.second.defect_px > r.second.defect_px;
    });
    uint64_t defect_front_total = 0;
    for (const auto& kv : rows) defect_front_total += kv.second.defect_front_px;
    autoport_proof::publish(("flip_merc_defect_front_px_" + lvl).c_str(), defect_front_total);
    std::string models;
    for (size_t i = 0; i < rows.size() && i < 12; ++i) {
      if (i) models += ",";
      models += rows[i].first + ":" + std::to_string(rows[i].second.defect_px) + ":" +
               std::to_string(rows[i].second.defect_front_px) + ":" +
               std::to_string(rows[i].second.defect_solid_px) + ":" +
               std::to_string(rows[i].second.flip_px) + ":" +
               std::to_string(rows[i].second.px) + ":" +
               std::to_string(rows[i].second.front_px);
    }
    autoport_proof::publish_text(("flip_merc_models_" + lvl).c_str(), models.c_str());
    lg::info("[flip-census] lvl={} merc_models={}", lvl, models);
  }
}

// Jugement des couples (niveau propre, famille), UNE fois, sur toute la tournee. Un couple est
// PRESENT s'il a des pixels, ou des tirages (draws>0) pour toute famille SAUF OCEAN (rendu
// global, sans pixel visible = absent). MESURE si px>=500 (et la condition nort du decor).
void judge_couples() {
  g_couples_seen = 0;
  g_couples_measured = 0;
  g_couples_dark = 0;
  g_couples_unmeasured = 0;
  g_couples_dep = 0;
  g_couples_invisible = 0;
  g_dark_list.clear();
  g_unmeasured_list.clear();
  g_dep_list.clear();
  g_invisible_list.clear();
  g_table_rows.clear();

  // merc : defaut juge par (niveau, modele) desormais, agrege par niveau ici.
  std::map<std::string, uint64_t> merc_defect_by_level;
  for (const auto& kv : g_merc_couple_label_acc) {
    merc_defect_by_level[kv.first.first] += kv.second.defect_solid_px;
  }
  g_merc_backview_px = 0;
  for (const auto& kv : merc_defect_by_level) {
    g_merc_backview_px += kv.second;
  }

  for (const auto& kv : g_couple_acc) {
    const std::string& lvl = kv.first.first;
    Family f = (Family)kv.first.second;
    const Acc& a = kv.second;

    bool present = a.px > 0 || (a.draws > 0 && f != OCEAN);
    if (!present) continue;

    bool measured = a.px >= kMeasuredPxMin && (!is_decor_family(f) || a.px_no_rt * 100 <= a.px);
    // MERC : merc2.frag/merc2.vert n'ont pas de terme d'eclairage recharge (0 reference
    // `u_rt_`), donc ON == OFF et la comparaison ON/OFF ne peut jamais faire tomber un pixel
    // merc sous son OFF. judged_defect reste a 0 ; la population de vue-de-dos merc est publiee
    // a part (flipped_merc_backview_px).
    uint64_t judged_defect = (f == MERC) ? 0 : a.defect_px;

    ++g_couples_seen;
    const std::string couple = lvl + ":" + kFamNames[f];
    if (a.draws > 0 && a.px == 0 && f != OCEAN) {
      ++g_couples_invisible;
      g_invisible_list.push_back(couple);
      ++g_couples_unmeasured;
      g_unmeasured_list.push_back(couple);
      continue;
    }
    if (measured) {
      ++g_couples_measured;
      // Contrat : normale a l'envers ET sous un seuil de noir, comparaison ON/OFF. dep_px seul
      // (face vue de dos, sans retournement au runtime elle ombre forcement autrement de son
      // jumeau) n'est plus un defaut de contrat, juste une mesure a part.
      if (judged_defect > 0) {
        ++g_couples_dark;
        g_dark_list.push_back(couple);
      }
      if (a.dep_px > 0) {
        ++g_couples_dep;
        g_dep_list.push_back(couple);
      }
    } else {
      ++g_couples_unmeasured;
      g_unmeasured_list.push_back(couple);
    }
    uint64_t flipped_ppm = a.px ? (uint64_t)std::lround(1e6 * (double)a.flip_px / (double)a.px) : 0;
    g_table_rows.push_back(couple + ":" + std::to_string(a.px) + ":" +
                           std::to_string(flipped_ppm) + ":" + std::to_string(judged_defect) +
                           ":" + std::to_string(a.dep_px));
  }
}

void publish_summary() {
  const bool done_now = g_state == State::DONE;
  if (done_now) judge_couples();

  autoport_proof::publish("flipped_levels_expected", (uint64_t)g_num_active);
  autoport_proof::publish("flipped_levels_visited", g_levels_visited);
  autoport_proof::publish("flipped_levels_missing", g_levels_missing);
  autoport_proof::publish_text("flipped_levels_missing_list", join(g_missing_list).c_str());
  autoport_proof::publish("flipped_couples_seen", g_couples_seen);
  autoport_proof::publish("flipped_couples_measured", g_couples_measured);
  autoport_proof::publish("flipped_couples_dark", g_couples_dark);
  autoport_proof::publish("flipped_couples_unmeasured", g_couples_unmeasured);
  autoport_proof::publish("flipped_couples_dep", g_couples_dep);
  autoport_proof::publish("flipped_couples_invisible", g_couples_invisible);
  {
    std::vector<std::string> xr(g_xray_couples.begin(), g_xray_couples.end());
    autoport_proof::publish("flipped_couples_xray", (uint64_t)xr.size());
    autoport_proof::publish_text("flipped_couples_xray_list", join(xr).c_str());
    lg::info("[flip-census] couples passes aux rayons X ({}) : {}", xr.size(), join(xr));
  }
  autoport_proof::publish_text("flipped_couples_dark_list", join(g_dark_list).c_str());
  autoport_proof::publish_text("flipped_couples_unmeasured_list", join(g_unmeasured_list).c_str());
  autoport_proof::publish_text("flipped_couples_dep_list", join(g_dep_list).c_str());
  autoport_proof::publish_text("flipped_couples_invisible_list", join(g_invisible_list).c_str());
  autoport_proof::publish_text("flipped_table", join_semi(g_table_rows).c_str());
  for (int f = 0; f < kFamilies; ++f) {
    const std::string suf = kFamNames[f];
    autoport_proof::publish(("flipped_fam_px_" + suf).c_str(), g_fam_totals[f].px);
    uint64_t ppm = g_fam_totals[f].px
                       ? (uint64_t)std::lround(1e6 * (double)g_fam_totals[f].flip_px /
                                               (double)g_fam_totals[f].px)
                       : 0;
    autoport_proof::publish(("flipped_fam_flipped_ppm_" + suf).c_str(), ppm);
    autoport_proof::publish(("flipped_fam_defect_px_" + suf).c_str(), g_fam_totals[f].defect_px);
    autoport_proof::publish(("flipped_fam_dim_px_" + suf).c_str(), g_fam_totals[f].dim_px);
    autoport_proof::publish(("flipped_fam_latent_px_" + suf).c_str(), g_fam_totals[f].latent_px);
    autoport_proof::publish(("flipped_fam_dep_px_" + suf).c_str(), g_fam_totals[f].dep_px);
    autoport_proof::publish(("flipped_fam_depx_px_" + suf).c_str(), g_fam_totals[f].dep_exact_px);
  }
  autoport_proof::publish("flipped_probe_frames", g_probe_frames);
  const bool done = g_state == State::DONE;
  autoport_proof::publish("flipped_tour_done", done ? uint64_t(1) : uint64_t(0));

  if (done) {
    uint64_t visited_plus_missing = g_levels_visited + g_levels_missing;
    uint64_t incoherence = visited_plus_missing < (uint64_t)g_num_active
                              ? (uint64_t)g_num_active - visited_plus_missing
                              : 0;
    uint64_t value = g_couples_dark + g_couples_unmeasured + g_levels_missing + incoherence;
    autoport_proof::publish("flipped_faces_dark", value);
    uint64_t t_dark = value;

    autoport_proof::publish("flipped_merc_backview_px", g_merc_backview_px);

    // Auto-test du compteur de retournement runtime : exerce une fois, avec une chaine ou le
    // retournement HORS sonde compte 1 et celui DANS la sonde ne compte pas.
    static const std::string kSelfTestSrc =
        "vec3 N = s.N;\nif (x) { N = -N; }\n#ifdef OG_FLIP_PROBE\nN = -N;\n#endif\n";
    uint64_t selftest = count_runtime_flips(strip_comments_and_probe(kSelfTestSrc));
    autoport_proof::publish("flipped_runtime_flip_selftest", selftest);

    uint64_t flip_shade = count_runtime_flips_in_file("shade.glsl");
    uint64_t flip_merc = count_runtime_flips_in_file("merc2.frag");
    autoport_proof::publish("flipped_runtime_flip_shade", flip_shade);
    autoport_proof::publish("flipped_runtime_flip_merc", flip_merc);
    uint64_t runtime_flip_total = flip_shade + flip_merc + (selftest == 1 ? 0 : 1000);
    autoport_proof::publish("flipped_runtime_flip_total", runtime_flip_total);

    // Niveaux de la tournee active sans compagnon .meshweld applique.
    std::set<std::string> tour_levels;
    for (int idx : g_active_steps) tour_levels.insert(kSteps[idx].level);
    std::vector<std::string> without_asset;
    uint64_t asset_ok = 0;
    std::lock_guard<std::mutex> asset_lock(g_level_asset_mtx);
    for (const auto& lvl : tour_levels) {
      if (g_level_asset_ok_map.count(lvl)) {
        ++asset_ok;
      } else {
        without_asset.push_back(lvl);
      }
      auto it = g_level_asset.find(lvl);
      const std::string route = it == g_level_asset.end() || it->second.second.empty()
                                    ? "-"
                                    : it->second.second;
      autoport_proof::publish_text(("flipped_asset_route_" + lvl).c_str(), route.c_str());
    }
    autoport_proof::publish("flipped_levels_without_asset", (uint64_t)without_asset.size());
    autoport_proof::publish_text("flipped_levels_without_asset_list", join(without_asset).c_str());
    autoport_proof::publish("flipped_levels_asset_ok", asset_ok);

    // Refus de release_verify sur les compagnons .meshweld de la tournee : la meme regle que le
    // pack livre, interrogee sans la recopier (voir .autoport/lib/custom_pack_membership.sh).
    uint64_t pack_refused = (uint64_t)tour_levels.size();
    int pack_check_rc = -1;
#ifndef __ANDROID__
    {
      const auto script = file_util::get_jak_project_dir() / ".autoport/lib/custom_pack_membership.sh";
      std::string cmd = "bash '" + script.string() + "' --check 0 0";
      for (const auto& lvl : tour_levels) cmd += " 'fr3/" + lvl + ".meshweld'";
      cmd += " 2>&1";
      FILE* p = popen(cmd.c_str(), "r");
      if (p) {
        std::string out;
        char buf[256];
        size_t n;
        while ((n = fread(buf, 1, sizeof(buf), p)) > 0) out.append(buf, n);
        pack_check_rc = pclose(p);
        static const std::regex kRefused(R"(refused=(\d+))");
        std::smatch m;
        if (std::regex_search(out, m, kRefused)) {
          pack_refused = (uint64_t)std::stoull(m[1].str());
        }
      }
    }
#else
    pack_check_rc = -1;
#endif
    autoport_proof::publish("flipped_pack_refused", pack_refused);
    autoport_proof::publish("flipped_pack_check_rc", (uint64_t)pack_check_rc);

    uint64_t contract_defects =
        t_dark + runtime_flip_total + (uint64_t)without_asset.size() + pack_refused;
    autoport_proof::publish("flipped_faces_contract_defects", contract_defects);

    printf(
        "FLIP-CENSUS RESULT flipped_faces_dark=%llu couples_measured=%llu couples_seen=%llu "
        "couples_unmeasured=%llu couples_dep=%llu couples_invisible=%llu levels_visited=%llu "
        "levels_expected=%llu dark_list=%s unmeasured_list=%s contract_defects=%llu\n",
        (unsigned long long)value, (unsigned long long)g_couples_measured,
        (unsigned long long)g_couples_seen, (unsigned long long)g_couples_unmeasured,
        (unsigned long long)g_couples_dep, (unsigned long long)g_couples_invisible,
        (unsigned long long)g_levels_visited, (unsigned long long)g_num_active,
        join(g_dark_list).c_str(), join(g_unmeasured_list).c_str(),
        (unsigned long long)contract_defects);
    fflush(stdout);
  } else {
    autoport_proof::publish("flipped_faces_dark", (uint64_t)999);
    autoport_proof::publish("flipped_faces_contract_defects", (uint64_t)999);
  }
}

void request_warp(int step) {
  std::lock_guard<std::mutex> lk(g_warp_mutex);
  std::strncpy(g_warp_name, kSteps[step].continue_name, sizeof(g_warp_name) - 1);
  g_warp_name[sizeof(g_warp_name) - 1] = 0;
  g_warp_pending = true;
}

void log_transition(const char* state) {
  // En DONE, g_step == g_num_active : aucune etape a nommer (lecture hors bornes = SIGSEGV
  // dans printf, course du 25/09 03:11).
  if (g_step < 0 || g_step >= g_num_active) {
    printf("FLIP-CENSUS step=%d/%d state=%s\n", g_step, g_num_active, state);
  } else {
    printf("FLIP-CENSUS step=%d/%d cont=%s level=%s state=%s\n", g_step + 1, g_num_active,
           kSteps[g_active_steps[g_step]].continue_name, kSteps[g_active_steps[g_step]].level,
           state);
  }
  fflush(stdout);
}

}  // namespace
#endif  // !__ANDROID__

bool active() {
#ifndef __ANDROID__
  static bool checked = false;
  static bool value = false;
  if (!checked) {
    checked = true;
    const char* e = getenv("OG_FLIP_TOUR");
    value = e && std::string(e) == "1";
  }
  return value;
#else
  return false;
#endif
}

void frame_tick(uint64_t frame_idx) {
#ifndef __ANDROID__
  if (!active()) return;
  if (!g_steps_built) {
    build_active_steps();
    if (g_active_steps.empty()) {
      g_state = State::DONE;
      autoport_proof::publish("flipped_levels_expected", (uint64_t)0);
      autoport_proof::publish("flipped_faces_dark", (uint64_t)999);
      printf(
          "FLIP-CENSUS RESULT flipped_faces_dark=999 couples_measured=0 couples_seen=0 "
          "couples_unmeasured=0 couples_dep=0 levels_visited=0 levels_expected=0 dark_list=- "
          "unmeasured_list=-\n");
      fflush(stdout);
    }
  }
  g_cur_frame_idx = frame_idx;
  if (g_state == State::BOOT) {
    autoport_proof::publish("flipped_faces_dark", (uint64_t)999);
  }

  // Detacher/relire la sonde attachee a l'image precedente (sonde => WINDOW uniquement).
  if (g_pending) {
    do_read_and_detach();
    g_pending = false;
  }
  if (g_attached) {
    g_pending = true;
    g_pending_tex = g_probe_tex;
    g_pending_w = g_tex_w;
    g_pending_h = g_tex_h;
    g_pending_fbo = g_target_fbo;
    g_attached = false;
    g_labels_pending = std::move(g_labels_cur);
    g_labels_cur.clear();
  } else {
    g_labels_cur.clear();
  }
  g_label_to_slot_cur.clear();

  g_levels_prev = g_levels_cur;
  g_levels_cur.clear();
  g_this_frame_is_probe = false;
  g_attach_tried = false;

  switch (g_state) {
    case State::BOOT: {
      if (frame_idx >= kBootFrame) {
        g_attempt = 1;
        request_warp(g_active_steps[g_step]);
        g_request_frame = frame_idx;
        g_state = State::REQUEST;
        log_transition("REQUEST");
      }
      break;
    }
    case State::REQUEST: {
      g_ready_streak = 0;
      g_state = State::WAIT_READY;
      log_transition("WAIT_READY");
      break;
    }
    case State::WAIT_READY: {
      const bool ready = !load_gate::loading_screen_is_covering() &&
                         g_levels_prev.count(kSteps[g_active_steps[g_step]].level) != 0;
      if (ready) {
        ++g_ready_streak;
        if (g_ready_streak >= kReadyStreakNeeded) {
          g_window_idx = 0;
          reset_step_acc();
          g_state = State::WINDOW;
          g_spin = false;  // premiere moitie : camera posee par le point de continuation
          log_transition("WINDOW");
        }
      } else {
        g_ready_streak = 0;
      }
      if (g_state == State::WAIT_READY && frame_idx - g_request_frame >= kRequestTimeout) {
        if (g_attempt < 2) {
          ++g_attempt;
          request_warp(g_active_steps[g_step]);
          g_request_frame = frame_idx;
          g_ready_streak = 0;
          log_transition("REQUEST_RETRY");
        } else {
          ++g_levels_missing;
          g_missing_list.push_back(kSteps[g_active_steps[g_step]].level);
          log_transition("MISSING");
          ++g_step;
          if (g_step >= g_num_active) {
            g_state = State::DONE;
            g_spin = false;
            publish_summary();
            log_transition("DONE");
          } else {
            g_attempt = 1;
            request_warp(g_active_steps[g_step]);
            g_request_frame = frame_idx;
            g_state = State::REQUEST;
            log_transition("REQUEST");
          }
        }
      }
      break;
    }
    case State::WINDOW: {
      // Seconde moitie (rotation + rayons X) : une image sur DEUX est sondee, pour qu'un couple
      // minuscule a l'ecran (shrubs de jungleb : ~12 px par image) atteigne le seuil de mesure.
      g_this_frame_is_probe = g_window_idx >= kWindowFrames / 2 ? (g_window_idx % 2 == 1)
                                                                : (g_window_idx % 10 == 5);
      ++g_window_idx;
      // Seconde moitie seulement : la rotation balaie 360 degres, mais dans une salle etroite
      // (jungleb) elle encastre la camera dans les murs ; la premiere moitie garde la vue posee.
      g_spin = g_window_idx >= kWindowFrames / 2;
      if (g_window_idx >= kWindowFrames) {
        ++g_levels_visited;
        publish_step(g_step);
        g_spin = false;
        publish_summary();
        log_transition("STEP_DONE");
        ++g_step;
        if (g_step >= g_num_active) {
          g_state = State::DONE;
          publish_summary();
          log_transition("DONE");
        } else {
          g_attempt = 1;
          request_warp(g_active_steps[g_step]);
          g_request_frame = frame_idx;
          g_state = State::REQUEST;
          log_transition("REQUEST");
        }
      }
      break;
    }
    case State::DONE:
      g_spin = false;
      break;
  }

#else
  (void)frame_idx;
#endif
}

void before_draw(Family f,
                 unsigned program,
                 uint64_t frame_idx,
                 const std::string& level_name,
                 const char* label) {
#ifndef __ANDROID__
  if (!active()) return;
  (void)frame_idx;
  if (!level_name.empty()) g_levels_cur.insert(level_name);
  if (g_state != State::WINDOW) return;
  g_step_acc[f].draws++;
  {
    // Niveau propre du tirage (draws) : le sien s'il est connu, sinon celui de l'etape.
    const std::string own_lvl = level_name.empty() ? current_step_level() : level_name;
    g_couple_acc[{own_lvl, (int)f}].draws++;
  }
  if (!g_this_frame_is_probe) return;
  if (!g_attached && !g_attach_tried) {
    g_attach_tried = true;
    attach_for_frame();
  }
  if (!g_attached) return;

  // Libelle unifie "<niveau>|<modele>", partage par toutes les familles : meme libelle => meme
  // slot dans l'image.
  const std::string own_lvl = level_name.empty() ? current_step_level() : level_name;
  const std::string full_label = own_lvl + "|" + (label ? label : "");
  int slot = 0;
  {
    auto it = g_label_to_slot_cur.find(full_label);
    int idx;
    if (it != g_label_to_slot_cur.end()) {
      idx = it->second;
    } else {
      idx = (int)g_labels_cur.size();
      g_labels_cur.emplace_back(full_label);
      g_label_to_slot_cur.emplace(full_label, idx);
    }
    slot = idx + 1;
    if (slot > 4095) slot = 0;
  }

  GLint cur_fbo;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &cur_fbo);
  if (cur_fbo != g_target_fbo) {
    ++g_draws_other_fbo;
    autoport_proof::publish("flipped_draws_other_fbo", g_draws_other_fbo);
    return;
  }
  GLint loc = uniform_loc(program);
  if (loc < 0) {
    ++g_uniform_missing[f];
    autoport_proof::publish(("flipped_uniform_missing_" + std::string(kFamNames[f])).c_str(),
                            g_uniform_missing[f]);
    return;
  }
  glGetIntegerv(GL_DRAW_BUFFER0, &g_saved_draw_bufs[0]);
  glGetIntegerv(GL_DRAW_BUFFER1, &g_saved_draw_bufs[1]);
  glGetIntegerv(GL_DRAW_BUFFER2, &g_saved_draw_bufs[2]);
  glGetIntegerv(GL_DRAW_BUFFER3, &g_saved_draw_bufs[3]);
  GLenum bufs[5] = {(GLenum)g_saved_draw_bufs[0], (GLenum)g_saved_draw_bufs[1],
                    (GLenum)g_saved_draw_bufs[2], (GLenum)g_saved_draw_bufs[3],
                    GL_COLOR_ATTACHMENT4};
  glDrawBuffers(5, bufs);
  glDisablei(GL_BLEND, 4);
  glGetIntegerv(GL_CURRENT_PROGRAM, &g_saved_program);
  glUseProgram(program);
  g_active_program = program;
  g_active_family = f;
  glUniform1i(loc, 2 + (int)f + 16 * slot);
  g_draw_active = true;
  // RAYONS X : un couple (hors ocean, rendu global) encore NON MESURE en seconde moitie de fenetre est dessine,
  // sur l'image sonde seulement, sans test de profondeur. Son ombrage est calcule a l'identique
  // (meme programme, memes uniformes) ; seule l'occlusion est levee. Cas d'ecole : jungleb, dont
  // l'unique point de continuation enferme la camera dans une coque TIE — ses tfrag et shrubs
  // sont dessines a chaque image et jamais visibles. Course de recensement uniquement.
  g_xray_active = false;
  if (g_window_idx >= kWindowFrames / 2 && f != OCEAN) {
    const auto key = std::make_pair(own_lvl, (int)f);
    if (g_couple_acc[key].px < kMeasuredPxMin) {
      g_xray_saved_depth_test = glIsEnabled(GL_DEPTH_TEST);
      glDisable(GL_DEPTH_TEST);
      g_xray_active = true;
      g_xray_couples.insert(own_lvl + ":" + kFamNames[f]);
    }
  }
#else
  (void)f;
  (void)program;
  (void)frame_idx;
  (void)level_name;
  (void)label;
#endif
}

void after_draw() {
#ifndef __ANDROID__
  if (!active()) return;
  if (!g_draw_active) return;
  g_draw_active = false;
  if (g_xray_active) {
    if (g_xray_saved_depth_test) glEnable(GL_DEPTH_TEST);
    g_xray_active = false;
  }
  GLenum bufs[4] = {(GLenum)g_saved_draw_bufs[0], (GLenum)g_saved_draw_bufs[1],
                    (GLenum)g_saved_draw_bufs[2], (GLenum)g_saved_draw_bufs[3]};
  glDrawBuffers(4, bufs);
  GLint loc = uniform_loc(g_active_program);
  if (loc >= 0) glUniform1i(loc, 0);
  glUseProgram(g_saved_program);
#endif
}

bool take_warp_request(char* name, size_t cap) {
#ifndef __ANDROID__
  std::lock_guard<std::mutex> lk(g_warp_mutex);
  if (!g_warp_pending) return false;
  g_warp_pending = false;
  std::strncpy(name, g_warp_name, cap - 1);
  name[cap - 1] = 0;
  return true;
#else
  (void)name;
  (void)cap;
  return false;
#endif
}

bool spin_active() {
#ifndef __ANDROID__
  return g_spin.load();
#else
  return false;
#endif
}

void note_level_asset(const std::string& level, bool sidecar_applied, const std::string& path) {
#ifndef __ANDROID__
  std::lock_guard<std::mutex> lock(g_level_asset_mtx);
  g_level_asset[level] = {sidecar_applied, path};
  if (sidecar_applied) g_level_asset_ok_map[level] = true;
#else
  (void)level;
  (void)sidecar_applied;
  (void)path;
#endif
}

}  // namespace flip_census
