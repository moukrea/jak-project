#pragma once

#include "common/common_types.h"
// Discord RPC
struct DiscordRichPresence;
namespace jak1 {
/*!
 * Initialize global variables based on command line parameters
 */
void InitParms(int argc, const char* const* argv);
/*!
 * Initialize the I/O Processor
 */
void InitIOP();
/*!
 * Initialze GOAL Runtime
 */
int InitMachine();
/*!
 * Shutdown GOAL runtime.
 */
int ShutdownMachine();

void InitMachineScheme();

/*!
 * PHYS-ROOM (Grecharged-secondary-motion, SPEC §6 étape 1) — env OG_PHYS_ROOM / prop
 * debug.opengoal.phys.room, OFF by default. Once armed (any value but "" and "0"), it
 * calls the GOAL function `phys-room-start` through the *listener-function* trampoline
 * after OG_PHYS_ROOM_DELAY ticks (default 600), from the title screen — no game session
 * required — to open the player-less physics test room. Never armed in production.
 */
void phys_room_maybe();

struct DiscordInfo {
  u32 fuel;
  u32 money_total;
  u32 buzzer_total;
  u32 deaths;
  u32 status;
  u32 level;
  u32 cutscene;   // check if cutscene is playing
  u32 ogreboss;   // are we fighting ogreboss?
  u32 plantboss;  // are we fighting plant-boss?
  u32 racer;      // are we driving the zoomer?
  u32 flutflut;   // are we riding on flut flut?
  u32 time_of_day;
};

// To speedup finding the auto-splitter block in GOAL memory
// all this has is a marker for LiveSplit to find, and then the pointer
// to the symbol
struct AutoSplitterBlock {
  const char marker[20] = "UnLiStEdStRaTs_JaK1";
  u64 pointer_to_symbol = 0;
};
extern AutoSplitterBlock g_auto_splitter_block_jak1;
}  // namespace jak1
