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

#include <cstdio>
#include <cstdlib>
#include <string>
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
};

// Une image complete, dans l'ORDRE REEL du moteur : le rendu avance et publie ses issues, puis
// GOAL recense (main.gc appelle npc-census-tick depuis post-sync-draw, apres la passe de dessin).
void run_frame(const char* scene, const std::vector<Actor>& actors) {
  g_frame++;
  npc_flicker::end_render_frame(g_frame);
  for (const auto& a : actors) {
    if (a.drawn) {
      npc_flicker::note_draw(a.pid, npc_flicker::Outcome::kDrawn, false);
    } else if (a.outcome != npc_flicker::Outcome::kDrawn) {
      npc_flicker::note_draw(a.pid, a.outcome, false);
    }
  }
  npc_flicker::begin_census(scene);
  for (const auto& a : actors) {
    if (a.in_tree) {
      npc_flicker::census_actor(a.name, a.name, a.pid, a.status, a.level_active);
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

  printf("\n%s — %d echec(s)\n", g_fail ? "SELFTEST FAILED" : "SELFTEST PASS", g_fail);
  return g_fail ? 1 : 0;
}
