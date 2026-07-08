#pragma once

#include "game/graphics/texture/TexturePool.h"

// Loads the "Recharged" HUD sprite PNGs (recharged_assets/*.png at the repo/project root)
// into fixed PC texture-pool VRAM slots so GOAL can reference them by TBP in adgif TEX0.
// Slots (must match RHUD_TBP_* constants in goal_src/jak1/pc/hud-classes-pc.gc):
//   7900 jak_heart_100, 7901 jak_heart_66, 7902 jak_heart_33, 7903 jak_heart_0,
//   7904 jak_gauge_empty, 7905 jak_gauge_blue_full, 7906 jak_gauge_red_full,
//   7907 jak_gauge_yellow_full, 7908 jak_gauge_blue_end, 7909 jak_gauge_red_end,
//   7910 jak_gauge_yellow_end
void load_recharged_hud_textures(TexturePool& pool, GameVersion version);
