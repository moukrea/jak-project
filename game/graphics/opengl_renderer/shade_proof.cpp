#include "game/graphics/opengl_renderer/shade_proof.h"

#include <map>
#include <set>
#include <vector>

#include "game/graphics/pipelines/opengl.h"
#include "game/system/autoport_proof.h"

namespace shade_proof {
namespace {

constexpr const char* kItemId = "lighting-unify";
AUTOPORT_FEATURE_SITE(kItemId);
constexpr const char* kBegin = "@shade-model-begin";
constexpr const char* kEnd = "@shade-model-end";

// Les portes du §2.3. Ce sont elles qui, aujourd'hui, choisissent le composite dans le texte de
// chaque hote ; apres l'item, aucune ne doit plus etre lue hors du chunk partage.
//
// `u_rt_probe_on` A QUITTE CETTE TABLE (census-false-reds, 2026-09-12). Plus aucun shader ne le
// declare : il ne survivait que dans des commentaires, et un jeton qui n'existe qu'en commentaire
// n'apporte rien a un recensement qui ne compte que le code.
// `u_pbr_mode` L'A QUITTEE A SON TOUR (lighting-legacy-purge, 2026-09-12) : la porte des MATIERES
// est partie avec la pile qu'elle commandait, et aucun texte compile par ce binaire ne la declare
// plus. Cette table doit rester IDENTIQUE a `kGateNames` de `lighting_census.cpp` — la derive
// entre les deux est comptee par `lib/census/census-false-reds.sh`.
constexpr int kGateTokenCount = 2;
const char* const kGateTokens[kGateTokenCount] = {"u_rt_light_on", "u_pbr_shadow_on"};

struct ProgInfo {
  uint64_t model_fp = 0;   // empreinte des regions marquees ; 0 = aucune region
  uint64_t model_lines = 0;  // lignes de ce modele-la
  uint64_t gate_outside = 0;
  uint64_t gate_in_comment = 0;
  bool reads_a_gate = false;
};

std::map<std::string, ProgInfo> s_progs;      // par NOM de programme
std::set<unsigned> s_shade_programs;          // objets GL qui portent le modele
std::map<std::string, unsigned> s_linked;     // nom -> objet GL

unsigned s_bound = 0;
uint64_t s_hits = 0;
uint64_t s_draws_no_model = 0;
uint64_t s_track_checks = 0;
uint64_t s_track_mismatch = 0;
uint64_t s_frames = 0;
uint64_t s_src_lines = 0;  // lignes de source fragment compilees, tous hotes marques confondus
uint64_t s_gate_in_comment = 0;  // occurrences ECARTEES parce que commentees : le temoin du filtre

uint64_t fnv1a(const char* p, size_t n, uint64_t h = 1469598103934665603ull) {
  for (size_t i = 0; i < n; i++) {
    h ^= (unsigned char)p[i];
    h *= 1099511628211ull;
  }
  return h;
}

// Une occurrence de jeton dans une ligne dont le premier caractere non blanc ouvre un
// commentaire ne compte pas : le texte de cet arbre commente abondamment les portes, et les
// compter ferait dire a `shade_gate_reads_outside` l'inverse de ce qu'elle mesure.
bool line_is_comment(const std::string& s, size_t line_begin, size_t tok_pos) {
  size_t i = line_begin;
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t')) {
    i++;
  }
  return i + 1 < s.size() && i <= tok_pos && s[i] == '/' && s[i + 1] == '/';
}

size_t line_start_of(const std::string& s, size_t pos) {
  const size_t nl = s.rfind('\n', pos);
  return nl == std::string::npos ? 0 : nl + 1;
}

}  // namespace

bool active() {
  static int s_cached = -1;
  if (s_cached < 0) {
    s_cached = autoport_proof::armed_for(kItemId) ? 1 : 0;
  }
  return s_cached == 1;
}

void note_fragment_source(const std::string& name, const std::string& src) {
  if (!active()) {
    return;
  }
  ProgInfo info;

  // ── l'empreinte du modele : TOUTES les regions marquees, concatenees dans l'ordre ──────────
  // Concatener plutot que prendre la premiere : un hote qui inclurait le chunk partage ET
  // garderait une region a lui rendrait une empreinte DIFFERENTE des autres, donc une variante
  // de plus. C'est exactement ce qu'on veut voir.
  std::vector<std::pair<size_t, size_t>> regions;  // [debut de contenu, fin de contenu)
  uint64_t h = 1469598103934665603ull;
  bool any = false;
  size_t search = 0;
  while (true) {
    const size_t b = src.find(kBegin, search);
    if (b == std::string::npos) {
      break;
    }
    const size_t body = src.find('\n', b);
    if (body == std::string::npos) {
      break;
    }
    const size_t e = src.find(kEnd, body);
    if (e == std::string::npos) {
      break;
    }
    const size_t body_end = line_start_of(src, e);
    if (body_end > body + 1) {
      h = fnv1a(src.data() + body + 1, body_end - (body + 1), h);
      for (size_t k = body + 1; k < body_end; k++) {
        if (src[k] == '\n') {
          info.model_lines++;
        }
      }
      regions.emplace_back(body + 1, body_end);
      any = true;
    }
    search = e + 1;
  }
  info.model_fp = any ? h : 0;

  // ── les portes lues HORS region ────────────────────────────────────────────────────────────
  for (const char* tok : kGateTokens) {
    const size_t tlen = std::string(tok).size();
    size_t p = 0;
    while ((p = src.find(tok, p)) != std::string::npos) {
      // jeton entier : le nom ne compte que s'il n'est pas la partie initiale d'un identifiant
      // plus long ; un jeton qui n'est qu'un PREFIXE ne doit jamais matcher.
      const char after = (p + tlen < src.size()) ? src[p + tlen] : '\0';
      const bool whole = !((after >= 'a' && after <= 'z') || (after >= 'A' && after <= 'Z') ||
                           (after >= '0' && after <= '9') || after == '_');
      if (whole) {
        // LE TEST DE COMMENTAIRE VIENT D'ABORD (census-false-reds, 2026-09-12). `reads_a_gate`
        // etait pose ICI, avant lui : un programme dont la SEULE occurrence d'une porte etait un
        // commentaire comptait dans `shade_hosts_missing` comme un hote reste sur sa propre copie.
        // Faux rouge latent, et deja vrai pour la plupart des noms herites du texte de cet arbre.
        // Une porte LUE est une porte lue par le compilateur GLSL, pas par un lecteur humain.
        const bool commented = line_is_comment(src, line_start_of(src, p), p);
        if (commented) {
          info.gate_in_comment++;
        } else {
          info.reads_a_gate = true;
          bool inside = false;
          for (const auto& r : regions) {
            if (p >= r.first && p < r.second) {
              inside = true;
              break;
            }
          }
          if (!inside) {
            info.gate_outside++;
          }
        }
      }
      p += tlen;
    }
  }

  s_progs[name] = info;

  if (any) {
    uint64_t lines = 0;
    for (char c : src) {
      if (c == '\n') {
        lines++;
      }
    }
    s_src_lines += lines;
  }
}

void note_program_linked(const std::string& name, unsigned gl_program) {
  if (!active() || gl_program == 0) {
    return;
  }
  s_linked[name] = gl_program;
  auto it = s_progs.find(name);
  if (it != s_progs.end() && it->second.model_fp != 0) {
    s_shade_programs.insert(gl_program);
  }
}

void note_program_bound(unsigned gl_program) {
  s_bound = gl_program;
}

void note_world_draw() {
  if (!active()) {
    return;
  }
  // AU SITE DU GESTE. `hits` compte les draws qui sont REELLEMENT partis avec un programme
  // porteur du modele, pas les draws dont on suppose qu'ils y passeront. Un hote oublie fait
  // donc monter `shade_draws_no_model`, pas `hits`.
  if (s_shade_programs.count(s_bound)) {
    s_hits++;
    autoport_proof::note_hit_for(kItemId);
  } else {
    s_draws_no_model++;
  }
}

void frame_end() {
  if (!active()) {
    return;
  }
  s_frames++;

  // LE SUIVI DE PROGRAMME EST UNE OMBRE : ON LE CONFRONTE. `note_program_bound` est pose dans
  // `Shader::activate()`, mais rien n'interdit a un autre site d'appeler `glUseProgram`
  // directement. Une relecture par image, synchrone mais unique, dit si l'ombre ment.
  {
    int prog = 0;
    glGetIntegerv(GL_CURRENT_PROGRAM, &prog);
    s_track_checks++;
    if ((unsigned)prog != s_bound) {
      s_track_mismatch++;
    }
  }

  // `shade_model_lines` compte les lignes des modeles DISTINCTS, une fois chacun. C'est la
  // grandeur qui dit « un modele au lieu de quatre » ; `shade_world_frag_lines` somme le texte
  // EXPANSE de chaque programme et monte forcement quand un chunk partage est inline cinq fois —
  // les deux ne mesurent pas la meme chose et se lisent ensemble.
  std::set<uint64_t> fps;
  uint64_t model_lines = 0;
  uint64_t hosts = 0, missing = 0, outside = 0, commented = 0;
  for (const auto& [name, info] : s_progs) {
    if (info.model_fp != 0) {
      if (fps.insert(info.model_fp).second) {
        model_lines += info.model_lines;
      }
      hosts++;
    } else if (info.reads_a_gate) {
      // Un programme qui lit une porte d'ombrage sans porter le modele partage : c'est
      // exactement un shader monde reste sur sa propre copie.
      missing++;
    }
    outside += info.gate_outside;
    commented += info.gate_in_comment;
  }
  s_gate_in_comment = commented;

  autoport_proof::publish("shade_variants", fps.size());
  autoport_proof::publish("shade_model_lines", model_lines);
  autoport_proof::publish("shade_hosts", hosts);
  autoport_proof::publish("shade_hosts_missing", missing);
  autoport_proof::publish("shade_gate_reads_outside", outside);
  // LES DEUX DENOMINATEURS DU FILTRE. `shade_gate_reads_in_comment` est le temoin GRATUIT que le
  // test de commentaire a bien mordu quelque part : a zero, `shade_gate_reads_outside` serait le
  // meme chiffre avec ou sans filtre, et le filtre ne prouverait rien. `shade_gate_tokens` dit
  // sur combien de noms tout cela a ete cherche.
  autoport_proof::publish("shade_gate_reads_in_comment", s_gate_in_comment);
  autoport_proof::publish("shade_gate_tokens", (uint64_t)kGateTokenCount);
  autoport_proof::publish("shade_programs_seen", s_progs.size());
  autoport_proof::publish("shade_draws_no_model", s_draws_no_model);
  autoport_proof::publish("shade_world_frag_lines", s_src_lines);
  autoport_proof::publish("shade_prog_track_checks", s_track_checks);
  autoport_proof::publish("shade_prog_track_mismatch", s_track_mismatch);
  autoport_proof::publish("shade_frames", s_frames);
  autoport_proof::publish("shade_hits", s_hits);
}

}  // namespace shade_proof
