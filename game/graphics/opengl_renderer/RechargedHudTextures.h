#pragma once

#include "game/graphics/texture/TexturePool.h"

// Loads the "Recharged" HUD sprite PNGs (recharged_assets/*.png at the repo/project root)
// into fixed PC texture-pool VRAM slots so GOAL can reference them by TBP in adgif TEX0.
// Slots (must match RHUD_TBP_* constants in goal_src/jak1/pc/hud-classes-pc.gc):
//   8300 jak_heart_100, 8301 jak_heart_66, 8302 jak_heart_33, 8303 jak_heart_0,
//   8304 jak_gauge_empty, 8305 jak_gauge_blue_full, 8306 jak_gauge_red_full,
//   8307 jak_gauge_yellow_full, 8308 jak_gauge_blue_end, 8309 jak_gauge_red_end,
//   8310 jak_gauge_yellow_end
void load_recharged_hud_textures(TexturePool& pool, GameVersion version);
