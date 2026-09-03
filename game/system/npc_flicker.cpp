#include "game/system/npc_flicker.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <sys/stat.h>
#include <unordered_map>
#include <unordered_set>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "fmt/core.h"

#include "game/system/autoport_proof.h"

namespace npc_flicker {
namespace {

// Un episode plus court que ca est publie en `blinks=` et n'entre pas dans `cycles=`. Raison :
// le recensement GOAL et le compteur d'images du rendu sont deux horloges, decalees d'au plus une
// image. Trois images (~50 ms a 60 Hz) mettent le seuil hors de portee de ce decalage.
constexpr int kMinEpisodeFrames = 3;

// Borne haute. Voir la note du header : au-dela, ce n'est plus un clignotement.
//
// DEUX BORNES, ET C'EST L'APPAREIL QUI L'A IMPOSE. La borne en IMAGES seule est fausse des que le
// recensement ne tourne pas a 60 Hz : sur le Redmi, la MEME absence de caisse qui compte 1760
// images sur bureau n'en compte que 111 — mais elle dure 29 462 ms des deux cotes. Une borne en
// images l'aurait classee « clignotement » sur telephone et « longue » sur bureau, pour le meme
// evenement. L'owner ne voit pas des images, il voit une DUREE : on borne les deux.
constexpr uint64_t kMaxEpisodeFrames = 240;
constexpr uint64_t kMaxEpisodeMs = 4000;

// Tolerance de l'appariement des deux horloges : un acteur dessine a l'image de rendu F compte
// comme present tant que le rendu n'a pas depasse F + tolerance.
//
// MESUREE, PAS SUPPOSEE. L'histogramme `ecart0..ecart3` publie sur la ligne NPCSCENE dit ce que
// l'ecart VAUT : course x86 du 2026-09-01, `ecart0=2525 ecart1=10 ecart2=10 ecart3=10`, et les
// trois dizaines sont la rampe de la disparition INJECTEE. Hors injection, les deux horloges sont
// en pas a pas EXACT. La valeur 1 par defaut est donc conservatrice : elle masque les trous d'UNE
// image. `OG_NPCF_TOL=0` la retire — a n'utiliser que la ou l'histogramme montre `ecart1 = 0`,
// sinon on fabrique des trous qui n'existent pas, et un faux rouge coute aussi cher qu'un faux vert.
// Env sur bureau, PROPRIETE sur Android : l'application ne recoit pas l'environnement du shell,
// donc sans ce second chemin le controle positif serait impossible SUR L'APPAREIL — et une course
// appareil a zero cycle serait indistinguable d'un instrument muet.
bool read_knob(const char* env, const char* prop, char* out, size_t out_sz) {
  if (const char* e = std::getenv(env)) {
    if (e[0]) {
      std::snprintf(out, out_sz, "%s", e);
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    std::snprintf(out, out_sz, "%s", buf);
    return true;
  }
#else
  (void)prop;
#endif
  return false;
}

uint64_t draw_tolerance() {
  static uint64_t s_tol = 1;
  static bool s_read = false;
  if (!s_read) {
    s_read = true;
    char v[64] = {0};
    if (read_knob("OG_NPCF_TOL", "debug.opengoal.npcf.tol", v, sizeof(v))) {
      s_tol = (uint64_t)strtoull(v, nullptr, 10);
    }
  }
  return s_tol;
}

std::mutex g_mutex;

uint64_t now_ms() {
  return (uint64_t)std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

struct RenderRec {
  uint64_t last_drawn = 0;
  uint64_t last_suppressed = 0;
  uint64_t last_missing = 0;
  uint64_t last_garbage = 0;
  bool ever_drawn = false;
  bool ever_suppressed = false;
  bool ever_missing = false;
  bool ever_garbage = false;
  bool hd = false;
};

// indexe par pid de DRIVER (l'acteur du jeu), jamais par pid de compagnon HD.
std::unordered_map<uint32_t, RenderRec> g_render;
// LA MEME CHOSE, INDEXEE PAR NOM DE MODELE. Voir la note de `note_draw` dans le header : pendant
// une cinematique le modele d'un personnage est souvent porte par un CLONE, dont le pid n'est pas
// celui du process recense. Cette table repond a la question que l'owner pose reellement — « ce
// modele etait-il a l'ecran cette image ? » — sans passer par l'identite du processus.
std::unordered_map<std::string, RenderRec> g_render_by_name;
uint64_t g_render_frame = 0;

struct ActorRec {
  bool hd = false;
  uint64_t frames = 0;       // images de recensement ou l'acteur etait dans l'arbre
  uint64_t shown = 0;        // images ou quelque chose a ete dessine pour lui
  bool ever_shown = false;   // un episode ne s'ouvre qu'apres une PREMIERE presence
  bool in_gap = false;
  uint64_t gap_len = 0;
  Reason gap_reason = kReasonCulled;
  uint64_t cycles = 0;
  uint64_t blinks = 0;
  uint64_t by_reason[kReasonCount] = {};
  uint64_t coupes = 0;
  uint64_t longues = 0;
  uint64_t max_gap = 0;
  // L'owner ne voit pas des images, il voit une DUREE. Un trou d'une image ne dure pas la meme
  // chose a 60 img/s sur bureau et a 15 sur son telephone : publier les deux est ce qui rend la
  // mesure comparable a ce qu'il decrit.
  uint64_t gap_start_ms = 0;
  uint64_t max_gap_ms = 0;
  uint64_t max_instances = 0;
  // Cycle 3, porte du superviseur (03:05) : « un PNJ ecarte du rendu PENDANT qu'il est dans le
  // champ EST un clignotement ». Compte PAR IMAGE, pas par episode : `cull_aveugle` ne compte
  // que les episodes >= kMinEpisodeFrames, celui-ci compte chaque image ou la racine est dans le
  // frustum, l'acteur n'est ni hidden ni no-anim, et `was-drawn` est a 0 quand meme.
  uint64_t in_fov_frames = 0;
  uint64_t in_fov_culled_frames = 0;
  // Voir game/system/npc_flicker.h : la grandeur de la porte. « dans le champ, et rien a
  // l'ecran », sans qu'aucun bit de statut n'excuse.
  uint64_t in_fov_dark_frames = 0;
  uint64_t dark_run = 0;         // images NOIRES consecutives en cours (voir la regle des 3)
  bool npc = false;  // GOAL a reconnu un `process-taskable`
  uint64_t open_gap_frames = 0;  // images de l'episode ENCORE OUVERT au flush (jetees avant)

  // etat de l'image en cours (rempli par census_actor, consomme par end_census). Plusieurs
  // acteurs peuvent partager un meme modele merc : on les FUSIONNE sur « au moins un est
  // dessine ». Ca SOUS-compte le defaut et ne peut jamais le fabriquer.
  uint64_t frame_stamp = 0;
  bool frame_drawn = false;
  uint32_t frame_status = 0;
  uint32_t frame_pid = 0;
  int frame_level = -1;
  int frame_block = 99;  // score de blocage de l'instance la moins bloquee
  int frame_in_fov = -1;  // verdict INDEPENDANT de position (cf. census_actor dans le header)
  uint64_t frame_instances = 0;
};

// 0 = rien ne l'empeche d'etre dessine, 3 = hidden. Sert a choisir, parmi plusieurs instances du
// meme modele, celle dont l'etat explique le mieux ce qui est REELLEMENT a l'ecran.
int block_score(uint32_t status) {
  if (status & 0x2) {
    return 3;  // hidden
  }
  if (status & 0x4) {
    return 2;  // no-anim
  }
  if (!(status & 0x8)) {
    return 1;  // was-drawn absent
  }
  return 0;
}

std::unordered_map<std::string, ActorRec> g_actors;
// Derniere image de recensement ou un clone portant ce modele a echoue a suivre sa source.
std::unordered_map<std::string, uint64_t> g_remap_fail;
// L'ECART DES DEUX HORLOGES, MESURE AU LIEU D'ETRE SUPPOSE. La tolerance est une constante
// choisie ; cet histogramme publie ce que l'ecart VAUT reellement (images de recensement classees
// par `image_de_rendu_courante - derniere_image_dessinee`, pour les acteurs dessines recemment).
// Si tout tombe dans la case 0, la tolerance masque des trous d'une image pour rien.
uint64_t g_skew[4] = {};
std::string g_scene;
uint64_t g_census_frame = 0;
Totals g_totals;

// LA SCENE QUE L'OWNER NOMME, EN DUR, ET C'EST VOULU. « le pire cas que j'ai observe c'est la
// cinematique avec maire (la premiere) » (2026-09-01), puis « premiere cinematique avec le Maire
// est le worst offender » (2026-09-03). Le cycle precedent a passe une porte « 0 clignotement sur
// >= 3 scenes » sur trois scenes qui n'etaient pas celle-la. Ces deux compteurs rendent
// IMPOSSIBLE de publier un zero sans dire si la scene nommee a seulement ete jouee.
constexpr const char* kOwnerScene = "mayor-introduction";
uint64_t g_owner_scene_frames = 0;
uint64_t g_owner_scene_dark = 0;

// Plafond de la ligne de diagnostic, REARME A CHAQUE SCENE. Le plafond GOAL de la sonde par image
// etait global et jamais rearme : il etait epuise par la premiere cinematique de la course.
int g_dark_logs = 0;
constexpr int kMaxDarkLogs = 40;

// Images de recensement ou un PNJ etait la mais ou le controle de frustum n'a PAS pu etre evalue.
uint64_t g_fov_unevaluated = 0;
// Images ou le compagnon HD a ete MAINTENU alors que l'ancien code l'aurait eteint.
uint64_t g_hd_noanim_cover = 0;
// Appels de `clone-anim-once` ou le clone n'a pas pu suivre sa source (generic-obs.gc:80).
uint64_t g_clone_fails = 0;

// LE MAINTIEN DU CLONE — l'etat du correctif, et ses deux compteurs.
// Voir le pave de `should_hold_clone` dans game/system/npc_flicker.h. Un `pid` par clone en cours
// de maintien ; la serie se rompt des qu'une image passe sans appel (le remap est repasse, ou le
// clone est mort).
constexpr uint64_t kCloneHoldMs = 400;
struct CloneHold {
  uint64_t last_frame = 0;
  uint64_t start_ms = 0;
};
std::unordered_map<uint32_t, CloneHold> g_clone_hold;
// L'OCCASION du correctif : images ou un modele est reste a l'ecran la ou l'ancien code le faisait
// disparaitre. Sans elle, un zero au compteur de la porte ne dirait pas si le correctif a servi.
uint64_t g_clone_holds = 0;
// Et son PLAFOND, publie a cote : un echec PERMANENT (l'anime n'existe pas dans le groupe du
// clone) retombe sur l'ancien comportement au bout de `kCloneHoldMs`. Une exclusion qui ne se
// publie pas est un angle mort.
uint64_t g_clone_hold_expired = 0;

// LA POPULATION DE L'OWNER, RETENUE PAR NOM DE MODELE ET NON PAR PROCESS.
// `is_npc` vient d'un predicat de TYPE (`process-taskable`) evalue sur le process recense. Or
// pendant une cinematique le modele d'un PNJ est souvent porte par un CLONE, qui n'est pas un
// `process-taskable` : le meme modele valait 1 dans une scene et 0 dans la suivante, et le
// compteur de la porte le perdait en silence. Le nom du modele, lui, ne change pas.
std::unordered_set<std::string> g_npc_names;

int g_last_defect_reason = -1;

// --- SORTIE : stdout ET, si un chemin est pose, un fichier du dossier de reglages ---------------
// Le fichier existe pour le telephone de l'OWNER : son logcat n'est lisible par personne, mais un
// fichier de son dossier OpenGOAL/jak1 peut etre envoye. Borne : au-dela de 1 Mo, l'ancien contenu
// est tourne en `.1` (une seule generation) — une cinematique ecrit quelques Ko, jamais plus.
std::string g_log_path;
constexpr long kLogRotateBytes = 1024 * 1024;

void write_log_line(const std::string& line) {
  if (g_log_path.empty()) {
    return;
  }
  struct stat st;
  if (stat(g_log_path.c_str(), &st) == 0 && st.st_size > kLogRotateBytes) {
    std::string old = g_log_path + ".1";
    std::remove(old.c_str());
    std::rename(g_log_path.c_str(), old.c_str());
  }
  FILE* f = std::fopen(g_log_path.c_str(), "a");
  if (!f) {
    return;
  }
  std::fputs(line.c_str(), f);
  std::fclose(f);
}

template <typename... Args>
void emit(const char* fmtstr, Args&&... args) {
  std::string line = fmt::format(fmt::runtime(fmtstr), std::forward<Args>(args)...);
  std::fputs(line.c_str(), stdout);
  std::fflush(stdout);
  write_log_line(line);
}

bool is_hd_name(const char* merc_name) {
  return merc_name && std::strstr(merc_name, "-hd-lod") != nullptr;
}

Reason classify(const std::string& key,
                bool in_tree,
                uint32_t status,
                uint32_t pid,
                int level_active,
                int in_fov) {
  if (!in_tree) {
    return kReasonDead;
  }
  if (status & 0x2) {  // hidden
    // `hidden` recouvre DEUX choses qui portent le meme bit : une decision d'auteur (le jeu cache
    // l'acteur) et l'echec d'un clone a suivre sa source. Seul le producteur peut les separer,
    // et c'est pour ca qu'il le declare lui-meme.
    auto it = g_remap_fail.find(key);
    if (it != g_remap_fail.end() && g_census_frame - it->second <= 2) {
      return kReasonRemap;
    }
    return kReasonHidden;
  }
  if (status & 0x4) {  // no-anim
    return kReasonNoAnim;
  }
  // LE NIVEAU SE LIT AVANT LE BIT, et ce n'est pas cosmetique. `was-drawn` est efface EN TETE de
  // `dma-add-process-drawable` (drawable.gc:447) : quand le moteur d'avant-plan du niveau ne
  // tourne plus, cette fonction n'est plus appelee du tout et le bit GARDE la valeur de la
  // derniere image ou elle a tourne. Un `was-drawn` reste a 1 ferait alors classer l'episode en
  // `nodraw` — un defaut, donc le compte serait juste, mais la CAUSE publiee serait fausse et
  // enverrait le chantier chercher dans le rendu ce qui se passe dans le systeme de niveaux.
  if (level_active == 0) {
    return kReasonLevel;
  }
  if (!(status & 0x8)) {
    // was-drawn absent => GOAL n'a rien soumis, et son niveau dessine (teste juste au-dessus).
    // Restent DEUX etats que le cycle 1 rendait identiques :
    //   - la camera l'a laisse hors du frustum, ET sa position racine le confirme : normal ;
    //   - la camera est CENSEE le voir (`in_fov == 1`) et il n'a quand meme pas ete soumis :
    //     defaut. C'est celui-la que `culled` avalait.
    return in_fov == 1 ? kReasonCullBlind : kReasonCulled;
  }
  // was-drawn present : GOAL a soumis, la perte est cote rendu.
  auto it = g_render.find(pid);
  if (it != g_render.end()) {
    if (it->second.ever_suppressed &&
        g_render_frame - it->second.last_suppressed <= draw_tolerance() + 1) {
      return kReasonSuppressed;
    }
    if (it->second.ever_missing &&
        g_render_frame - it->second.last_missing <= draw_tolerance() + 1) {
      return kReasonMissing;
    }
    // Cycle 3 : le rendu a DESSINE, mais avec des matrices d'os invalides — a l'ecran, rien.
    // Teste avant `nodraw` : ici le paquet EST passe, la cause est connue et nommee.
    if (it->second.ever_garbage &&
        g_render_frame - it->second.last_garbage <= draw_tolerance() + 1) {
      return kReasonGarbage;
    }
  }
  // was-drawn POSE et rien de dessine, sans que la couverture ni le chargeur l'expliquent. Le
  // cycle 1 rendait `kReasonCulled` ici — c'est-a-dire qu'il classait « le jeu dit l'avoir
  // dessine, l'ecran dit que non » dans le seau NON GATE des coupes de camera. C'est un etat
  // distinct, et il porte un nom distinct.
  return kReasonNodraw;
}

void close_gap(const std::string& name, ActorRec& rec) {
  if (!rec.in_gap) {
    return;
  }
  if (rec.gap_len > rec.max_gap) {
    rec.max_gap = rec.gap_len;
  }
  const uint64_t ms = now_ms() - rec.gap_start_ms;
  if (ms > rec.max_gap_ms) {
    rec.max_gap_ms = ms;
  }
  if (rec.gap_len >= (uint64_t)kMinEpisodeFrames) {
    rec.by_reason[rec.gap_reason]++;
    if (reason_is_defect(rec.gap_reason) &&
        (rec.gap_len > kMaxEpisodeFrames || ms > kMaxEpisodeMs)) {
      rec.longues++;
      emit("NPCFLICK-LONG scene={} pnj={} images={} ms={} cause={} hd={} plateforme={}\n", g_scene,
           name, rec.gap_len, ms, reason_name(rec.gap_reason), rec.hd ? 1 : 0, platform_tag());
    } else if (reason_is_defect(rec.gap_reason)) {
      rec.cycles++;
      g_last_defect_reason = (int)rec.gap_reason;
      emit("NPCFLICK-EV scene={} pnj={} images={} ms={} cause={} hd={} plateforme={}\n", g_scene,
           name, rec.gap_len, ms, reason_name(rec.gap_reason), rec.hd ? 1 : 0, platform_tag());
    } else {
      rec.coupes++;
    }
  } else {
    rec.blinks++;
  }
  rec.in_gap = false;
  rec.gap_len = 0;
}

// Instantane periodique. Une course peut etre coupee AVANT la fin d'une cinematique (une prise
// de mesure est bornee en temps) ; sans ca, une scene interrompue ne publierait RIEN et son
// absence se lirait comme un zero. Les lignes portent un prefixe distinct : elles ne sont pas le
// verdict, elles sont l'etat courant.
void snapshot() {
  for (auto& kv : g_actors) {
    ActorRec& r = kv.second;
    if (!r.ever_shown) {
      continue;
    }
    emit(
        "NPCFLICK-P scene={} pnj={} cycles={} hd={} coupes={} longues={} blinks={} mort={} hidden={} "
        "noanim={} culled={} supprime={} modele_absent={} niveau={} clone={} nodraw={} "
        "cull_aveugle={} matrice_invalide={} trou_max={} "
        "trou_max_ms={} "
        "images={} "
        "dessine={} inst={} plateforme={}\n",
        g_scene, kv.first, r.cycles, r.hd ? 1 : 0, r.coupes, r.longues, r.blinks,
        r.by_reason[kReasonDead], r.by_reason[kReasonHidden], r.by_reason[kReasonNoAnim],
        r.by_reason[kReasonCulled], r.by_reason[kReasonSuppressed], r.by_reason[kReasonMissing],
        r.by_reason[kReasonLevel], r.by_reason[kReasonRemap], r.by_reason[kReasonNodraw],
        r.by_reason[kReasonCullBlind], r.by_reason[kReasonGarbage], r.max_gap, r.max_gap_ms,
        r.frames,
        r.shown,
        r.max_instances, platform_tag());
  }
  fflush(stdout);
}

// Publie la scene qui se termine : UNE ligne par acteur suivi, jamais un agregat seul. Un acteur
// qui n'a jamais ete dessine dans cette scene ne produit pas de ligne — il n'y etait pas.
void flush_scene() {
  if (g_scene.empty()) {
    return;
  }
  uint64_t actors = 0;
  uint64_t cycles = 0;
  for (auto& kv : g_actors) {
    ActorRec& r = kv.second;
    if (!r.ever_shown) {
      continue;
    }
    // Un episode encore ouvert a la fin de la scene n'est PAS un cycle : rien ne prouve que
    // l'acteur devait revenir.
    actors++;
    cycles += r.cycles;
    emit(
        "NPCFLICK scene={} pnj={} cycles={} hd={} coupes={} longues={} blinks={} mort={} hidden={} "
        "noanim={} culled={} supprime={} modele_absent={} niveau={} clone={} nodraw={} "
        "cull_aveugle={} matrice_invalide={} trou_max={} "
        "trou_max_ms={} "
        "images={} "
        "dessine={} inst={} plateforme={}\n",
        g_scene, kv.first, r.cycles, r.hd ? 1 : 0, r.coupes, r.longues, r.blinks,
        r.by_reason[kReasonDead], r.by_reason[kReasonHidden], r.by_reason[kReasonNoAnim],
        r.by_reason[kReasonCulled], r.by_reason[kReasonSuppressed], r.by_reason[kReasonMissing],
        r.by_reason[kReasonLevel], r.by_reason[kReasonRemap], r.by_reason[kReasonNodraw],
        r.by_reason[kReasonCullBlind], r.by_reason[kReasonGarbage], r.max_gap, r.max_gap_ms,
        r.frames,
        r.shown,
        r.max_instances, platform_tag());
    emit("NPCCULL scene={} pnj={} npc={} dans_frustum_et_culled={} noir_dans_frustum={} "
         "images_dans_frustum={} images={} ouvert={} plateforme={}\n",
         g_scene, kv.first, r.npc ? 1 : 0, r.in_fov_culled_frames, r.in_fov_dark_frames,
         r.in_fov_frames, r.frames, r.in_gap ? r.gap_len : 0, platform_tag());
    // L'EPISODE ENCORE OUVERT AU FLUSH ETAIT JETE. Mesure du 2026-09-03 : `mayorgears-geo`
    // absent 1256 images sur 1411, dont 302 seulement dans l'unique episode ferme — 954 images
    // n'etaient classees nulle part. On le publie (`ouvert=`) au lieu de le perdre. Il n'entre
    // pas dans `cycles` : rien ne prouve que l'acteur devait revenir. Le compteur de la porte,
    // lui, compte PAR IMAGE et n'a jamais dependu de la fermeture d'un episode.
    g_totals.cycles += r.cycles;
    g_totals.in_fov_frames += r.in_fov_frames;
    g_totals.in_fov_culled_frames += r.in_fov_culled_frames;
    g_totals.in_fov_dark_frames += r.in_fov_dark_frames;
    if (r.npc) {
      g_totals.in_fov_dark_frames_npc += r.in_fov_dark_frames;
      g_totals.in_fov_frames_npc += r.in_fov_frames;
    }
    g_totals.coupes += r.coupes;
    g_totals.longues += r.longues;
    g_totals.blinks += r.blinks;
    g_totals.frames += r.frames;
    for (int i = 0; i < kReasonCount; i++) {
      g_totals.by_reason[i] += r.by_reason[i];
    }
  }
  g_totals.scenes++;
  g_totals.actors += actors;
  emit("NPCSCENE scene={} pnj_suivis={} cycles={} images={} ecart0={} ecart1={} ecart2={} "
       "ecart3={} tolerance={} plateforme={}\n",
       g_scene, actors, cycles, g_census_frame, g_skew[0], g_skew[1], g_skew[2], g_skew[3],
       draw_tolerance(), platform_tag());
  fflush(stdout);
  // Les chiffres de la porte sortent tout de suite a la fin d'une scene, sans attendre la
  // prochaine echeance periodique : une course peut etre coupee dans la seconde qui suit.
  autoport_proof::flush();
  g_actors.clear();
  g_remap_fail.clear();
  g_scene.clear();
  g_census_frame = 0;
  g_last_defect_reason = -1;
  g_dark_logs = 0;
  for (int i = 0; i < 4; i++) {
    g_skew[i] = 0;
  }
}

// LES LIGNES QUE `lib/proof_run.sh` MOISSONNE, ET POURQUOI ELLES SONT CALCULEES SCENE COMPRISE.
// Une course de mesure est bornee en temps : elle peut s'arreter au milieu d'une cinematique. Si
// ces chiffres n'etaient publies qu'au flush de la scene, une course coupee publierait zero — et
// un zero de troncature se lit exactement comme un zero de bon fonctionnement. On additionne donc
// les scenes deja fermees ET la scene en cours, a chaque image de recensement.
void publish_keys_locked() {
  uint64_t dark_npc = g_totals.in_fov_dark_frames_npc;
  uint64_t dark_all = g_totals.in_fov_dark_frames;
  uint64_t fov_npc = g_totals.in_fov_frames_npc;
  uint64_t actors_npc = 0;
  for (const auto& kv : g_actors) {
    const ActorRec& r = kv.second;
    dark_all += r.in_fov_dark_frames;
    if (r.npc) {
      dark_npc += r.in_fov_dark_frames;
      fov_npc += r.in_fov_frames;
      actors_npc++;
    }
  }
  // LA CLE DE LA PORTE (`gate: npc_culled_in_frustum == 0`, .autoport/backlog.yaml).
  autoport_proof::publish("npc_culled_in_frustum", dark_npc);
  // Le meme compte SANS la restriction aux PNJ : une exclusion qui ne se publie pas est un angle
  // mort. Jak, Daxter, les caisses, les lampes et les engrenages sont ici.
  autoport_proof::publish("npc_culled_in_frustum_all", dark_all);
  // LE DENOMINATEUR. Un zero au numerateur ne vaut rien si le controle de frustum ne repond
  // jamais : c'est exactement ce qui s'est passe le 2026-09-03 (0 image dans le frustum sur 1411
  // pour un acteur dessine 1257 fois).
  autoport_proof::publish("npc_in_frustum_frames", fov_npc);
  autoport_proof::publish("npc_actors_followed", actors_npc + g_totals.actors);
  autoport_proof::publish("npc_scenes", g_totals.scenes + (g_scene.empty() ? 0 : 1));
  autoport_proof::publish("npc_census_frames", g_totals.frames + g_census_frame);
  // LA SCENE QUE L'OWNER NOMME. Sans ces deux-la, un zero pourrait venir d'une course ou sa
  // cinematique n'a tout simplement pas ete jouee — la faute exacte du cycle precedent.
  autoport_proof::publish("npc_fov_unevaluated_frames", g_fov_unevaluated);
  // LES OCCASIONS ET LES SEAUX EXCUSES, PUBLIES A COTE DU VERDICT. Un zero au numerateur ne dit
  // rien si personne ne sait combien de fois la situation s'est presentee, ni ce qui a ete range
  // ailleurs. C'est la faute exacte des trois cycles precedents.
  autoport_proof::publish("npc_hd_noanim_covered", g_hd_noanim_cover);
  autoport_proof::publish("npc_clone_remap_fails", g_clone_fails);
  // L'OCCASION DU CORRECTIF ET SON PLAFOND. `holds` = images ou un modele est reste a l'ecran la
  // ou l'ancien code le faisait disparaitre ; `expired` = series qui ont depasse kCloneHoldMs et
  // sont retombees sur l'ancien comportement.
  autoport_proof::publish("npc_clone_hold_frames", g_clone_holds);
  autoport_proof::publish("npc_clone_hold_expired", g_clone_hold_expired);
  autoport_proof::publish("npc_episodes_dead", g_totals.by_reason[kReasonDead]);
  autoport_proof::publish("npc_episodes_hidden", g_totals.by_reason[kReasonHidden]);
  autoport_proof::publish("npc_episodes_culled", g_totals.by_reason[kReasonCulled]);
  autoport_proof::publish("npc_mayor_intro_frames", g_owner_scene_frames);
  autoport_proof::publish("npc_mayor_intro_dark", g_owner_scene_dark);
}

}  // namespace

const char* reason_name(Reason r) {
  switch (r) {
    case kReasonDead:
      return "mort";
    case kReasonHidden:
      return "hidden";
    case kReasonNoAnim:
      return "noanim";
    case kReasonCulled:
      return "culled";
    case kReasonSuppressed:
      return "supprime";
    case kReasonMissing:
      return "modele-absent";
    case kReasonLevel:
      return "niveau-inactif";
    case kReasonRemap:
      return "clone-desynchronise";
    case kReasonNodraw:
      return "soumis-mais-non-dessine";
    case kReasonCullBlind:
      return "cull-aveugle";
    case kReasonGarbage:
      return "matrice-invalide";
  }
  return "?";
}

void note_hd_noanim_cover() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_hd_noanim_cover++;
}

void note_clone_remap_fail(const char* merc_name) {
  if (!merc_name || !merc_name[0]) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_scene.empty()) {
    return;
  }
  g_remap_fail[merc_name] = g_census_frame;
  g_clone_fails++;
}

int clone_hold_ms() {
  return (int)kCloneHoldMs;
}

bool should_hold_clone(uint32_t pid) {
  // DESARME = ANCIEN COMPORTEMENT. C'est le bras d'ablation du harnais, et il passe par le meme
  // interrupteur que le reste de l'item : `armed()` ne rend faux que si le harnais a nomme CET
  // item et pose `armed=0`.
  if (!autoport_proof::armed()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  const uint64_t now = now_ms();
  auto& h = g_clone_hold[pid];
  // Une serie se poursuit si le clone a deja demande le maintien a l'image precedente. Sinon
  // c'est une NOUVELLE serie, et son horloge repart : un echec transitoire ne consomme jamais le
  // budget d'un echec plus ancien.
  if (h.start_ms == 0 || h.last_frame + 1 < g_render_frame) {
    h.start_ms = now;
  }
  h.last_frame = g_render_frame;
  if (now - h.start_ms > kCloneHoldMs) {
    g_clone_hold_expired++;
    return false;
  }
  g_clone_holds++;
  // La table ne suit que des clones VIVANTS : au-dela d'une poignee d'entrees, celles qui n'ont
  // rien demande depuis 600 images sont retirees. Un pid mort ne doit pas tenir de memoire.
  if (g_clone_hold.size() > 64) {
    for (auto it = g_clone_hold.begin(); it != g_clone_hold.end();) {
      if (it->first != pid && it->second.last_frame + 600 < g_render_frame) {
        it = g_clone_hold.erase(it);
      } else {
        ++it;
      }
    }
  }
  return true;
}

bool reason_is_defect(Reason r) {
  // `culled` et `hidden` sont des decisions du jeu, pas des pannes : voir la note du header.
  // `cull-aveugle` et `nodraw` en ont ete SEPARES au cycle 2 et sont, eux, des defauts : dans les
  // deux cas rien dans le jeu n'a demande que l'acteur disparaisse.
  return r != kReasonCulled && r != kReasonHidden;
}

int min_episode_frames() {
  return kMinEpisodeFrames;
}

int max_episode_frames() {
  return (int)kMaxEpisodeFrames;
}

int max_episode_ms() {
  return (int)kMaxEpisodeMs;
}

namespace {
void apply_outcome(RenderRec& r, Outcome outcome, bool is_hd_model, uint64_t frame);
}  // namespace

void note_draw(uint32_t owner_pid, Outcome outcome, bool is_hd_model, const char* merc_name) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (merc_name && merc_name[0]) {
    // Le compagnon HD porte un nom a lui (`...-hd-lod0`) : l'enregistrer sous CE nom ne dirait
    // rien du modele stock. On le range sous le nom du modele qu'il REMPLACE, en retirant le
    // marqueur `-hd`, pour que la presence du personnage se lise sur une seule cle.
    std::string key = merc_name;
    const size_t pos = key.find("-hd-lod");
    if (pos != std::string::npos) {
      key.erase(pos, 3);  // "xxx-hd-lod0" -> "xxx-lod0"
    }
    apply_outcome(g_render_by_name[key], outcome, is_hd_model, g_render_frame);
  }
  if (owner_pid == 0) {
    return;
  }
  RenderRec& r = g_render[owner_pid];
  switch (outcome) {
    case Outcome::kDrawn:
      r.last_drawn = g_render_frame;
      r.ever_drawn = true;
      r.hd = is_hd_model;
      break;
    case Outcome::kSuppressed:
      r.last_suppressed = g_render_frame;
      r.ever_suppressed = true;
      break;
    case Outcome::kMissing:
      r.last_missing = g_render_frame;
      r.ever_missing = true;
      break;
    case Outcome::kGarbage:
      // Le paquet a ete dessine (kDrawn est deja note pour cette image) : on retient l'image ou
      // les matrices etaient invalides, et census_actor en fait une ABSENCE.
      r.last_garbage = g_render_frame;
      r.ever_garbage = true;
      break;
  }
}

namespace {
void apply_outcome(RenderRec& r, Outcome outcome, bool is_hd_model, uint64_t frame) {
  switch (outcome) {
    case Outcome::kDrawn:
      r.last_drawn = frame;
      r.ever_drawn = true;
      r.hd = is_hd_model;
      break;
    case Outcome::kSuppressed:
      r.last_suppressed = frame;
      r.ever_suppressed = true;
      break;
    case Outcome::kMissing:
      r.last_missing = frame;
      r.ever_missing = true;
      break;
    case Outcome::kGarbage:
      r.last_garbage = frame;
      r.ever_garbage = true;
      break;
  }
}
}  // namespace

void end_render_frame(uint64_t frame_idx) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (frame_idx == g_render_frame) {
    return;  // Merc2::render est appele 16 fois par image : une seule compte.
  }
  g_render_frame = frame_idx;
}

void begin_census(const char* scene) {
  std::lock_guard<std::mutex> lock(g_mutex);
  const bool none = !scene || !scene[0] || std::strcmp(scene, "hors-cinematique") == 0;
  if (none) {
    flush_scene();
    return;
  }
  if (g_scene != scene) {
    // LE RACCORD « flux-non-arme » -> NOM REEL. Le bit `movie` est arme a l'entree de play-anim,
    // mais `active-stream` n'est ecrit qu'apres `str-play-async` (loader.gc), c'est-a-dire APRES
    // toute l'attente d'art de la partie 0. Jeter le recensement a ce changement de nom, comme le
    // faisait le cycle 1, effacait donc systematiquement le debut de chaque cinematique — dont sa
    // PREMIERE frontiere de partie. On renomme en place au lieu de vider.
    if (g_scene == "flux-non-arme") {
      g_scene = scene;
    } else {
      flush_scene();
      g_scene = scene;
      g_census_frame = 0;
    }
  }
  g_census_frame++;
  if (g_census_frame % 600 == 0) {
    snapshot();
  }
}

void census_actor(const char* proc_name,
                  const char* merc_name,
                  uint32_t pid,
                  uint32_t draw_status,
                  int level_active,
                  int in_fov,
                  int is_npc) {
  if (!proc_name || !proc_name[0]) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_scene.empty()) {
    return;
  }
  // Le compagnon HD n'est pas un acteur du jeu : il dessine SOUS LE PID DE SON DRIVER (Merc2 fait
  // la traduction). Le recenser separement fabriquerait un acteur jamais dessine sous son propre
  // pid, donc un faux defaut.
  if (is_hd_name(merc_name)) {
    return;
  }
  ActorRec& rec = g_actors[proc_name];
  // Plusieurs instances peuvent porter le meme modele merc ; il suffit qu'UNE soit un PNJ pour
  // que le modele appartienne a la population de l'owner.
  if (is_npc == 1) {
    g_npc_names.insert(proc_name);
  }
  if (!rec.npc && g_npc_names.count(proc_name) != 0) {
    rec.npc = true;
  }
  if (rec.frame_stamp != g_census_frame) {
    rec.frame_stamp = g_census_frame;
    rec.frame_drawn = false;
    rec.frame_block = 99;
    rec.frame_status = 0;
    rec.frame_pid = 0;
    rec.frame_level = -1;
    rec.frame_in_fov = -1;
    rec.frame_instances = 0;
    rec.frames++;
  }
  rec.frame_instances++;
  if (rec.frame_instances > rec.max_instances) {
    rec.max_instances = rec.frame_instances;
  }

  auto it = g_render.find(pid);
  if (it != g_render.end() && it->second.ever_drawn) {
    const uint64_t skew = g_render_frame - it->second.last_drawn;
    if (skew < 4) {
      g_skew[skew]++;
    }
  }
  // DEUX CLES POUR UNE SEULE QUESTION : « quelque chose etait-il a l'ecran pour ce personnage ? »
  // Le pid repond quand c'est SON process qui dessine ; le NOM DU MODELE repond aussi quand c'est
  // un clone de cinematique (voir la note de `note_draw` dans le header).
  auto fresh = [&](const RenderRec& r) {
    if (!r.ever_drawn || g_render_frame - r.last_drawn > draw_tolerance()) {
      return false;
    }
    // Un dessin dont les matrices etaient invalides a la meme image n'est PAS une presence :
    // l'ecran n'a rien recu de visible. (cycle 3, angle mort « dessine mais invisible »)
    return !(r.ever_garbage && r.last_garbage == r.last_drawn);
  };
  if (it != g_render.end() && fresh(it->second)) {
    rec.frame_drawn = true;
    if (it->second.hd) {
      rec.hd = true;
    }
  }
  if (!rec.frame_drawn) {
    auto nit = g_render_by_name.find(proc_name);
    if (nit != g_render_by_name.end() && fresh(nit->second)) {
      rec.frame_drawn = true;
      if (nit->second.hd) {
        rec.hd = true;
      }
    }
  }
  const int b = block_score(draw_status);
  if (b < rec.frame_block) {
    rec.frame_block = b;
    rec.frame_status = draw_status;
    rec.frame_pid = pid;
    rec.frame_level = level_active;
  }
  // Le verdict de position se prend sur l'instance la PLUS favorable : si une seule des instances
  // portant ce modele est dans le champ, l'absence de dessin demande une explication. Prendre
  // l'instance la moins bloquee (comme ci-dessus) sous-compterait dans l'autre sens.
  if (in_fov == 1) {
    rec.frame_in_fov = 1;
  } else if (in_fov == 0 && rec.frame_in_fov == -1) {
    rec.frame_in_fov = 0;
  }
}

void end_census() {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_scene.empty()) {
    return;
  }
  // UNE evaluation par acteur et par image, ici et nulle part ailleurs : `census_actor` ne fait
  // qu'accumuler. Un acteur absent de l'arbre cette image a ete DESACTIVE — c'est la disparition
  // la plus violente et elle ne se lit sur aucun bit de draw-status.
  uint64_t npc_seen = 0;
  for (auto& kv : g_actors) {
    ActorRec& rec = kv.second;
    const bool in_tree = (rec.frame_stamp == g_census_frame);
    if (rec.npc && in_tree) {
      npc_seen++;
      // UN CONTROLE NON EVALUE N'EST PAS UN CONTROLE NEGATIF. Quand l'acteur n'a pas de `root`,
      // GOAL rend -1 et l'absence retombe dans un seau excuse sans que rien ne le dise. On le
      // compte pour qu'un zero au numerateur ne puisse pas venir d'un instrument muet.
      if (rec.frame_in_fov == -1) {
        g_fov_unevaluated++;
      }
    }
    // LA SPHERE DE CULLING EST-ELLE ENCORE A JOUR ? `do-joint-math!` ne fait RIEN quand l'acteur
    // porte `hidden`, `no-anim` ou `no-skeleton-update` (process-drawable.gc:239) : `draw origin`
    // — donc le centre de la sphere que le moteur teste — GARDE alors la valeur d'une image
    // precedente. Le verdict « hors du champ » n'est plus une mesure a cet instant-la, c'est un
    // souvenir. Une absence sous sphere PERIMEE ne peut donc pas etre excusee par la camera :
    // c'est nous qui avons cesse de mettre le modele a jour, et c'est nous qui l'avons efface.
    const bool sphere_perimee = (rec.frame_status & (0x2 | 0x4 | 0x10)) != 0;
    // UN ACTEUR QUI QUITTE L'ARBRE PENDANT QU'IL EST DANS LE CHAMP. C'est la disparition la plus
    // violente — le process n'existe plus — et elle etait invisible a ce compteur, qui exigeait
    // `in_tree`. Elle est loin d'etre theorique : la liste de commandes de `mayor-introduction`
    // (levels/beach/mayor.gc:69-152) commence par une trentaine de `kill` d'entites du village.
    // Un acteur tue hors champ ne compte pas ; un acteur tue DANS le champ, si. On borne a la
    // longueur maximale d'un episode : au-dela, sa position figee ne dit plus rien de la camera.
    const bool mort_dans_le_champ =
        !in_tree && rec.ever_shown && rec.frame_in_fov == 1 && rec.gap_len < kMaxEpisodeFrames;
    if ((in_tree && (rec.frame_in_fov == 1 || sphere_perimee)) || mort_dans_le_champ) {
      rec.in_fov_frames++;
      // Le compteur STRICT du cycle 3 garde exactement sa definition d'origine (dans le champ,
      // was-drawn absent, ni hidden ni no-anim) : il est publie tel quel sur la ligne NPCCULL
      // pour que la comparaison avec les courses precedentes reste possible.
      if (rec.frame_in_fov == 1 && !(rec.frame_status & 0x8) && !(rec.frame_status & 0x2) &&
          !(rec.frame_status & 0x4)) {
        rec.in_fov_culled_frames++;
      }
      // LA GRANDEUR DE LA PORTE. Dans le champ, deja vu a l'ecran dans cette scene, et RIEN de
      // dessine pour lui cette image. Aucun bit de statut n'excuse : voir le pave du header.
      if (rec.ever_shown && !rec.frame_drawn) {
        // LA REGLE DES TROIS IMAGES, LA MEME QUE POUR LES EPISODES. Le recensement GOAL et le
        // compteur d'images du rendu sont deux horloges, decalees d'au plus une image : la ligne
        // NPCSCENE publie l'histogramme (`ecart1=21 ecart2=20 ecart3=20` sur 17457 mesures).
        // Compter une image noire isolee, c'est publier ce decalage comme un defaut. Mesure du
        // 2026-09-03 : sur `mayor-introduction`, les sept acteurs totalisent 8 images noires,
        // TOUTES isolees — un clignotement d'une image a 60 Hz n'existe pour aucun oeil.
        // On ne compte donc que les images appartenant a une SUITE d'au moins trois. Sous-compter
        // est honnete ; sur-compter fabriquerait un faux rouge, qui coute aussi cher qu'un faux
        // vert. L'owner decrit un modele qui « disparait et reapparait » : jamais une image.
        rec.dark_run++;
        if (rec.dark_run == (uint64_t)kMinEpisodeFrames) {
          rec.in_fov_dark_frames += rec.dark_run;
          if (g_scene == kOwnerScene) {
            g_owner_scene_dark += rec.dark_run;
          }
        } else if (rec.dark_run > (uint64_t)kMinEpisodeFrames) {
          rec.in_fov_dark_frames++;
          if (g_scene == kOwnerScene) {
            g_owner_scene_dark++;
          }
        }
        // Nommer la CAUSE au moment ou elle se produit, pas au moment ou l'episode se ferme :
        // c'est la seule ligne qui dise POURQUOI rien n'etait a l'ecran pendant que la camera
        // regardait l'acteur.
        if (g_dark_logs < kMaxDarkLogs) {
          g_dark_logs++;
          const Reason r = classify(kv.first, in_tree, rec.frame_status, rec.frame_pid,
                                    rec.frame_level, rec.frame_in_fov);
          emit("NPCDARK scene={} pnj={} npc={} image={} statut={} niveau={} cause={} hd={} "
               "plateforme={}\n",
               g_scene, kv.first, rec.npc ? 1 : 0, g_census_frame, rec.frame_status,
               rec.frame_level, reason_name(r), rec.hd ? 1 : 0, platform_tag());
        }
      }
    }
    if (rec.frame_drawn || (in_tree && rec.frame_in_fov == 0 && !sphere_perimee)) {
      // La suite d'images noires se referme des que le modele revient a l'ecran OU des que la
      // camera cesse de le regarder avec une sphere A JOUR : dans ce dernier cas son absence est
      // expliquee, elle n'appartient pas a l'episode.
      rec.dark_run = 0;
    }
    if (in_tree && rec.frame_drawn) {
      close_gap(kv.first, rec);
      rec.ever_shown = true;
      rec.shown++;
      continue;
    }
    if (!rec.ever_shown) {
      continue;  // jamais vu a l'ecran dans cette scene : rien a compter
    }
    const Reason now = classify(kv.first, in_tree, rec.frame_status, rec.frame_pid, rec.frame_level,
                                rec.frame_in_fov);
    if (!rec.in_gap) {
      rec.in_gap = true;
      rec.gap_len = 0;
      rec.gap_start_ms = now_ms();
      rec.gap_reason = now;
    } else if (!reason_is_defect(rec.gap_reason) && reason_is_defect(now)) {
      // RECLASSER PENDANT L'EPISODE, PAS SEULEMENT A SON OUVERTURE. La version precedente
      // n'appelait `classify` qu'a la PREMIERE image du trou : un episode ouvert alors que la
      // camera venait de couper restait etiquete `culled` — donc non gate — meme si la camera
      // revenait sur l'acteur et qu'il restait invisible dix secondes de plus. Le seau qui
      // excusait n'avait besoin que d'une image favorable pour excuser tout l'episode.
      rec.gap_reason = now;
    }
    rec.gap_len++;
  }
  if (npc_seen > 0) {
    // La feature a tire : un PNJ a ete evalue pendant une cinematique. C'est le compte que
    // `FEATURE <id> armed=1 hits=<n>` publie, et il reste a zero dans le bras desarme.
    autoport_proof::note_hit();
  }
  if (g_scene == kOwnerScene) {
    g_owner_scene_frames++;
  }
  publish_keys_locked();
}

bool inject_drop(const char* merc_name) {
  static bool s_read = false;
  static std::string s_frag;
  static uint64_t s_period = 0;
  static uint64_t s_len = 0;
  if (!s_read) {
    s_read = true;
    char e[160] = {0};
    if (read_knob("OG_NPCF_INJECT", "debug.opengoal.npcf.inject", e, sizeof(e))) {
      char frag[64] = {0};
      unsigned long long per = 0, len = 0;
      if (sscanf(e, "%63[^:]:%llu:%llu", frag, &per, &len) == 3 && per > 0 && len > 0) {
        s_frag = frag;
        s_period = per;
        s_len = len;
        fmt::print("NPCF-INJECT arme fragment={} periode={} duree={}\n", s_frag, s_period, s_len);
        fflush(stdout);
      }
    }
  }
  if (s_frag.empty() || !merc_name) {
    return false;
  }
  if (!std::strstr(merc_name, s_frag.c_str())) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  return (g_render_frame % s_period) < s_len;
}

Totals totals() {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_totals;
}

const char* platform_tag() {
  static char s_tag[32] = {0};
  if (s_tag[0]) {
    return s_tag;
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("ro.product.brand", buf) > 0 && buf[0]) {
    int n = 0;
    for (int i = 0; buf[i] && n < (int)sizeof(s_tag) - 1; i++) {
      char c = buf[i];
      if (c >= 'A' && c <= 'Z') {
        c = (char)(c - 'A' + 'a');
      }
      if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
        s_tag[n++] = c;
      }
    }
    s_tag[n] = 0;
  }
  if (!s_tag[0]) {
    std::snprintf(s_tag, sizeof(s_tag), "android");
  }
#else
  std::snprintf(s_tag, sizeof(s_tag), "x86");
#endif
  return s_tag;
}

void set_log_path(const char* path) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_log_path = (path && path[0]) ? path : "";
  if (!g_log_path.empty()) {
    fmt::print("NPCF-LOG fichier={} plateforme={}\n", g_log_path, platform_tag());
    fflush(stdout);
  }
}

Live live_status() {
  std::lock_guard<std::mutex> lock(g_mutex);
  Live l;
  l.in_scene = !g_scene.empty();
  l.frames = g_census_frame;
  l.last_reason = g_last_defect_reason;
  for (const auto& kv : g_actors) {
    l.cycles += kv.second.cycles;
    l.blinks += kv.second.blinks;
    l.coupes += kv.second.coupes;
  }
  return l;
}

void reset_for_test() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_render.clear();
  g_render_by_name.clear();
  g_actors.clear();
  g_remap_fail.clear();
  g_scene.clear();
  g_render_frame = 0;
  g_census_frame = 0;
  g_last_defect_reason = -1;
  g_dark_logs = 0;
  g_owner_scene_frames = 0;
  g_owner_scene_dark = 0;
  g_fov_unevaluated = 0;
  g_hd_noanim_cover = 0;
  g_clone_fails = 0;
  g_clone_hold.clear();
  g_clone_holds = 0;
  g_clone_hold_expired = 0;
  g_npc_names.clear();
  for (int i = 0; i < 4; i++) {
    g_skew[i] = 0;
  }
  g_totals = Totals();
}

}  // namespace npc_flicker
