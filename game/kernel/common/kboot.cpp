#include "kboot.h"

#include <cstring>

// Grecharged-buildsys-flags: flag-set marker paired with the GOAL-side
// *og-flag-set-marker* (generated pc/recharged-flags.gc). deploy_verify/
// release_verify grep both artifacts and refuse mixed flag-set builds
// (libgk vs CGOs). OG_FLAG_SET_ID is stamped onto THIS TU only (see root
// CMakeLists set_source_files_properties). Fallback keeps a stable string
// if the define is somehow absent (e.g. a raw single-file compile).
#ifndef OG_FLAG_SET_ID
#define OG_FLAG_SET_ID "unknown:unknown"
#endif
#if defined(__GNUC__) || defined(__clang__)
extern "C" __attribute__((used)) const char g_og_flag_set_marker[] = "ogflags:" OG_FLAG_SET_ID;
#elif defined(_MSC_VER)
// MSVC has no `used` attribute; /include pins the symbol against /OPT:REF so
// the marker string always survives into gk.exe (packaging greps it).
extern "C" const char g_og_flag_set_marker[] = "ogflags:" OG_FLAG_SET_ID;
#pragma comment(linker, "/include:g_og_flag_set_marker")
#else
extern "C" const char g_og_flag_set_marker[] = "ogflags:" OG_FLAG_SET_ID;
#endif

// Set to 1 to kill GOAL kernel
RuntimeExitStatus MasterExit;

// Set to 1 to load game engine after boot automatically
u32 DiskBoot;

// Set to 1 to enable debug heap
u32 MasterDebug;

// added in pc port for splash screen
Timer SplashTimer;
u32 SplashScreen;

// Set to 1 to load debug code
u32 DebugSegment;

u32 MasterUseKernel;

// Level to load on boot
char DebugBootLevel[64];

// Pass to GOAL kernel on boot
char DebugBootMessage[64];

// game configuration
MasterConfig masterConfig;

void kboot_init_globals_common() {
  MasterExit = RuntimeExitStatus::RUNNING;
  DiskBoot = 0;
  MasterDebug = 1;
  DebugSegment = 1;
  MasterUseKernel = 1;
  SplashScreen = 1;
  strcpy(DebugBootLevel, "#f");      // no specified level
  strcpy(DebugBootMessage, "play");  // play mode, the default retail mode
  memset(&masterConfig, 0, sizeof(MasterConfig));
}