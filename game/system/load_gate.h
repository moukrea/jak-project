#pragma once

// Gplayability-input-and-loadgate (owner 2026-08-27).
//
// WHAT THIS IS
// ------------
// A scene in this engine is driven by its AUDIO stream: `ja-play-spooled-anim`
// starts the stream with `str-play-async`, and from that instant the animation
// frame is slaved to `current-str-pos` (goal_src/jak1/engine/load/loader.gc).
// The command-list that displays the levels the scene shows is executed by
// ANIMATION FRAME NUMBER. So once the stream starts, the picture can never
// catch up: if the level is still loading, the scene simply plays against a
// half-built world.
//
// Measured on the owner's Shield, 2026-08-27 (two boots, reproducible to 3 ms):
//   ndi-intro   sound -> `title` drawable    :   683 / 651 ms late
//   logo-intro  sound -> `village1` drawable :  4742 / 4740 ms late
//   sage-intro-sequence-e (return from Geyser Rock)
//               sound -> `beach` drawable    : 41 950 ms late
//
// A barrier already existed (Loader::update_blocking, armed by the
// blackout->visible transition in OpenGLRenderer.cpp). It runs ONE STEP TOO
// LATE: the blackout lifts *after* `str-play-async` has already started the
// clock, and for a level whose DGO is still streaming it has nothing to block
// on at all (measured: 33 ms of work on the beach leg, and beach was not
// drawable until 38 s later).
//
// This gate closes BEFORE the audio starts. GOAL polls `scene_ready` in a
// suspend loop; the renderer publishes which levels are actually drawable.
//
// NATURE of the quantity: a RESIDENCY STATE, not a timer. The gate never adds
// a delay of its own — when the levels are already resident the very first
// poll returns "go", so a fast machine is bit-for-bit unchanged.
//
// FRAME of the quantity: renderer-side GPU residency (the level's tfrag3
// geometry and textures are uploaded), NOT GOAL's `level-status`. GOAL's
// status only covers the DGO; on the beach leg GOAL said "loaded" 38 s before
// the level could be drawn.
//
// FAIL-OPEN, ALWAYS. If nothing ever publishes residency (a build where the
// renderer feed is not wired, a headless run, a level that never loads), the
// gate opens instead of holding. A barrier that can wedge the game is worse
// than the pop-in it removes.

#include <string>

namespace load_gate {

// ---- renderer -> gate ------------------------------------------------------
// Called by Loader when a level's geometry+textures have finished uploading
// and it is genuinely drawable, and when it is evicted.
void mark_level_resident(const std::string& level_name);
void mark_level_evicted(const std::string& level_name);

// ---- gate -> renderer ------------------------------------------------------
// True while at least one scene barrier is closed. The renderer uses this to
// run the loader at full speed (update_blocking) instead of the per-frame
// budget: nobody is looking at the frame while we hold the scene, so spending
// only TIE_LOAD_BUDGET (1.5 ms) + SHARED_TEXTURE_LOAD_BUDGET (3 ms) per frame
// is pure loss. Measured: village1 crawled for 13.4 s on the budgeted path and
// then finished in 4.6 s once the blocking path took over.
bool wants_blocking_loads();

// ---- GOAL -> gate ----------------------------------------------------------
// Is this level drawable right now?
bool level_is_resident(const char* level_name);

// Scene barrier. The first call for `scene` arms a deadline.
// Returns 1 when every named level is resident, or when the deadline expired,
// or when the gate cannot know (fail-open). Returns 0 while it should hold.
// `level0`/`level1` may be null, empty, "none" or "#f" — those are ignored.
int scene_ready(const char* scene, const char* level0, const char* level1, int timeout_ms);

// Drop a scene's armed barrier (called when the scene ends or is aborted).
void scene_release(const char* scene);

// Test seam: forget everything. Not used by the game.
void reset_for_test();



// ================================================================================================
// Gloading-screen (owner 2026-08-30) — LA CADENCE REELLE DE L'ECRAN DE CHARGEMENT, ET LE DECOUPAGE
// DU TRAVAIL GOAL QUI LA DETRUIT.
// ================================================================================================
//
// LE TROU QUE CECI BOUCHE. `LOADSCREEN-GAP` (Loader.cpp) ne mesure l'ecart entre deux images que
// tant qu'une barriere de scene est ARMEE, parce qu'il vit dans `update_blocking`, lui-meme appele
// seulement quand `wants_blocking_loads()` est vrai. Or `continue-load-gate!` relache la barriere
// des que le decor est resident cote GPU (loader.gc:1128), et l'ecran, lui, reste tenu par
// `LS_HOLD_TARGET` (target-death.gc:107, :159) pendant que le thread GOAL fait encore le login du
// niveau, la table d'entites et la liaison. Mesure sur trace x86 : dernier `LOADSCREEN-GAP` a
// t=62,345 s, ouverture de la barriere a t=62,688 s, puis PLUS RIEN. « La fin du chargement »,
// c'est-a-dire exactement le moment ou l'owner voit le gel, n'etait mesuree par aucun instrument.
//
// NATURE de la grandeur : une DUREE entre deux images REELLEMENT peintes, sur `steady_clock`.
// Ce n'est pas une horloge de jeu : sur l'appareil l'increment de l'horloge de jeu est plafonne a
// 4 frames et le retard est JETE (android/gk_android_main.cpp:787-799), donc une horloge de jeu
// SOUS-ESTIME un gel par construction. REPERE : le temps mural du processus.
// CE QU'ELLE LIT QUAND LE DEFAUT EST ABSENT : des ecarts a ~16,7 ms et un maximum du meme ordre.
//
// Publie par SECONDE et pas seulement en moyenne : l'owner l'a demande mot pour mot (« publier la
// cadence mesuree PENDANT la derniere seconde d'un chargement de sauvegarde, pas sur la moyenne
// du chargement. Une moyenne sur dix secondes noie un gel d'une seconde. »)
void loading_screen_tick(int hold_mask);
void loading_screen_end();

// ---- decoupage du travail fait par le thread GOAL --------------------------
// Plusieurs etages du chargement d'un niveau tournent SANS AUCUN BUDGET DE TEMPS cote GOAL, et
// tiennent donc une frame entiere — c'est-a-dire qu'ils FIGENT l'ecran de chargement, quel que
// soit ce que fait le renderer. Ils sont tous COLD-ONLY, ce qui explique le discriminant de
// l'owner (le gel n'apparait pas sur une teleportation vers un niveau deja resident).
// GOAL n'a pas d'horloge sous-frame sur PC : ces deux fonctions la lui donnent.
//   `goal_slice_begin(slot)`  : marque le debut de la tranche `slot`.
//   `goal_slice_expired(slot)`: 1 des que le budget est consomme. Rend TOUJOURS 0 quand le budget
//                               vaut 0 — c'est l'ABLATION, sur le meme binaire, par
//                               OG_GOAL_SLICE_MS=0 (emplacement 0) ou OG_GOAL_LOOP_SLICE_MS
//                               (emplacement 1, DESARME PAR DEFAUT : voir load_gate.cpp, la
//                               mesure qui l'a refute).
//
// IL Y A PLUSIEURS EMPLACEMENTS, ET C'EST UNE NECESSITE, PAS UN CONFORT : la boucle bloquante de
// `update! load-state` (level.gc) appelle `load-continue`, qui appelle `level-update-after-load`,
// qui veut SA propre tranche. Avec un seul chronometre l'appel imbrique remettrait le depart a
// zero et la tranche exterieure n'expirerait JAMAIS — un budget qui ne se declenche pas est pire
// que pas de budget, parce qu'il a l'air pose.
void goal_slice_begin(int slot);
int goal_slice_expired(int slot);

}  // namespace load_gate
