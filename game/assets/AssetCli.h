#pragma once

// Grecharged-managed-assets: the `gk --assets <verb>` driver. Headless, runs
// before any graphics/IOP machinery, and exits — so a pack can be installed,
// inspected or re-verified without launching the game (and from a script).
//
//   gk --assets status                    what is installed vs what the lock pins
//   gk --assets install [--assets-preset default] [--assets-profile pc-bc]
//   gk --assets verify                    re-hash every installed shard
//
// The profile normally comes from GpuCaps, which needs a GL context; the
// headless path therefore takes --assets-profile, defaulting to the desktop
// BC profile. In-game installs (phase F) use the detected one.

#include <string>

#include "common/versions/versions.h"

namespace assets {

// Returns a process exit code. `verb` is one of status|install|verify.
int run_cli(const std::string& verb,
            GameVersion game_version,
            const std::string& profile_override,
            const std::string& preset,
            bool assume_yes);

}  // namespace assets
