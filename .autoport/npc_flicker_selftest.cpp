// Gcutscene-npc-flicker — CONTROLE DE L'INSTRUMENT, SANS APPAREIL ET SANS COURSE.
//
// POURQUOI CE FICHIER EXISTE, ET C'EST LA LECON DE LA REGRESSION.
// La garde laissee par Grecharged-hd-models4/5 etait la ligne `[hd-flicker] ... blackouts=0`.
// Son compteur `s_hd_blackout_events` est declare et imprime, et AUCUN chemin de code ne
// l'incremente depuis 45b7140ca7. Trois jambes de preuve exigeaient `blackouts=0` : une clause
// que rien ne pouvait violer. Le defaut est revenu sans qu'aucune porte ne s'ouvre.
//
// Un compteur ne vaut donc que s'il existe une entree qui le fait MONTER, et cette entree doit
// etre executee par la garde elle-meme. C'est ce que fait ce fichier : chaque propriete est
// prouvee AVEC son controle positif (le compteur monte) ET son controle negatif (il ne monte
// pas). Un test qui ne saurait qu'echouer sur du bruit ne prouve rien.

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include "game/system/npc_flicker.h"

static int g_fail = 0;

static void check(bool ok, const std::string& what, const std::string& detail) {
  printf("%-6s %-52s %s\n", ok ? "[ok]" : "[FAIL]", what.c_str(), detail.c_str());
  if (!ok) {
    g_fail++;
  }
}

namespace {

// draw-status de jak1 (engine/data/art-h.gc:184)
[[maybe_unused]] constexpr uint32_t kNeedsClip = 1 << 0;
constexpr uint32_t kHidden = 1 << 1;
constexpr uint32_t kNoAnim = 1 << 2;
constexpr uint32_t kWasDrawn = 1 << 3;

uint64_t g_frame = 0;

struct Actor {
  const char* name;
  uint32_t pid;
  uint32_t status;
  bool in_tree;
  bool drawn;
  npc_flicker::Outcome outcome = npc_flicker::Outcome::kDrawn;
  int level_active = 1;
  // Verdict INDEPENDANT de position (cf. npc_flicker.h) : 1 = la racine de l'acteur est dans le
  // frustum, 0 = dehors, -1 = non evalue. Par defaut -1, pour que les cas anterieurs a
  // Gcutscene-npc-flicker-2 rendent EXACTEMENT ce qu'ils rendaient avant.
  int in_fov = -1;
  // 1 = GOAL a reconnu un `process-taskable` (la population que l'owner nomme). Par defaut 1 :
  // les cas de ce fichier decrivent tous des PNJ de cinematique, et un defaut a 0 rendrait le
  // compteur de la porte MUET sur tous les cas anterieurs sans qu'aucun d'eux ne change.
  int is_npc = 1;
};

// Une image complete, dans l'ORDRE REEL du moteur : le rendu avance et publie ses issues, puis
// GOAL recense (main.gc appelle npc-census-tick depuis post-sync-draw, apres la passe de dessin).
void run_frame(const char* scene, const std::vector<Actor>& actors) {
  g_frame++;
  npc_flicker::end_render_frame(g_frame);
  for (const auto& a : actors) {
    if (a.drawn) {
      npc_flicker::note_draw(a.pid, npc_flicker::Outcome::kDrawn, false, a.name);
      // Cycle 3 : un paquet DESSINE peut porter des matrices invalides — Merc2 note alors les
      // deux issues pour la meme image, exactement dans cet ordre (kDrawn a la lecture du
      // modele, kGarbage a la lecture des matrices).
      if (a.outcome == npc_flicker::Outcome::kGarbage) {
        npc_flicker::note_draw(a.pid, npc_flicker::Outcome::kGarbage, false, a.name);
      }
    } else if (a.outcome != npc_flicker::Outcome::kDrawn) {
      npc_flicker::note_draw(a.pid, a.outcome, false, a.name);
    }
  }
  npc_flicker::begin_census(scene);
  for (const auto& a : actors) {
    if (a.in_tree) {
      npc_flicker::census_actor(a.name, a.name, a.pid, a.status, a.level_active, a.in_fov,
                                a.is_npc);
    }
  }
  npc_flicker::end_census();
}

Actor shown(const char* n, uint32_t pid) {
  return Actor{n, pid, kWasDrawn, true, true};
}

}  // namespace

int main() {
  const int minep = npc_flicker::min_episode_frames();
  printf("npc_flicker selftest — min_episode_frames=%d\n\n", minep);

  // ---------------------------------------------------------------------------------------------
  // 1. CONTROLE NEGATIF — un acteur dessine sans interruption ne produit AUCUN cycle.
  //    Si celui-ci echoue, tout compte publie plus loin est du bruit.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 60; i++) {
    run_frame("scene-A", {shown("keira-lod0", 100)});
  }
  npc_flicker::begin_census("hors-cinematique");  // ferme la scene
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 0 && t.blinks == 0,
          "acteur dessine 60 images : aucun cycle",
          "cycles=" + std::to_string(t.cycles) + " blinks=" + std::to_string(t.blinks));
    check(t.actors == 1 && t.scenes == 1, "la scene et l'acteur sont bien publies",
          "scenes=" + std::to_string(t.scenes) + " pnj=" + std::to_string(t.actors));
  }

  // ---------------------------------------------------------------------------------------------
  // 2. CONTROLE POSITIF — LE BRAS QUI MANQUAIT A LA GARDE PRECEDENTE.
  //    L'acteur reste dans l'arbre, porte `no-anim`, et plus rien ne le dessine pendant 8 images.
  //    Le compteur DOIT monter, et la cause DOIT etre `noanim`.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-B", {shown("keira-lod0", 100)});
  }
  for (int i = 0; i < 8; i++) {
    run_frame("scene-B", {Actor{"keira-lod0", 100, kNoAnim, true, false}});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-B", {shown("keira-lod0", 100)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 1, "8 images sans dessin, acteur vivant : UN cycle compte",
          "cycles=" + std::to_string(t.cycles));
    check(t.by_reason[npc_flicker::kReasonNoAnim] == 1, "cause publiee = noanim",
          "noanim=" + std::to_string(t.by_reason[npc_flicker::kReasonNoAnim]));
  }

  // ---------------------------------------------------------------------------------------------
  // 3. MORT DE PROCESSUS — l'acteur quitte l'arbre puis revient. Aucun bit de draw-status ne le
  //    dit : c'est le seul chemin qui detecte une naissance/mort d'acteur.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-C", {shown("sage-lod0", 200)});
  }
  for (int i = 0; i < 6; i++) {
    run_frame("scene-C", {});  // arbre vide
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-C", {shown("sage-lod0", 200)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 1 && t.by_reason[npc_flicker::kReasonDead] == 1,
          "acteur sorti de l'arbre puis revenu : cycle cause=mort",
          "cycles=" + std::to_string(t.cycles) +
              " mort=" + std::to_string(t.by_reason[npc_flicker::kReasonDead]));
  }

  // ---------------------------------------------------------------------------------------------
  // 4. PERTE COTE RENDU — GOAL a soumis (was-drawn pose) mais le rendu supprime le paquet.
  //    C'est exactement ce que la couverture HD fait, et c'est la classe que l'ancien detecteur
  //    pretendait couvrir avec un compteur mort.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-D", {shown("assistant-lod0", 300)});
  }
  for (int i = 0; i < 6; i++) {
    Actor a{"assistant-lod0", 300, kWasDrawn, true, false};
    a.outcome = npc_flicker::Outcome::kSuppressed;
    run_frame("scene-D", {a});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-D", {shown("assistant-lod0", 300)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 1 && t.by_reason[npc_flicker::kReasonSuppressed] == 1,
          "paquet supprime par la couverture : cycle cause=supprime",
          "supprime=" + std::to_string(t.by_reason[npc_flicker::kReasonSuppressed]));
  }

  // ---------------------------------------------------------------------------------------------
  // 5. MODELE NON RESIDENT — jusqu'ici compte dans `num_missing_models`, que rien ne publiait.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-E", {shown("mayor-lod0", 400)});
  }
  for (int i = 0; i < 6; i++) {
    Actor a{"mayor-lod0", 400, kWasDrawn, true, false};
    a.outcome = npc_flicker::Outcome::kMissing;
    run_frame("scene-E", {a});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-E", {shown("mayor-lod0", 400)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 1 && t.by_reason[npc_flicker::kReasonMissing] == 1,
          "modele absent du chargeur : cycle cause=modele-absent",
          "modele_absent=" + std::to_string(t.by_reason[npc_flicker::kReasonMissing]));
  }

  // ---------------------------------------------------------------------------------------------
  // 6. UN PNJ QUI N'EST JAMAIS APPARU NE PRODUIT AUCUN CYCLE.
  //    Sans cette regle, tout acteur hors champ d'une scene compterait comme un defaut : c'est le
  //    faux rouge le plus facile a fabriquer sur cette mesure.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 40; i++) {
    run_frame("scene-F", {Actor{"farmer-lod0", 500, 0, true, false}});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 0 && t.actors == 0, "jamais dessine : ni cycle ni ligne",
          "cycles=" + std::to_string(t.cycles) + " pnj=" + std::to_string(t.actors));
  }

  // ---------------------------------------------------------------------------------------------
  // 7. UN EPISODE ENCORE OUVERT A LA FIN DE LA SCENE N'EST PAS UN CYCLE.
  //    Rien ne prouve que l'acteur devait revenir : compter la fin d'une scene comme une
  //    disparition ferait monter le compteur sur toutes les cinematiques du jeu.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-G", {shown("oracle-lod0", 600)});
  }
  for (int i = 0; i < 20; i++) {
    run_frame("scene-G", {Actor{"oracle-lod0", 600, kNoAnim, true, false}});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 0, "disparition non refermee : aucun cycle",
          "cycles=" + std::to_string(t.cycles));
  }

  // ---------------------------------------------------------------------------------------------
  // 8. SEUIL — un trou trop court est publie en `blinks` et n'entre pas dans `cycles`.
  //    L'ecart des deux horloges (recensement GOAL / images rendues) vaut au plus une image ;
  //    sous-compter est honnete, sur-compter fabriquerait un faux rouge.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-H", {shown("keira-lod0", 700)});
  }
  run_frame("scene-H", {Actor{"keira-lod0", 700, kNoAnim, true, false}});
  run_frame("scene-H", {Actor{"keira-lod0", 700, kNoAnim, true, false}});
  for (int i = 0; i < 10; i++) {
    run_frame("scene-H", {shown("keira-lod0", 700)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 0 && t.blinks == 1, "trou de 2 images : blink publie, pas de cycle",
          "cycles=" + std::to_string(t.cycles) + " blinks=" + std::to_string(t.blinks));
  }

  // ---------------------------------------------------------------------------------------------
  // 9. DEUX ACTEURS PARTAGEANT UN MODELE — on fusionne sur « au moins un est dessine ». Cette
  //    regle SOUS-compte ; le test verifie qu'elle ne peut pas FABRIQUER un cycle.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 30; i++) {
    // deux instances de `harvester-lod0` : la seconde n'est jamais dessinee.
    run_frame("scene-I", {shown("harvester-lod0", 800),
                          Actor{"harvester-lod0", 801, kWasDrawn, true, false}});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 0, "instances fusionnees : aucun cycle fabrique",
          "cycles=" + std::to_string(t.cycles));
  }

  // ---------------------------------------------------------------------------------------------
  // 10. CULLING DE CAMERA — CONTROLE NEGATIF SUR DONNEE REELLE. Sur `sage-intro-sequence-a`
  //     (course x86 du 2026-09-01), les SEULS episodes observes sont de cette classe et durent
  //     jusqu'a 1686 images : une cinematique COUPE d'un cadrage a l'autre. Les compter comme un
  //     defaut mettrait toutes les cinematiques du jeu au rouge. Ils sont publies en `coupes`.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-J", {shown("sagesail-lod0", 900)});
  }
  for (int i = 0; i < 300; i++) {
    run_frame("scene-J", {Actor{"sagesail-lod0", 900, 0, true, false}});  // was-drawn a 0, niveau actif
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-J", {shown("sagesail-lod0", 900)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 0 && t.coupes == 1,
          "hors frustum 300 images, niveau actif : coupe, pas un cycle",
          "cycles=" + std::to_string(t.cycles) + " coupes=" + std::to_string(t.coupes));
  }

  // ---------------------------------------------------------------------------------------------
  // 11. NIVEAU DESACTIVE — MEME ETAT COTE ACTEUR QUE LE CULLING, VERDICT OPPOSE.
  //     `display-level <lev> #f` retire le bsp du moteur de fond et tue les acteurs du niveau
  //     (level.gc + entity.gc). L'acteur ne porte AUCUN bit qui le dise : seul le statut du
  //     niveau separe les deux, et c'est pour ca qu'il est publie.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-K", {shown("harvester-lod0", 950)});
  }
  for (int i = 0; i < 20; i++) {
    Actor a{"harvester-lod0", 950, 0, true, false};
    a.level_active = 0;
    run_frame("scene-K", {a});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-K", {shown("harvester-lod0", 950)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 1 && t.by_reason[npc_flicker::kReasonLevel] == 1,
          "niveau desactive sous l'acteur : cycle cause=niveau-inactif",
          "cycles=" + std::to_string(t.cycles) +
              " niveau=" + std::to_string(t.by_reason[npc_flicker::kReasonLevel]));
  }

  // ---------------------------------------------------------------------------------------------
  // 12. `hidden` VOLONTAIRE — publie, jamais gate.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-L", {shown("evilsis-lod0", 970)});
  }
  for (int i = 0; i < 20; i++) {
    run_frame("scene-L", {Actor{"evilsis-lod0", 970, kHidden, true, false}});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-L", {shown("evilsis-lod0", 970)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 0 && t.coupes == 1 && t.by_reason[npc_flicker::kReasonHidden] == 1,
          "masque volontairement : coupe, pas un cycle",
          "cycles=" + std::to_string(t.cycles) + " coupes=" + std::to_string(t.coupes));
  }

  // ---------------------------------------------------------------------------------------------
  // 13. BORNE HAUTE — une absence de cause DEFECTUEUSE mais tres longue n'est pas un
  //     clignotement. Mesure a l'appui : sur `intro-start`, la seule absence de cause `mort`
  //     relevee durait 1760 images (29 s) et venait d'une caisse qui streame. Publiee en
  //     `longues`, jamais dans `cycles`.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-M", {shown("crate-darkeco-lod0", 990)});
  }
  for (int i = 0; i < npc_flicker::max_episode_frames() + 20; i++) {
    run_frame("scene-M", {});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-M", {shown("crate-darkeco-lod0", 990)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 0 && t.longues == 1, "absence tres longue : `longues`, pas `cycles`",
          "cycles=" + std::to_string(t.cycles) + " longues=" + std::to_string(t.longues));
  }

  // ---------------------------------------------------------------------------------------------
  // 14. CLONE DESYNCHRONISE — MEME BIT `hidden`, VERDICT OPPOSE. Un figurant de cinematique est un
  //     clone : quand `joint-control-remap!` echoue (slot d'art streame delie), `clone-anim-once`
  //     se pose `hidden` lui-meme. Le producteur le DECLARE, sinon ce masquage et un masquage
  //     voulu par le jeu sont indistinguables — et celui-ci compte, l'autre pas.
  // ---------------------------------------------------------------------------------------------
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-N", {shown("sidekick-human-lod0", 1010)});
  }
  for (int i = 0; i < 8; i++) {
    npc_flicker::note_clone_remap_fail("sidekick-human-lod0");
    run_frame("scene-N", {Actor{"sidekick-human-lod0", 1010, kHidden, true, false}});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-N", {shown("sidekick-human-lod0", 1010)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 1 && t.by_reason[npc_flicker::kReasonRemap] == 1,
          "clone qui ne suit plus sa source : cycle cause=clone-desynchronise",
          "cycles=" + std::to_string(t.cycles) +
              " clone=" + std::to_string(t.by_reason[npc_flicker::kReasonRemap]));
  }

  // ---------------------------------------------------------------------------------------------
  // Gcutscene-npc-flicker-2 — LES DEUX SEAUX QUE `culled` AVALAIT, ET LE RACCORD DE DEBUT DE SCENE.
  //
  // Au cycle 1, `culled` recevait tout ce que classify() ne savait pas nommer, et il n'etait
  // jamais gate : sur les sept courses archivees de .autoport/reports/Gcutscene-npc-flicker/ il
  // etait le SEUL seau non vide (37 a 106 episodes par course) pendant que `cycles` valait 0. Un
  // compteur neuf sans controle qui le fasse MONTER est exactement la faute que cette garde
  // existe pour interdire : les deux nouveaux seaux ont donc ici leur controle positif ET leur
  // controle negatif.
  // ---------------------------------------------------------------------------------------------

  // 15. CULL-AVEUGLE, CONTROLE POSITIF — was-drawn a 0 alors que la position racine est DANS le
  //     champ. Le moteur ne l'a pas soumis, et ce n'est pas la camera qui l'a laisse dehors.
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-CA", {shown("mayor-lod0", 700)});
  }
  for (int i = 0; i < 8; i++) {
    Actor a{"mayor-lod0", 700, 0u, true, false};  // was-drawn absent
    a.in_fov = 1;                                 // ... et pourtant dans le champ
    run_frame("scene-CA", {a});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-CA", {shown("mayor-lod0", 700)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 1 && t.by_reason[npc_flicker::kReasonCullBlind] == 1,
          "was-drawn=0 mais racine DANS le champ : cycle cause=cull-aveugle",
          "cycles=" + std::to_string(t.cycles) +
              " cull_aveugle=" + std::to_string(t.by_reason[npc_flicker::kReasonCullBlind]));
    check(t.by_reason[npc_flicker::kReasonCulled] == 0,
          "  ... et il ne retombe PAS dans le seau non gate `culled`",
          "culled=" + std::to_string(t.by_reason[npc_flicker::kReasonCulled]));
  }

  // 16. CULL-AVEUGLE, CONTROLE NEGATIF — meme absence, mais la racine est HORS du champ. C'est la
  //     camera qui a coupe : non gate, exactement comme avant.
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-CB", {shown("mayor-lod0", 700)});
  }
  for (int i = 0; i < 8; i++) {
    Actor a{"mayor-lod0", 700, 0u, true, false};
    a.in_fov = 0;
    run_frame("scene-CB", {a});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-CB", {shown("mayor-lod0", 700)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 0 && t.by_reason[npc_flicker::kReasonCulled] == 1,
          "was-drawn=0 et racine HORS du champ : coupe, pas un cycle",
          "cycles=" + std::to_string(t.cycles) +
              " culled=" + std::to_string(t.by_reason[npc_flicker::kReasonCulled]));
  }

  // 17. NODRAW, CONTROLE POSITIF — was-drawn POSE, donc GOAL a soumis, et le rendu n'a rien
  //     dessine, sans suppression de couverture ni modele absent. Le cycle 1 rendait `culled`.
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-CC", {shown("farmer-lod0", 800)});
  }
  for (int i = 0; i < 8; i++) {
    run_frame("scene-CC", {Actor{"farmer-lod0", 800, kWasDrawn, true, false}});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("scene-CC", {shown("farmer-lod0", 800)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 1 && t.by_reason[npc_flicker::kReasonNodraw] == 1,
          "was-drawn=1 et rien de dessine : cycle cause=soumis-mais-non-dessine",
          "cycles=" + std::to_string(t.cycles) +
              " nodraw=" + std::to_string(t.by_reason[npc_flicker::kReasonNodraw]));
  }

  // 18. LE RACCORD « flux-non-arme » -> NOM REEL NE DOIT PAS JETER LE RECENSEMENT. Le bit `movie`
  //     est arme a l'entree de play-anim, mais `active-stream` n'est ecrit qu'apres
  //     `str-play-async` : le cycle 1 vidait tout a ce changement de nom, donc le DEBUT de chaque
  //     cinematique — dont sa premiere frontiere de partie — etait hors instrument. Ici l'episode
  //     s'ouvre sous « flux-non-arme » et se ferme sous le vrai nom : UNE scene, UN cycle.
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("flux-non-arme", {shown("mayor-lod0", 900)});
  }
  for (int i = 0; i < 8; i++) {
    run_frame("flux-non-arme", {Actor{"mayor-lod0", 900, kNoAnim, true, false}});
  }
  for (int i = 0; i < 10; i++) {
    run_frame("mayor-introduction", {shown("mayor-lod0", 900)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.scenes == 1 && t.cycles == 1,
          "episode ouvert avant que le flux porte son nom : compte, sous UNE seule scene",
          "scenes=" + std::to_string(t.scenes) + " cycles=" + std::to_string(t.cycles));
  }

  // ---------------------------------------------------------------------------------------------
  // Gcutscene-npc-flicker-2, CYCLE 3 — L'ANGLE MORT « DESSINE MAIS INVISIBLE ».
  // Les deux cycles precedents ne pouvaient voir qu'une ABSENCE de dessin. Un paquet dessine avec
  // des matrices d'os invalides (NaN, os a des kilometres, matrice nulle) ne met rien a l'ecran
  // et comptait comme une PRESENCE. Trois proprietes : le controle positif tire avec la bonne
  // cause, le controle negatif ne tire pas, et l'etat vivant (celui que le compteur FPS affiche
  // a l'owner) reflete le cycle pendant la scene.
  // ---------------------------------------------------------------------------------------------
  // 19. MATRICE INVALIDE, CONTROLE POSITIF — was-drawn pose, paquet DESSINE, matrices invalides
  //     pendant 8 images : un cycle, cause `matrice-invalide`, et PAS `nodraw`.
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-G", {shown("mayor-lod0", 1000)});
  }
  for (int i = 0; i < 8; i++) {
    Actor a = shown("mayor-lod0", 1000);
    a.outcome = npc_flicker::Outcome::kGarbage;
    run_frame("scene-G", {a});
  }
  npc_flicker::Live mid = npc_flicker::live_status();
  for (int i = 0; i < 10; i++) {
    run_frame("scene-G", {shown("mayor-lod0", 1000)});
  }
  npc_flicker::Live fin = npc_flicker::live_status();
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 1 && t.by_reason[npc_flicker::kReasonGarbage] == 1 &&
              t.by_reason[npc_flicker::kReasonNodraw] == 0,
          "dessine avec des matrices INVALIDES : cycle cause=matrice-invalide",
          "cycles=" + std::to_string(t.cycles) +
              " matrice_invalide=" + std::to_string(t.by_reason[npc_flicker::kReasonGarbage]) +
              " nodraw=" + std::to_string(t.by_reason[npc_flicker::kReasonNodraw]));
    // 20. L'ETAT VIVANT (compteur FPS) : pendant l'episode rien n'est encore ferme, apres la
    //     reprise du dessin le cycle est visible AVEC sa cause — et la scene est declaree en cours.
    check(mid.in_scene && mid.cycles == 0 && fin.in_scene && fin.cycles == 1 &&
              fin.last_reason == (int)npc_flicker::kReasonGarbage,
          "etat vivant : 0 cycle pendant l'episode, 1 cycle + cause apres la reprise",
          "mid=" + std::to_string(mid.cycles) + " fin=" + std::to_string(fin.cycles) +
              " cause=" + std::to_string(fin.last_reason));
    npc_flicker::Live out = npc_flicker::live_status();
    check(!out.in_scene && out.cycles == 0, "etat vivant hors cinematique : aucune scene",
          "in_scene=" + std::to_string(out.in_scene));
  }

  // 21. MATRICE INVALIDE, CONTROLE NEGATIF — une matrice invalide notee a une image ANTERIEURE ne
  //     doit pas contaminer les images suivantes ou le dessin est sain : 1 image invalide = un
  //     `blink` au plus, jamais un cycle, et `matrice_invalide` reste a 0 dans les cycles.
  npc_flicker::reset_for_test();
  g_frame = 0;
  for (int i = 0; i < 10; i++) {
    run_frame("scene-H", {shown("mayor-lod0", 1100)});
  }
  {
    Actor a = shown("mayor-lod0", 1100);
    a.outcome = npc_flicker::Outcome::kGarbage;
    run_frame("scene-H", {a});
  }
  for (int i = 0; i < 20; i++) {
    run_frame("scene-H", {shown("mayor-lod0", 1100)});
  }
  npc_flicker::begin_census("hors-cinematique");
  {
    auto t = npc_flicker::totals();
    check(t.cycles == 0 && t.by_reason[npc_flicker::kReasonGarbage] == 0 && t.blinks <= 1,
          "une seule image invalide : au plus un blink, jamais un cycle",
          "cycles=" + std::to_string(t.cycles) + " blinks=" + std::to_string(t.blinks));
  }

  // 23. DANS LE FRUSTUM ET ECARTE DU RENDU, PAR IMAGE (porte du superviseur 2026-09-03 03:05).
  //     Positif : 2 images ou la racine est dans le champ, statut 0 (ni hidden ni no-anim, pas de
  //     was-drawn) -> dans_frustum_et_culled=2, sous le seuil d'episode (blink) mais COMPTE.
  //     Negatif : les memes 2 images avec la racine HORS du champ -> 0. Et hidden dans le champ
  //     ne compte pas : c'est une decision du jeu, pas un ecartement.
  {
    auto run_case = [&](int fov, uint32_t status) -> npc_flicker::Totals {
      npc_flicker::reset_for_test();
      g_frame = 0;
      for (int i = 0; i < 10; i++) {
        run_frame("scene-F", {shown("mayor-lod0", 1200)});
      }
      for (int i = 0; i < 2; i++) {
        Actor a{"mayor-lod0", 1200, status, true, false};
        a.in_fov = fov;
        run_frame("scene-F", {a});
      }
      for (int i = 0; i < 10; i++) {
        run_frame("scene-F", {shown("mayor-lod0", 1200)});
      }
      npc_flicker::begin_census("hors-cinematique");
      return npc_flicker::totals();
    };
    auto pos = run_case(1, 0u);
    auto neg = run_case(0, 0u);
    auto hid = run_case(1, kHidden);
    check(pos.in_fov_culled_frames == 2 && pos.in_fov_frames == 2 && pos.cycles == 0,
          "dans le champ + was-drawn=0, 2 images : dans_frustum_et_culled=2 (sous le seuil, compte)",
          "dans_frustum_et_culled=" + std::to_string(pos.in_fov_culled_frames) +
              " images_dans_frustum=" + std::to_string(pos.in_fov_frames));
    check(neg.in_fov_culled_frames == 0 && neg.in_fov_frames == 0,
          "hors du champ + was-drawn=0 : dans_frustum_et_culled=0",
          "dans_frustum_et_culled=" + std::to_string(neg.in_fov_culled_frames));
    check(hid.in_fov_culled_frames == 0 && hid.in_fov_frames == 2,
          "hidden dans le champ : compte dans le champ, pas comme ecarte",
          "dans_frustum_et_culled=" + std::to_string(hid.in_fov_culled_frames) +
              " images_dans_frustum=" + std::to_string(hid.in_fov_frames));
  }

  // 22. LA PLATEFORME EST PUBLIEE PAR LE CODE, pas par l'analyseur : sur ce bureau elle vaut
  //     "x86" ; sur Android c'est la marque lue dans ro.product.brand (redmi, honor).
  {
    std::string tag = npc_flicker::platform_tag();
    check(tag == "x86", "plateforme publiee par le code (bureau = x86)", "plateforme=" + tag);
  }

  // ---------------------------------------------------------------------------------------------
  // LA GRANDEUR DE LA PORTE : `npc_culled_in_frustum` (Totals::in_fov_dark_frames_npc).
  //
  // POURQUOI CES CINQ CAS EXISTENT. Le defaut est deja revenu trois fois, et A CHAQUE FOIS la
  // porte publiait zero. Le zero n'etait jamais faux : c'est ce qu'il COMPTAIT qui l'etait. Un
  // compteur de porte sans controle positif est un compteur mort en puissance — c'est
  // exactement l'histoire de `[hd-flicker] blackouts=`. Ces cas fixent, dans du code que la
  // construction de `gk` execute, ce que le compteur doit compter ET ce qu'il ne doit pas.
  // ---------------------------------------------------------------------------------------------
  printf("\n");
  {
    // (a) CONTROLE POSITIF : PNJ dans le champ, plus rien de dessine, 5 images -> 5 comptees.
    npc_flicker::reset_for_test();
    g_frame = 0;
    for (int i = 0; i < 10; i++) {
      run_frame("porte-a", {Actor{"mayor-lod0", 900, kWasDrawn, true, true, npc_flicker::Outcome::kDrawn, 1, 1, 1}});
    }
    for (int i = 0; i < 5; i++) {
      run_frame("porte-a", {Actor{"mayor-lod0", 900, kWasDrawn, true, false, npc_flicker::Outcome::kDrawn, 1, 1, 1}});
    }
    for (int i = 0; i < 10; i++) {
      run_frame("porte-a", {Actor{"mayor-lod0", 900, kWasDrawn, true, true, npc_flicker::Outcome::kDrawn, 1, 1, 1}});
    }
    npc_flicker::begin_census("hors-cinematique");
    auto t = npc_flicker::totals();
    // 5 images sans dessin -> 4 comptees. La difference est la TOLERANCE D'UNE IMAGE entre
    // l'horloge du recensement et celle du rendu (`draw_tolerance()`, npc_flicker.cpp) : la
    // premiere image d'un trou est encore lue « dessine ». C'est un sous-comptage ASSUME et
    // documente ; il est fixe ici pour qu'un changement de tolerance ne passe pas inapercu.
    check(t.in_fov_dark_frames_npc == 4,
          "porte : PNJ dans le champ, rien de dessine 5 images -> 4 (tolerance 1)",
          "npc_culled_in_frustum=" + std::to_string(t.in_fov_dark_frames_npc));
  }
  {
    // (b) CONTROLE NEGATIF DE SEUIL : une SEULE image noire est le decalage des deux horloges,
    //     pas un clignotement. La regle des trois images doit la rejeter.
    npc_flicker::reset_for_test();
    g_frame = 0;
    for (int i = 0; i < 10; i++) {
      run_frame("porte-b", {Actor{"mayor-lod0", 900, kWasDrawn, true, true, npc_flicker::Outcome::kDrawn, 1, 1, 1}});
    }
    run_frame("porte-b", {Actor{"mayor-lod0", 900, kWasDrawn, true, false, npc_flicker::Outcome::kDrawn, 1, 1, 1}});
    for (int i = 0; i < 10; i++) {
      run_frame("porte-b", {Actor{"mayor-lod0", 900, kWasDrawn, true, true, npc_flicker::Outcome::kDrawn, 1, 1, 1}});
    }
    npc_flicker::begin_census("hors-cinematique");
    auto t = npc_flicker::totals();
    check(t.in_fov_dark_frames_npc == 0,
          "porte : une image noire isolee ne compte pas (regle des 3)",
          "npc_culled_in_frustum=" + std::to_string(t.in_fov_dark_frames_npc));
  }
  {
    // (c) CONTROLE NEGATIF DE CAUSE : hors du champ, sphere A JOUR -> c'est une coupe de camera,
    //     et le moteur qui fonctionne ne doit jamais faire monter la porte.
    npc_flicker::reset_for_test();
    g_frame = 0;
    for (int i = 0; i < 10; i++) {
      run_frame("porte-c", {Actor{"mayor-lod0", 900, kWasDrawn, true, true, npc_flicker::Outcome::kDrawn, 1, 1, 1}});
    }
    for (int i = 0; i < 20; i++) {
      run_frame("porte-c", {Actor{"mayor-lod0", 900, 0, true, false, npc_flicker::Outcome::kDrawn, 1, 0, 1}});
    }
    npc_flicker::begin_census("hors-cinematique");
    auto t = npc_flicker::totals();
    check(t.in_fov_dark_frames_npc == 0,
          "porte : hors du champ avec sphere a jour = coupe de camera, 0",
          "npc_culled_in_frustum=" + std::to_string(t.in_fov_dark_frames_npc));
  }
  {
    // (d) SPHERE PERIMEE : `no-anim` fige `draw origin` (process-drawable.gc:239). Le verdict
    //     « hors du champ » n'est plus une mesure, c'est un souvenir : l'absence compte, meme
    //     avec in_fov=0. C'est le mecanisme que `Gfirstperson-hd-hide` a arme le 2026-08-28 et
    //     que l'owner a signale trois jours plus tard.
    npc_flicker::reset_for_test();
    g_frame = 0;
    for (int i = 0; i < 10; i++) {
      run_frame("porte-d", {Actor{"mayor-lod0", 900, kWasDrawn, true, true, npc_flicker::Outcome::kDrawn, 1, 1, 1}});
    }
    for (int i = 0; i < 6; i++) {
      run_frame("porte-d", {Actor{"mayor-lod0", 900, kNoAnim, true, false, npc_flicker::Outcome::kDrawn, 1, 0, 1}});
    }
    npc_flicker::begin_census("hors-cinematique");
    auto t = npc_flicker::totals();
    check(t.in_fov_dark_frames_npc == 5,
          "porte : sphere perimee (no-anim) -> l'absence compte quand meme (6-1)",
          "npc_culled_in_frustum=" + std::to_string(t.in_fov_dark_frames_npc));
  }
  {
    // (e) LE MODELE, PAS LE PID. Pendant une cinematique le personnage est souvent porte par un
    //     CLONE, dont le pid n'est pas celui du process recense. Une presence dessinee sous un
    //     AUTRE pid mais le MEME modele doit fermer l'episode : sinon la porte publie un defaut
    //     la ou l'ecran montre le personnage.
    npc_flicker::reset_for_test();
    g_frame = 0;
    for (int i = 0; i < 10; i++) {
      run_frame("porte-e", {Actor{"mayor-lod0", 900, kWasDrawn, true, true, npc_flicker::Outcome::kDrawn, 1, 1, 1}});
    }
    for (int i = 0; i < 8; i++) {
      g_frame++;
      npc_flicker::end_render_frame(g_frame);
      // le CLONE dessine le meme modele sous un pid different
      npc_flicker::note_draw(4242, npc_flicker::Outcome::kDrawn, false, "mayor-lod0");
      npc_flicker::begin_census("porte-e");
      npc_flicker::census_actor("mayor-lod0", "mayor-lod0", 900, kWasDrawn, 1, 1, 1);
      npc_flicker::end_census();
    }
    npc_flicker::begin_census("hors-cinematique");
    auto t = npc_flicker::totals();
    check(t.in_fov_dark_frames_npc == 0,
          "porte : dessine par un CLONE (autre pid, meme modele) -> 0",
          "npc_culled_in_frustum=" + std::to_string(t.in_fov_dark_frames_npc));
  }

  {
    // (f) LE CORRECTIF LUI-MEME — CONTROLE POSITIF. `should_hold_clone` doit rendre VRAI tant que
    //     la serie tient dans son budget : c'est ce qui garde le modele a l'ecran a la place du
    //     `hidden` de generic-obs.gc:81. Un correctif qui ne rend jamais vrai serait exactement
    //     la garde morte de 45b7140ca7.
    npc_flicker::reset_for_test();
    g_frame = 0;
    int held = 0;
    for (int i = 0; i < 5; i++) {
      g_frame++;
      npc_flicker::end_render_frame(g_frame);
      if (npc_flicker::should_hold_clone(777)) {
        held++;
      }
    }
    check(held == 5, "correctif : 5 images d'echec de suite -> le clone est MAINTENU 5 fois",
          "maintenus=" + std::to_string(held) + "/5");
  }
  {
    // (g) SON PLAFOND — CONTROLE NEGATIF. Au-dela de `clone_hold_ms()`, on retombe sur l'ancien
    //     comportement : un echec PERMANENT ne doit pas laisser un modele fige indefiniment.
    //     Sans ce bras, le correctif remplacerait un defaut par un autre.
    npc_flicker::reset_for_test();
    g_frame = 0;
    g_frame++;
    npc_flicker::end_render_frame(g_frame);
    const bool first = npc_flicker::should_hold_clone(778);
    std::this_thread::sleep_for(std::chrono::milliseconds(npc_flicker::clone_hold_ms() + 40));
    g_frame++;
    npc_flicker::end_render_frame(g_frame);
    const bool after = npc_flicker::should_hold_clone(778);
    check(first && !after, "correctif : au-dela du plafond, retour a l'ancien comportement",
          "premiere=" + std::to_string(first ? 1 : 0) + " apres_plafond=" +
              std::to_string(after ? 1 : 0) + " plafond_ms=" +
              std::to_string(npc_flicker::clone_hold_ms()));
    // ... et une NOUVELLE serie repart a zero : un echec transitoire ne doit jamais payer le
    // budget deja consomme par un echec plus ancien.
    g_frame += 10;
    npc_flicker::end_render_frame(g_frame);
    check(npc_flicker::should_hold_clone(778),
          "correctif : une serie rompue repart avec un budget neuf", "serie=2");
  }
  {
    // (i) LA POPULATION DE L'OWNER SURVIT AU CHANGEMENT DE SCENE. `is_npc` vient d'un predicat de
    //     type evalue sur le PROCESS ; pendant une cinematique le modele d'un PNJ est porte par un
    //     CLONE, qui n'est pas un `process-taskable`. Le meme modele valait donc 1 dans une scene
    //     et 0 dans la suivante, et le compteur de la porte le perdait EN SILENCE.
    npc_flicker::reset_for_test();
    g_frame = 0;
    for (int i = 0; i < 6; i++) {
      run_frame("porte-i1", {Actor{"mayor-lod0", 900, kWasDrawn, true, true, npc_flicker::Outcome::kDrawn, 1, 1, 1}});
    }
    npc_flicker::begin_census("hors-cinematique");
    // scene suivante : le MEME modele, porte par un clone que GOAL ne reconnait pas taskable.
    for (int i = 0; i < 6; i++) {
      run_frame("porte-i2", {Actor{"mayor-lod0", 901, kWasDrawn, true, true, npc_flicker::Outcome::kDrawn, 1, 1, 0}});
    }
    for (int i = 0; i < 6; i++) {
      run_frame("porte-i2", {Actor{"mayor-lod0", 901, kNoAnim, true, false, npc_flicker::Outcome::kDrawn, 1, 0, 0}});
    }
    npc_flicker::begin_census("hors-cinematique");
    auto t = npc_flicker::totals();
    check(t.in_fov_dark_frames_npc == 5,
          "porte : un modele deja reconnu PNJ le reste sous un clone (is_npc=0)",
          "npc_culled_in_frustum=" + std::to_string(t.in_fov_dark_frames_npc));
  }

  {
    // (j) ESSAI 11 — LES COMPTEURS DE PLATEFORME SORTENT PAR SCENE, EN DELTA, ET DISENT LEUR SOURCE.
    //     Le defaut n'existe que sur l'appareil de l'owner ; la seule trace qui en revient est
    //     npc_flicker.txt. Cette ligne doit donc (1) porter la DIFFERENCE entre la fin et le debut
    //     de la scene, jamais le cumul depuis le boot, (2) declarer QUI l'a remplie : un zero
    //     sans source n'est pas une mesure. Controle positif : la source bouge pendant la scene,
    //     le delta doit etre exactement ce mouvement.
    npc_flicker::reset_for_test();
    npc_flicker::set_host_counters_fn(nullptr);
    npc_flicker::set_render_counters_fn(nullptr);
    g_frame = 0;
    for (int i = 0; i < 6; i++) {
      run_frame("plat-0", {shown("mayor-lod0", 950)});
    }
    npc_flicker::begin_census("hors-cinematique");
    check(npc_flicker::platform_sources() == 0 && npc_flicker::platform_totals()[0] == 0,
          "plateforme : sans source, sources=0 et rien n'est compte",
          "sources=" + std::to_string(npc_flicker::platform_sources()));
    // une source hote factice : nullfg part de 5, et monte a 7 PENDANT la scene
    static uint64_t s_fake_nullfg = 5;
    static uint64_t s_fake_failopen = 100;
    npc_flicker::set_host_counters_fn([](uint64_t* out, int n) {
      if (n > npc_flicker::kPlatNullFg) {
        out[npc_flicker::kPlatNullFg] = s_fake_nullfg;
      }
    });
    npc_flicker::set_render_counters_fn([](uint64_t* out, int n) {
      if (n > npc_flicker::kPlatHdFailOpen) {
        out[npc_flicker::kPlatHdFailOpen] = s_fake_failopen;
      }
    });
    for (int i = 0; i < 6; i++) {
      run_frame("plat-1", {shown("mayor-lod0", 951)});
    }
    s_fake_nullfg = 7;      // deux reparations pendant la scene
    s_fake_failopen = 103;  // trois fail-open
    for (int i = 0; i < 6; i++) {
      run_frame("plat-1", {shown("mayor-lod0", 951)});
    }
    npc_flicker::begin_census("hors-cinematique");
    const uint64_t* pt = npc_flicker::platform_totals();
    check(npc_flicker::platform_sources() == 3, "plateforme : hote ET rendu declares (sources=3)",
          "sources=" + std::to_string(npc_flicker::platform_sources()));
    check(pt[npc_flicker::kPlatNullFg] == 2,
          "plateforme : la scene publie le DELTA (7-5=2), pas le cumul depuis le boot",
          "nullfg=" + std::to_string(pt[npc_flicker::kPlatNullFg]));
    check(pt[npc_flicker::kPlatHdFailOpen] == 3, "plateforme : le rendu remplit sa case (fail-open=3)",
          "hd_failopen=" + std::to_string(pt[npc_flicker::kPlatHdFailOpen]));
    // une scene SANS mouvement rend zero : le delta ne fuit pas d'une scene a l'autre
    for (int i = 0; i < 6; i++) {
      run_frame("plat-2", {shown("mayor-lod0", 952)});
    }
    npc_flicker::begin_census("hors-cinematique");
    check(pt[npc_flicker::kPlatNullFg] == 2 && pt[npc_flicker::kPlatHdFailOpen] == 3,
          "plateforme : une scene sans evenement n'ajoute rien",
          "nullfg=" + std::to_string(pt[npc_flicker::kPlatNullFg]) +
              " hd_failopen=" + std::to_string(pt[npc_flicker::kPlatHdFailOpen]));
    npc_flicker::set_host_counters_fn(nullptr);
    npc_flicker::set_render_counters_fn(nullptr);
  }

  printf("\n%s — %d echec(s)\n", g_fail ? "SELFTEST FAILED" : "SELFTEST PASS", g_fail);
  return g_fail ? 1 : 0;
}
