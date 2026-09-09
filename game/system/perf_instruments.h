#pragma once

// perf_instruments — OU PASSE LE TEMPS D'UNE IMAGE, MESURE PAR LE MOTEUR, SUR LES DEUX PLATEFORMES.
//
// POURQUOI. « Kernel dispatch time » (kboot.cpp) chronometre un tour du dispatcher AVEC les
// attentes `sync-path` / `syncv` du process display, et ne s'imprime qu'au-dela de 50 ms : ce
// n'est ni le temps CPU GOAL ni une mesure. Les 35 seaux `with-profiler` de GOAL emettent vers
// `GlobalProfiler`, dont le corps est vide sur Android. Personne ne pouvait dire si une image
// lente l'etait par le fil GOAL, par le fil GL ou par le GPU.
//
// CE QUE CE MODULE MESURE (fil GOAL, sauf mention) et PUBLIE par `autoport_proof` toutes les
// 60 images, sous des cles `cle=valeur` que `lib/proof_run.sh` moissonne :
//
//   goal_busy_ms              = dispatch - attente sync-path - attente vsync, par image (moyenne
//                               sur la fenetre de 60 images). Les trois termes sont publies
//                               a cote (goal_dispatch_ms, goal_syncpath_wait_ms,
//                               goal_vsync_wait_ms) : un solde sans ses termes est invérifiable.
//   goal_bucket_ms_<seau>     = ns accumules entre le `begin` et le `end` de chaque seau
//                               `with-profiler` (recepteur du flux `pc-prof`), par image.
//                               Les 35 seaux connus sont TOUS publies ; ceux jamais entres
//                               dans la fenetre valent 0 et sont nommes dans
//                               `goal_buckets_unseen` — un zero sans son pourquoi est une
//                               fausse constante.
//   actors_active / actors_paused = process-drawable du `*entity-pool*` qui ont couru / n'ont
//                               pas couru au dernier tour du dispatcher. « A couru » n'est pas
//                               deduit d'une distance recalculee ici : c'est le `begin` que le
//                               noyau GOAL emet lui-meme pour chaque process qu'il execute
//                               (gkernel.gc, `profiler-start-event (process-name-as-string this)`),
//                               croise avec une marche de l'arbre a `ROOT`. Les acteurs sont
//                               nommes par la chaine de leur entite (entity.gc, `activate`),
//                               unique par acteur.
//   joints_evaluated          = somme des `num-bones` de `*bone-calculation-list*`, lue a
//                               l'entree du seau « bones », c'est-a-dire l'instant ou
//                               `bones-mtx-calc-execute` va la consommer.
//   dma_chain_bytes_copied    = octets copies par `FixedChunkDmaCopier` a `send_chain`, par
//                               image. x86 ne copie pas (`run_dma_copy = false`) : la valeur y
//                               est 0 et `dma_chain_copy_mode=0` le dit.
//   cpu_core_goal             = `sched_getcpu()` du fil GOAL a la frontiere d'image.
//   perf_map_entries          = lignes de `/data/local/tmp/perf-<pid>.map` (x86 : `/tmp`),
//                               relues apres ecriture. Le fichier est produit apres chaque
//                               rafale de `link finish` (klink) : une ligne par fonction
//                               nommee par un symbole et par methode de chaque type, au
//                               format que `perf` et `simpleperf` lisent.
//   perf_instruments_missing  = nombre de cles attendues ABSENTES de la table de publication
//                               (`autoport_proof::has_key`), y compris les `gpu_ms_*` que
//                               `lighting_census` declare bucket par bucket. La liste des
//                               absentes est publiee dans `perf_instruments_missing_keys`.
//
// ARMEMENT. Rien ne tourne — pas meme le recepteur `pc-prof` — sauf si le harnais nomme cet
// item (`AUTOPORT_FEATURE` / `debug.opengoal.feature`) ou si le reglage `OG_PERF_BUCKETS=1` /
// `debug.opengoal.perf.buckets=1` est pose. `armed_for("perf-instruments")` desarme tout, c'est
// le bras d'ablation. Le binaire de l'owner sans propriete paye un test de booleen par
// evenement.
//
// AUCUN PIXEL NE CHANGE : ce module ne fait que lire.

#include <cstdint>

namespace perf_instruments {

// Vrai quand les instruments tournent (voir ARMEMENT). Lisible depuis n'importe quel fil.
bool enabled();

// ── fil GOAL ────────────────────────────────────────────────────────────────────────────────
// Un tour du dispatcher vient de finir (kboot.cpp), duree en ns.
void note_dispatch_ns(uint64_t ns);
// Temps passe dans `sync-path` / `syncv` (enveloppes de kmachine.cpp), en ns.
void note_syncpath_wait_ns(uint64_t ns);
void note_vsync_wait_ns(uint64_t ns);
// Frontiere d'image : appelee a l'ENTREE de `syncv`, avant l'attente. Compte les images,
// echantillonne le coeur CPU, ecrit le perf map si des liens ont eu lieu, publie toutes les
// 60 images.
void frame_boundary();
// Le flux `pc-prof` de GOAL : `kind` = ProfNode::Kind (0 begin, 1 end, 2 instant).
// `name_ptr` est l'offset GOAL de la chaine, `name` son contenu.
void goal_prof_event(uint32_t name_ptr, const char* name, int kind);
// `send_chain` vient de copier `bytes` octets de chaine DMA (0 quand la copie est desactivee).
void note_dma_chain_copied(uint64_t bytes, bool copy_mode);
// klink : un objet vient d'etre lie ; le perf map sera reecrit apres la rafale.
void note_link_finish();

// ── declaration de cles attendues par d'autres modules (lighting_census pour gpu_ms_*) ──────
void expect_key(const char* key);

// ── lecture croisee (fil GL, ligne A35-SPART) ──────────────────────────────────────────────
struct Snapshot {
  double busy_ms = 0;
  double dispatch_ms = 0;
  double syncpath_ms = 0;
  double vsync_ms = 0;
  uint64_t dma_bytes = 0;
  uint64_t actors_active = 0;
  uint64_t actors_paused = 0;
  uint64_t joints = 0;
  int cpu_core = -1;
  uint64_t perf_map_entries = 0;
  uint64_t missing = 0;
  uint64_t frames = 0;
};
Snapshot snapshot();

}  // namespace perf_instruments
