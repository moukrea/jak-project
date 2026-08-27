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

}  // namespace load_gate
