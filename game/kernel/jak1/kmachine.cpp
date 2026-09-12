#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#elif defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#include "kmachine.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <limits>
#include <array>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <type_traits>
#include <unordered_set>
#include <vector>

#include "common/log/log.h"
#include "common/symbols.h"
#include "common/util/FileUtil.h"
#include "common/util/Timer.h"
#include "common/util/string_util.h"

#include "game/external/discord_jak1.h"
#include "game/graphics/display.h"
#include "game/graphics/fixed_tick.h"
#include "game/graphics/render_pace.h"
#include "game/graphics/gfx.h"
#include "game/graphics/refset.h"
#include "game/graphics/refset_state.h"
#include "game/system/load_gate.h"
#include "game/graphics/fire_red_census.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/system/autoport_proof.h"
#include "game/system/mesh_browser_census.h"
#include "game/system/recharged_gating.h"
#include "game/system/perf_baseline.h"
#include "game/system/perf_instruments.h"
#include "game/system/checkpoint_census.h"
#include "game/system/naming_census.h"
#include "game/system/settings_case_l10n.h"
#include "game/system/touch_screen.h"
#include "game/system/npc_flicker.h"
#include "game/graphics/opengl_renderer/loader/ManagedAssets.h"
#include "game/graphics/opengl_renderer/GrassOccluders.h"
#include "game/graphics/opengl_renderer/hdr_output.h"
// Registre de matieres PBR (en-tete SANS GL, le noyau peut l'inclure). lighting-legacy-purge
// (2026-09-11) : l'ecrivain de `pbr_tan_diag.txt` vivait dans `pc_set_pbr_isolate`, supprime avec
// la rangee PBR ISOLATE ; les sections de diagnostic (POM, couverture, reach) existent toujours
// dans ce module et n'ont plus d'appelant.
#include "game/graphics/opengl_renderer/loader/CustomTextureReplacements.h"
#include "game/graphics/sceGraphicsInterface.h"
#include "game/kernel/common/fileio.h"
#include "game/kernel/common/kboot.h"
#include "game/kernel/common/kdgo.h"
#include "game/kernel/common/kdsnetm.h"
#include "game/kernel/common/kernel_types.h"
#include "game/kernel/common/klink.h"
#include "game/kernel/common/kmachine.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/ksocket.h"
#include "game/kernel/common/ksound.h"
#include "game/kernel/common/memory_layout.h"
#include "game/kernel/jak1/kboot.h"
#include "game/kernel/jak1/kdgo.h"
#include "game/kernel/jak1/klisten.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/kernel/jak1/ksound.h"
#include "game/sce/deci2.h"
#include "game/system/pad_replay.h"
#include "game/system/boot_replay.h"
#include "game/sce/libcdvd_ee.h"
#include "game/sce/libdma.h"
#include "game/sce/libgraph.h"
#include "game/sce/sif_ee.h"
#include "game/sce/stubs.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>

#include "common/util/font/font_utils.h"
#if defined(__ANDROID__) || defined(__linux__)
#include <unistd.h>  // fsync (Gcollision-glitchcapture dump durability)
#endif
#if defined(__ANDROID__)
#include <android/log.h>  // [CC] trigger line -> GK_STDOUT logcat (live supervisor monitoring)
#include <sys/system_properties.h>
// Gcrash-swamp-load (debug-only): arm the signal-handler repair bypass, defined
// in android/gk_android_main.cpp. Called from diag_flags_maybe(); OFF by default.
extern "C" void gk_set_diag_norepair(bool on);
#endif
AUTOPORT_FEATURE_SITE("title-tap-prompt-regression");
AUTOPORT_FEATURE_SITE("mesh-browser-removal");
AUTOPORT_FEATURE_SITE("lighting-legacy-purge");
AUTOPORT_FEATURE_SITE("dead-follow-probe");

using namespace ee;

#ifdef OG_FEAT_HD_MODELS
// Grecharged-hd-models4: per-actor coverage registry, DEFINED at GLOBAL scope in Merc2.cpp
// (prototypes here rather than including the GL renderer headers in this kernel TU). Declared
// BEFORE namespace jak1 — an in-namespace declaration makes the calls below reference
// jak1::merc2_hd_* and the link fails (attempt-1 failure of this phase).
void merc2_hd_cover(u32 companion_pid, u32 driver_pid);
void merc2_hd_uncover(u32 companion_pid);
// Ghd-skin-origin-stretch : la moitie GPU du compte de la porte (os consommes hors de la pose
// commandee, hors d'echelle, ou differents de ce que GOAL a ecrit) et sa decomposition. Meme
// regle de portee que les deux prototypes ci-dessus : DEHORS de `namespace jak1`.
u64 merc2_hd_stretch_verdict();
u64 merc2_hd_stretch_diag(int which);
// Ghd-skin-origin-stretch : registre du rig HD (parent, joint pilote, mode de reciblage et
// position de bind par joint) pour les sondes HDSKINLEN / HDCMD de Merc2 — meme regle de portee
// que les deux prototypes ci-dessus.
void merc2_hd_skel_joint(u32 companion_pid,
                         int k,
                         int parent,
                         int e,
                         int mode,
                         float bx,
                         float by,
                         float bz);
void merc2_hd_skel_forget(u32 companion_pid);
// Ghd-skin-origin-stretch : l'anneau GOAL (ce que le squelette a ECRIT par joint et par image)
// et l'emplacement d'un compagnon dedans — sonde HDRING de Merc2.
void merc2_hd_ring(u32 ring_addr, u32 cam_addr, u32 stamp_addr);
void merc2_hd_ring_slot(u32 companion_pid, int slot);
// recharged-secondary-motion : les joints que le solveur de chaines ECRIT, et la grandeur que
// la porte lit (echelle recue par la chair sur la t-mtx CONSOMMEE). Meme regle de portee que
// les prototypes ci-dessus : DEHORS de `namespace jak1`.
void merc2_hd_phys_joint(u32 companion_pid, int k, int on);
u64 merc2_sm_diag(int which);
#endif

// Grecharged-foliage-wind3 : la cadence du vent natif, rapportee par `update-wind-ticks!` au
// renderer. Declaration en avant plutot qu'un `#include` : foliage_wind.h tire
// `pipelines/opengl.h`, que le noyau n'a aucune raison de connaitre ; un desaccord de signature
// sort au LIEN, pas a l'execution. Au SCOPE GLOBAL : `foliage_wind` n'est pas dans `jak1`.
namespace foliage_wind {
void note_wind_rate(float ratio, int steps);
}  // namespace foliage_wind

namespace jak1 {

/*!
 * Initialize global variables based on command line parameters. Not called in retail versions,
 * but it is present in the ELF.
 * DONE
 * Modified to use std::string, and removed call to fflush.
 */
void InitParms(int argc, const char* const* argv) {
  // Modified default settings:
  if (argc == 1) {
    DiskBoot = 1;
    isodrv = fakeiso;
    modsrc = 0;
    reboot_iop = 0;
    DebugSegment = 0;
    MasterDebug = 0;
  }

  for (int i = 1; i < argc; i++) {
    std::string arg = argv[i];
    // DVD Settings
    // ----------------------------

    // the "cd" mode uses the DVD drive for everything. This is how the game runs in retail
    if (arg == "-cd") {
      Msg(6, "dkernel: cd mode\n");
      isodrv = iso_cd;  // use the actual DVD drive for data files
      modsrc = 1;       // use the DVD drive data for IOP modules
      reboot_iop = 1;   // Reboot the IOP (load new IOP runtime)
    }

    // the "cddata" uses the DVD drive for everything but IOP modules.
    if (arg == "-cddata") {
      Msg(6, "dkernel: cddata mode\n");
      isodrv = iso_cd;  // tell IOP to use actual DVD drive for data files
      modsrc = 0;       // don't use DVD drive for IOP modules
      reboot_iop = 0;   // no need to reboot the IOP
    }

    // the "deviso" mode is one of two modes for testing without the need for DVDs
    if (arg == "-deviso") {
      Msg(6, "dkernel: deviso mode\n");
      isodrv = deviso;  // IOP deviso mode
      modsrc = 0;       // no IOP module loading (there's no DVD to load from!)
      reboot_iop = 0;
    }

    // the "fakeiso" mode is the other of two modes for testing without the need for DVDs
    if (arg == "-fakeiso") {
      Msg(6, "dkernel: fakeiso mode\n");
      isodrv = fakeiso;  // IOP fakeeiso mode
      modsrc = 0;        // no IOP module loading (there's no DVD to load from!)
      reboot_iop = 0;
    }

    // an added mode to allow booting without a KERNEL.CGO for testing
    if (arg == "-nokernel") {
      Msg(6, "dkernel: no kernel mode\n");
      MasterUseKernel = false;
    }

    // an added mode to allow booting without sound for testing
    if (arg == "-nosound") {
      Msg(6, "dkernel: no sound mode\n");
      masterConfig.disable_sound = true;
    }

    // added in pc port to skip the splash screen
    if (arg == "-nosplash") {
      Msg(6, "dkernel: skipping splash screen\n");
      SplashScreen = false;
    }

    // GOAL Settings
    // ----------------------------

    // the "demo" mode is used to pass the message "demo" to the gkernel in the DebugBootMessage
    // (instead of play)
    if (arg == "-demo") {
      Msg(6, "dkernel: demo mode\n");
      kstrcpy(DebugBootMessage, "demo");
    }

    // the "boot" mode is used to set GOAL up for running the game in retail mode
    if (arg == "-boot") {
      Msg(6, "dkernel: boot mode\n");
      MasterDebug = 0;
      DiskBoot = 1;
      DebugSegment = 0;
    }

    // the "debug" mode is used to set GOAL up for debugging/development
    if (arg == "-debug") {
      Msg(6, "dkernel: debug mode\n");
      MasterDebug = 1;
      DebugSegment = 1;
      // disable splash in debug
      SplashScreen = 0;
    }

    // the "debug-mem" mode is used to set up GOAL in debug mode, but not to load debug-segments
    if (arg == "-debug-mem") {
      Msg(6, "dkernel: debug-mem mode\n");
      MasterDebug = 1;
      DebugSegment = 0;
    }

    // the "-level [level-name]" mode is used to inform the game to boot a specific level
    // the default level is "#f".
    if (arg == "-level") {
      i++;
      std::string levelName = argv[i];
      Msg(6, "dkernel: level %s\n", levelName.c_str());
      kstrcpy(DebugBootLevel, levelName.c_str());
    }
  }
}

/*!
 * Initialize the I/O Processor
 * Removed calls to exit(0) if loading modules fails.
 */
void InitIOP() {
  // before doing anything with the I/O Processor, we need to set up SIF RPC
  sceSifInitRpc(0);

  if ((isodrv == iso_cd) || modsrc || reboot_iop) {
    // we will need the DVD drive to bring up the IOP
    InitCD();
  }

  if (!reboot_iop) {
    // reboot with development IOP kernel
    lg::debug("Rebooting IOP...");
    while (!sceSifRebootIop("host0:/usr/local/sce/iop/modules/ioprp221.img")) {
      lg::debug("Failed, retrying");
    }
    while (!sceSifSyncIop()) {
      lg::debug("Syncing...");
    }
  } else {
    // reboot with IOP kernel off of the disk
    // reboot with development IOP kernel
    lg::debug("Rebooting IOP...");
    while (!sceSifRebootIop("cdrom0:\\DRIVERS\\IOPRP221.IMG;1")) {
      lg::debug("Failed, retrying");
    }
    while (!sceSifSyncIop()) {
      lg::debug("Syncing...");
    }
  }

  // now that the IOP is booted with the correct kernel, we need to connect SIF RPC again
  sceSifInitRpc(0);

  // if we plan to get files off of the DVD drive, we get ready to load files again.
  // resetting the file system may not be needed here, but it does not hurt.
  if ((isodrv == iso_cd) || modsrc) {
    InitCD();
    sceFsReset();
  }

  // we begin putting together a boot command for OVERLORD, the IOP driver, which must know the data
  // source and the name of the boot splash screen of the game.
  char overlord_boot_command[256];
  char* cmd = overlord_boot_command;
  kstrcpy(cmd, init_types[(int)isodrv]);
  cmd = cmd + strlen(cmd) + 1;
  kstrcpy(cmd, "SCREEN1.USA");
  cmd = cmd + strlen(cmd) + 1;
  if (masterConfig.disable_sound) {
    kstrcpy(cmd, "-nosound");
    cmd = cmd + strlen(cmd) + 1;
  }

  int total_len = cmd - overlord_boot_command;

  if (modsrc == fakeiso) {
    // load from network

    if (sceSifLoadModule("host0:/usr/local/sce/iop/modules/sio2man.irx", 0, nullptr) < 0) {
      MsgErr("loading sio2man.irx failed\n");
    }

    if (sceSifLoadModule("host0:/usr/local/sce/iop/modules/padman.irx", 0, nullptr) < 0) {
      MsgErr("loading padman.irx failed\n");
    }

    if (sceSifLoadModule("host0:/usr/local/sce/iop/modules/libsd.irx", 0, nullptr) < 0) {
      MsgErr("loading libsd.irx failed\n");
    }

    if (sceSifLoadModule("host0:/usr/local/sce/iop/modules/mcman.irx", 0, nullptr) < 0) {
      MsgErr("loading mcman.irx failed\n");
    }

    if (sceSifLoadModule("host0:/usr/local/sce/iop/modules/mcserv.irx", 0, nullptr) < 0) {
      MsgErr("loading mcserv.irx failed\n");
    }

    if (sceSifLoadModule("host0:/usr/home/src/989snd10/iop/989snd.irx", 0, nullptr) < 0) {
      MsgErr("loading 989snd.irx failed\n");
    }

    sceSifLoadModule("host0:/usr/home/src/989snd10/iop/989ERR.IRX", 0, nullptr);

    lg::debug("Initializing CD library...");
    auto rv = sceSifLoadModule("host0:binee/overlord.irx", total_len, overlord_boot_command);
    if (rv < 0) {
      MsgErr("loading overlord.irx failed\n");
    }
  } else {
    // load from DVD drive
    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\SIO2MAN.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading sio2man.irx failed\n");
    }

    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\PADMAN.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading padman.irx failed\n");
    }

    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\LIBSD.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading libsd.irx failed\n");
    }

    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\MCMAN.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading mcman.irx failed\n");
    }

    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\MCSERV.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading mcserv.irx failed\n");
    }

    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\989SND.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading 989snd.irx failed\n");
    }

    lg::debug("Initializing CD library in ISO_CD mode...");
    auto rv =
        sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\OVERLORD.IRX;1", total_len, overlord_boot_command);
    if (rv < 0) {
      MsgErr("loading overlord.irx failed\n");
    }
  }
  auto rv = sceMcInit();
  if (rv < 0) {
    MsgErr("MC driver init failed %d\n", rv);
  } else {
    lg::info("InitIOP OK");
  }
}

AutoSplitterBlock g_auto_splitter_block_jak1;

// GENERAL crash-loop guard: a persisted setting must NEVER brick the game. A sentinel file
// ("recharged-boot-guard") next to settings.ini holds a consecutive-unhealthy-boot count. At
// boot we bump it; if it already reached 2 (two boots that died before reaching healthy
// gameplay) nous le CONSIGNONS : plus aucun reglage persistant n'est capable de bloquer
// l'amorcage, et la remise d'aplomb qui visait `pbr-test-preset` est partie avec ce reglage.
// After 60s of healthy running the sentinel is deleted so a normal session never trips it. Mirrors the AO-specific
// ao-boot-guard style (fs::* via ghc + file_util text IO) but is a distinct GENERAL guard.
namespace {
constexpr double kRechargedGuardHealthySecs = 60.0;
fs::path recharged_boot_guard_path() {
  return file_util::get_user_settings_dir(g_game_version) / "recharged-boot-guard";
}
fs::path recharged_settings_ini_path() {
  return file_util::get_user_settings_dir(g_game_version) / "settings.ini";
}
// lighting-legacy-purge (2026-09-11) : `s_recharged_guard_tripped` est SUPPRIME. Son UNIQUE
// lecteur etait `pc_set_pbr_displacement`, qui refusait la valeur risquee pour la session ; le
// reglage n'existe plus. La garde continue de REMETTRE settings.ini d'aplomb au bootage.
double s_recharged_boot_t = -1.0;            // steady_clock boot time (for the healthy clear)
// lighting-legacy-purge (2026-09-11) : `recharged_reset_risky_ini` est SUPPRIMEE. Elle
// reecrivait la ligne `pbr-test-preset = <n>` de settings.ini vers sa valeur par defaut. Or
// `pbr-test-preset` est un reglage de l'ancien monde : il n'a plus de rangee, plus de champ, et
// sa clause de lecture dans pckernel.gc:526 est une PIERRE TOMBALE qui consomme la valeur et la
// jette. Remettre a « 1 » une valeur que plus personne ne lit ne protege de rien — mais la ligne
// de journal, elle, nommait un reglage retire comme s'il pilotait encore quelque chose, et elle
// a ete VUE : la course d'appareil du 2026-09-11 03:31 l'a emise. C'est un faux filet de
// securite, et le livrable demande que l'ancien monde SORTE du code, pas qu'il soit debranche.
//
// La garde generale, elle, reste ENTIERE : c'est elle qui compte les demarrages morts avant le
// jeu. Le jour ou un reglage persistant redevient capable de bloquer l'amorcage, c'est ici que
// sa remise d'aplomb se rebranche — et elle nommera CE reglage-la.
// Boot-time crash-loop check. Runs from InitMachine (after the Android external game-root is set
// by goal_main, before GOAL boots and loads settings.ini).
// UNE COURSE DE REFERENCE NE MODIFIE PAS LES REGLAGES QU'ELLE MESURE.
// `lighting-origin-bitexact`, 2026-09-07. Cette garde compte les demarrages « morts avant le
// jeu » dans un fichier a cote de `settings.ini`, et au DEUXIEME elle REECRIVAIT `settings.ini`
// (cette reecriture est partie avec le reglage qu'elle visait, lighting-legacy-purge 2026-09-11 ;
// la garde continue d'ECRIRE son fichier sentinelle). Or une course `refset` est toujours
// tuee au bout de son plan : elle n'atteint jamais les 60 s « saines » qui effacent le
// sentinelle, donc trois courses successives suffisent a faire changer les reglages SOUS la
// comparaison. Mesure : sentinelle a 2 et `settings.ini` reecrit a 01:31:38 entre deux rejeux
// du meme plan ; l'ecart est passe de 1242 a 100172 pixels sans qu'une seule ligne du chemin de
// dessin ait bouge. Un instrument bit-a-bit ne peut pas vivre avec ca : sous `OG_REFSET` la
// garde ne lit rien et n'ecrit rien. Le joueur, lui, la garde entiere.
bool refset_pins_settings() {
  static const bool s_on = [] {
#if defined(__ANDROID__)
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.refset", buf) > 0 && buf[0]) {
      return std::string(buf) == "capture" || std::string(buf) == "replay";
    }
    return false;
#else
    const char* e = std::getenv("OG_REFSET");
    return e && (std::string(e) == "capture" || std::string(e) == "replay");
#endif
  }();
  return s_on;
}

void recharged_crash_loop_guard_boot() {
  if (refset_pins_settings()) {
    return;
  }
  s_recharged_boot_t =
      std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
  const auto guard = recharged_boot_guard_path();
  int c = 0;
  if (file_util::file_exists(guard.string())) {
    try {
      c = std::stoi(file_util::read_text_file(guard));
    } catch (...) {
      c = 0;  // unparseable -> treat as fresh
    }
  }
  if (c >= 2) {
    lg::warn(
        "[recharged] crash-loop guard: 2 consecutive boots died before gameplay. Aucun reglage "
        "persistant n'est aujourd'hui capable de bloquer l'amorcage : rien n'est reecrit.");
    try {
      file_util::write_text_file(guard, "1");  // count this boot as unhealthy until it survives
    } catch (...) {
    }
  } else {
    try {
      file_util::write_text_file(guard, std::to_string(c + 1));
    } catch (...) {
    }
  }
}
}  // namespace

/*!
 * Initialize GOAL Runtime. This is the main initialization which is called before entering
 * the GOAL kernel dispatch loop (KernelCheckAndDispatch).
 * TODO finish up things which are commented.
 */
int InitMachine() {
  // GENERAL crash-loop guard: bump/inspect the boot sentinel BEFORE GOAL boots and loads
  // settings.ini. On Android the external game-root (which decides where the settings dir is)
  // is already set by goal_main before InitMachine runs, so the path is final here.
  recharged_crash_loop_guard_boot();

  u32 debug_heap_end = (0xffffffff - DEBUG_HEAP_SPACE_FOR_STACK + 1) & 0x7ffffff;

  // initialize the global heap
  u32 global_heap_size = GLOBAL_HEAP_END - HEAP_START;
  float size_mb = ((float)global_heap_size) / (float)(1 << 20);
  lg::info("gkernel: global heap 0x{:08x} to 0x{:08x} (size {:.3f} MB)", HEAP_START,
           GLOBAL_HEAP_END, size_mb);
  kinitheap(kglobalheap, Ptr<u8>(HEAP_START), global_heap_size);

  // initialize the debug heap, if appropriate
  if (MasterDebug) {
    u32 debug_heap_size = debug_heap_end - DEBUG_HEAP_START;
    kinitheap(kdebugheap, Ptr<u8>(DEBUG_HEAP_START), debug_heap_size);
    float debug_size_mb = ((float)debug_heap_size) / (float)(1 << 20);
    float gap_size_mb = ((float)DEBUG_HEAP_START - GLOBAL_HEAP_END) / (float)(1 << 20);
    lg::info("gkernel: debug heap 0x{:08x} to 0x{:08x} (size {:.3f} MB, gap {:.3f} MB)",
             DEBUG_HEAP_START, debug_heap_end, debug_size_mb, gap_size_mb);
  } else {
    // if no debug, we make the kheapinfo structure NULL so GOAL knows not to use it.
    kdebugheap.offset = 0;
  }

  init_output();    // GOAL input/output buffer setup
  jak1::InitIOP();  // start IOP/OVERLORD, loading our legal splash screen

  // sceGsResetPath(); // reset VIF1, VU1, GIF

  InitVideo();  // display legal splash screen

  // FlushCache(WRITEBACK_DCACHE);
  // FlushCache(INVALIDATE_ICACHE);
  // sceGsSyncV(0);   // wait for it to show up on the screen
  //
  // if(scePadInit(0) != 1) { // init controllers
  //   MsgErr("dkernel: !init pad\n");
  // }

  if (MasterDebug) {  // connect to GOAL compiler
    InitGoalProto();
  } else {
    // shut down the deci2 stuff, we don't need it.
    ee::sceDeci2Disable();
  }

  lg::info("InitSound");
  InitSound();  // do nothing!
  lg::info("InitRPC");
  InitRPC();       // connect to IOP
  reset_output();  // reset output buffers
  clear_print();

  s32 goal_status = InitHeapAndSymbol();  // init GOAL runtime, load kernel and engine
  if (goal_status < 0) {
    return goal_status;
  }

  // TODO - better place to put this?
  // TODO - yes, see jak2's code!
  g_auto_splitter_block_jak1.pointer_to_symbol =
      (u64)g_ee_main_mem + intern_from_c("*autosplit-info-jak1*")->value;

  lg::info("InitListenerConnect");
  InitListenerConnect();
  lg::info("InitCheckListener");
  InitCheckListener();
  Msg(6, "kernel: machine started\n");
  return 0;
}

/*!
 * Shutdown the runtime.
 */
int ShutdownMachine() {
  StopIOP();
  CloseListener();
  ShutdownSound();
  ShutdownGoalProto();

  Msg(6, "kernel: machine shutdown\n");
  return 0;
}

/*!
 * Open a file-stream.  Name is a GOAL string. Mode is a GOAL symbol.  Use 'read for readonly
 * and anything else for write only.
 */
u64 kopen(u64 fs, u64 name, u64 mode) {
  auto file_stream = Ptr<FileStream>(fs).c();
  file_stream->mode = mode;
  file_stream->name = name;
  file_stream->flags = 0;
  lg::print("****** CALL TO kopen() ******\n");
  // sprintf(buffer, "host:%s", Ptr<String>(name)->data());
  if (!strcmp(info(Ptr<Symbol>(mode))->str->data(), "read")) {
    file_stream->file = sceOpen(Ptr<String>(name)->data(), SCE_RDONLY);
  } else {
    // 0x602
    file_stream->file = sceOpen(Ptr<String>(name)->data(), SCE_TRUNC | SCE_CREAT | SCE_WRONLY);
  }

  return fs;
}

void PutDisplayEnv(u32 ptr) {
  // we can mostly ignore this, except for one value that sets the 'blackout' amount.
  u8 alp = Ptr<u8>(ptr).c()[1];
  auto* renderer = Gfx::GetCurrentRenderer();
  if (renderer) {
    renderer->set_pmode_alp(alp / 255.f);
  }
}

void update_discord_rpc(u32 discord_info) {
  if (gDiscordRpcEnabled) {
    DiscordRichPresence rpc;
    char state[128];
    char large_image_key[128];
    char large_image_text[128];
    char small_image_key[128];
    char small_image_text[128];
    auto info = discord_info ? Ptr<DiscordInfo>(discord_info).c() : NULL;
    if (info) {
      int cells = (int)*Ptr<float>(info->fuel).c();
      int orbs = (int)*Ptr<float>(info->money_total).c();
      int scout_flies = (int)*Ptr<float>(info->buzzer_total).c();
      int deaths = *Ptr<int>(info->deaths).c();
      float time = *Ptr<float>(info->time_of_day).c();
      auto cutscene = Ptr<Symbol>(info->cutscene)->value;
      auto ogreboss = Ptr<Symbol>(info->ogreboss)->value;
      auto plantboss = Ptr<Symbol>(info->plantboss)->value;
      auto racer = Ptr<Symbol>(info->racer)->value;
      auto flutflut = Ptr<Symbol>(info->flutflut)->value;
      char* status = Ptr<String>(info->status).c()->data();
      char* level = Ptr<String>(info->level).c()->data();
      const char* full_level_name =
          get_full_level_name(level_names, level_name_remap, Ptr<String>(info->level).c()->data());
      memset(&rpc, 0, sizeof(rpc));
      if (!indoors(indoor_levels, level)) {
        char level_with_tod[128];
        strcpy(level_with_tod, level);
        strcat(level_with_tod, "-");
        strcat(level_with_tod, time_of_day_str(time));
        strcpy(large_image_key, level_with_tod);
      } else {
        strcpy(large_image_key, level);
      }
      strcpy(large_image_text, full_level_name);
      if (!strcmp(full_level_name, "unknown")) {
        strcpy(large_image_key, full_level_name);
        strcpy(large_image_text, level);
      }
      rpc.largeImageKey = large_image_key;
      if (!strcmp(level, "finalboss")) {
        strcpy(state, "Fighting Final Boss");
      } else if (plantboss != offset_of_s7()) {
        strcpy(state, "Fighting Dark Eco Plant");
        rpc.largeImageKey = "plant-boss";
        strcpy(large_image_text, "Dark Eco Plant");
      } else if (ogreboss != offset_of_s7()) {
        strcpy(state, "Fighting Klaww");
        rpc.largeImageKey = "ogreboss";
        strcpy(large_image_text, "Klaww");
      } else if (!strcmp(level, "title")) {
        strcpy(state, "On title screen");
        rpc.largeImageKey = "title";
        strcpy(large_image_text, "Title screen");
      } else if (!strcmp(level, "intro")) {
        strcpy(state, "Intro");
      } else if (cutscene != offset_of_s7()) {
        strcpy(state, "Watching a cutscene");
        strcpy(large_image_text, fmt::format("Cells: {} | Orbs: {} | Flies: {} | Deaths: {}",
                                             std::to_string(cells), std::to_string(orbs),
                                             std::to_string(scout_flies), std::to_string(deaths))
                                     .c_str());
      } else {
        strcpy(state, fmt::format("Cells: {} | Orbs: {} | Flies: {}", std::to_string(cells),
                                  std::to_string(orbs), std::to_string(scout_flies))
                          .c_str());

        strcat(large_image_text, fmt::format(" | Deaths: {}", std::to_string(deaths)).c_str());
      }
      rpc.largeImageText = large_image_text;
      rpc.state = state;
      if (racer != offset_of_s7()) {
        strcpy(small_image_key, "target-racer");
        strcpy(small_image_text, "Driving A-Grav Zoomer");
      } else if (flutflut != offset_of_s7()) {
        strcpy(small_image_key, "flutflut");
        strcpy(small_image_text, "Riding on Flut Flut");
      } else {
        if (!indoors(indoor_levels, level)) {
          strcpy(small_image_key, time_of_day_str(time));
          strcpy(small_image_text, "Time of day: ");
          strcat(small_image_text, get_time_of_day(time).c_str());
        } else {
          strcpy(small_image_key, "");
          strcpy(small_image_text, "");
        }
      }
      rpc.smallImageKey = small_image_key;
      rpc.smallImageText = small_image_text;
      rpc.startTimestamp = gStartTime;
      rpc.details = status;
      rpc.partySize = 0;
      rpc.partyMax = 0;
      Discord_UpdatePresence(&rpc);
    }
  } else {
    Discord_ClearPresence();
  }
}

void pc_set_levels(u32 l0, u32 l1) {
  if (!Gfx::GetCurrentRenderer()) {
    return;
  }
  std::string l0s = Ptr<String>(l0).c()->data();
  std::string l1s = Ptr<String>(l1).c()->data();

  std::vector<std::string> levels;
  if (l0s != "none" && l0s != "#f") {
    levels.push_back(l0s);
  }

  if (l1s != "none" && l1s != "#f") {
    levels.push_back(l1s);
  }

  Gfx::GetCurrentRenderer()->set_levels(levels);
}

// Gplayability-input-and-loadgate (owner 2026-08-27): the missing RETURN channel.
// `__pc-set-levels` above tells the renderer what GOAL wants; until now nothing
// ever told GOAL what the renderer actually HAS. A cutscene therefore starts its
// audio stream — which is the scene's master clock, see loader.gc — against a
// level that can still be tens of seconds from being drawable. Measured on the
// owner's Shield: the Geyser Rock return fly-over began 41.9 s before `beach`
// was drawable. These two let GOAL hold the scene until the picture can exist.
// Both are fail-open: see game/system/load_gate.h.
s32 pc_scene_ready(u32 scene, u32 lev0, u32 lev1, s32 timeout_ms) {
  const char* sc = scene ? Ptr<String>(scene).c()->data() : nullptr;
  const char* l0 = lev0 ? Ptr<String>(lev0).c()->data() : nullptr;
  const char* l1 = lev1 ? Ptr<String>(lev1).c()->data() : nullptr;
  return load_gate::scene_ready(sc, l0, l1, timeout_ms);
}

void pc_scene_release(u32 scene) {
  load_gate::scene_release(scene ? Ptr<String>(scene).c()->data() : nullptr);
}

// Gcutscene-npc-flicker (owner 2026-08-31) — le RECENSEMENT des PNJ pendant une cinematique.
// Voir game/system/npc_flicker.h : la garde precedente (`[hd-flicker] blackouts=`) etait un zero
// de compilation, et elle ne voyait de toute facon que les acteurs COUVERTS par un modele HD.
// Ces trois ponts publient, cote GOAL, les deux choses que le rendu ne peut pas connaitre :
// l'EXISTENCE de l'acteur dans l'arbre de processus et son octet draw-status.
void pc_npc_census_begin(u32 scene) {
  npc_flicker::begin_census(scene ? Ptr<String>(scene).c()->data() : nullptr);
}

// `in_fov` (Gcutscene-npc-flicker-2) : verdict INDEPENDANT de position. Le moteur cull sur
// `draw origin + draw bounds` ; ce parametre porte le meme test de frustum applique a
// `root trans`, l'autre source de position de l'acteur. Voir game/system/npc_flicker.h.
void pc_npc_census_actor(u32 merc_name,
                         u32 pid,
                         u32 draw_status,
                         s32 level_active,
                         s32 in_fov,
                         s32 is_npc) {
  const char* nm = merc_name ? Ptr<String>(merc_name).c()->data() : nullptr;
  npc_flicker::census_actor(nm, nm, pid, draw_status, level_active, in_fov, is_npc);
}

// Grecharged-foliage-wind3 — LA CADENCE DU VENT NATIF, RAPPORTEE PAR SON PRODUCTEUR.
// `update-wind-ticks!` (engine/gfx/background/wind.gc) appelle ceci une fois par tour de
// `display-loop` : `ratio` = `(-> *display* time-adjust-ratio)`, ce que l'image vaut en 1/60 s de
// TEMPS DE JEU ; `steps` = le nombre d'appels a `update-wind` reellement faits. Le verdict (1) de
// foliage-wind compare les deux sommes. Declaration en avant plutot qu'un `#include` :
// foliage_wind.h tire `pipelines/opengl.h`, que le noyau n'a aucune raison de connaitre ; un
// desaccord de signature sort au LIEN, pas a l'execution.
// GOAL passe un `float` a une fonction C comme un MOTIF DE BITS dans un registre entier (meme
// convention que `pc_set_axis_scale`, kernel/common/kmachine.cpp:951). Prendre un `float` en
// parametre ferait lire xmm0, ou GOAL n'a rien mis : mesure du 2026-09-05, ratio lu = 0,000 et
// `steps` = 1065353216 (= le motif de bits de 1,0f, decale d'un registre) — 9587 images
// rapportees, aucune mesurable.
void pc_wind_note_rate(u32 ratio_bits, u32 steps) {
  float ratio;
  std::memcpy(&ratio, &ratio_bits, sizeof(ratio));
  ::foliage_wind::note_wind_rate(ratio, (int)steps);
}

// Une image de plus, publiee par le compteur que `lib/proof_run.sh` moissonne. Appelee du meme
// point que le recensement (post-sync-draw), c'est-a-dire une fois par image RENDUE.
// Defini plus bas, apres `level_warp_run` dont il reutilise le trampoline.
static void refset_rewarp_maybe();
// perf-stock-baseline : defini plus bas, apres `level_warp_run` dont il reutilise le tremplin.
static void perf_baseline_warp_maybe();

// lighting-hdr essai 4 — LE PLAN DU JEU DE REFERENCES SE CADENCE SUR LA FRAME DE LOGIQUE.
// `pc_autoport_frame` tourne une fois par image RENDUE. Le piege est deja nomme plus bas pour
// l'ancre du premier warp (`level_warp_run`), mais il restait entier pour les deux autres
// consommateurs du plan. Mesure du 2026-09-06 sur eae4df44, meme .so et memes proprietes dans
// les deux courses : `REFSET start lf=902` a la capture contre `lf=903` au rejeu, puis une ancre
// de re-teleport a 906 contre 908. Sur `origine/h00`, 18766 pixels sur 57600 differents (32,6 %)
// pour un meilleur recalage entier de dx=0 dy=0 — donc pas la camera, la PHASE d'animation.
// `refset::begin_logic_frame` de-double sur la frame de logique, donc cet appel-ci reste comme
// REPLI (course sans harnais de rejeu d'entrees) sans jamais compter deux fois.
static void refset_pump(bool from_logic) {
  if (!refset::begin_logic_frame(from_logic)) {
    return;
  }
  refset_rewarp_maybe();
  refset::tick();
}

// ================== dead-follow-probe : recensement du reglage MORT « ENV PROBE » ===========
// Le champ `recharged_follow_probe` (gfx.h) etait ecrit par `pc_set_follow_probe` et lu par
// PERSONNE : son unique consommateur, FollowProbe.cpp, a disparu avec SPEC-refonte-lumiere §2.4,
// et sa rangee de menu ENV PROBE a ete retiree le 2026-09-02. Ce recensement ne juge rien et ne
// change aucun comportement : il PUBLIE combien de traces du reglage survivent.
//
// Deux grandeurs, parce qu'un nettoyage a moitie fait se lit a DEUX endroits differents :
//
//   * `dead_probe_cpp_field` — la struct C++ porte-t-elle encore le champ ? La reponse est
//     calculee PAR LE COMPILATEUR sur la vraie declaration (idiome de detection SFINAE). Elle ne
//     peut pas etre « verte par inaction » : re-ajouter le champ a gfx.h la remet a 1 sans qu'une
//     seule ligne d'ici ne bouge.
//   * `dead_probe_symbols` — combien de symboles GOAL de la famille ENV PROBE / follow-probe
//     vivent encore dans la table du runtime. C'est une lecture de l'image REELLEMENT CHARGEE
//     (GAME.CGO + ENGINE.CGO), pas du source : un `pc-set-follow-probe!` toujours enregistre par
//     ce fichier, ou un `*carousell-follow-probe*` toujours defini par progress-pc.gc, s'y voit.
//
// Le motif est la FAMILLE de ce reglage, jamais le mot « probe » seul : jak1 porte des dizaines
// de symboles `collide-probe*`, `*anim-probe-*`, `cutscene-*-probe` qui n'ont rien a voir et
// rendraient la porte inatteignable.
//
// La table se remplit au fil des DGO charges : on repasse periodiquement et on garde le MAXIMUM
// vu, pour qu'une apparition tardive ne puisse pas etre lavee par une passe propre. On publie
// aussi le denominateur (symboles balayes / connus du noyau) : sans lui, `dead_probe_sites=0`
// est aussi ce que rendrait une table vide ou non initialisee.
namespace {
template <typename T, typename = void>
struct HasDeadFollowProbeField : std::false_type {};
template <typename T>
struct HasDeadFollowProbeField<T, std::void_t<decltype(std::declval<T&>().recharged_follow_probe)>>
    : std::true_type {};

constexpr const char* kDeadProbeNamePatterns[] = {"follow-probe", "follow_probe", "followprobe",
                                                  "envprobe", "env-probe"};
}  // namespace

static void dead_probe_census() {
  static u32 s_worst = 0;
  static u32 s_passes = 0;
  static std::string s_worst_names;

  u32 live = 0;
  u32 scanned = 0;
  std::string names;
  if (SymbolTable2.offset && LastSymbol.offset) {
    // Pas de 8 octets : c'est le pas REEL de la table (find_symbol_in_area, kscheme.cpp:1305).
    for (u32 slot = SymbolTable2.offset; slot < LastSymbol.offset; slot += 8) {
      auto sym = Ptr<Symbol>(slot);
      if (!info(sym)->hash) {
        continue;  // slot jamais occupe
      }
      u32 stro = info(sym)->str.offset;
      if (!stro || stro >= (u32)EE_MAIN_MEM_SIZE - 128) {
        continue;
      }
      const char* nm = reinterpret_cast<const char*>(Ptr<u8>(stro + 4).c());
      size_t nlen = strnlen(nm, 96);
      if (!nlen || nlen >= 96) {
        continue;
      }
      scanned++;
      for (const char* pat : kDeadProbeNamePatterns) {
        if (strstr(nm, pat)) {
          live++;
          if (names.size() < 180) {
            if (!names.empty()) {
              names += ',';
            }
            names += nm;
          }
          break;
        }
      }
    }
  }
  s_passes++;
  if (live >= s_worst) {
    s_worst = live;
    s_worst_names = names;
  }

  constexpr u32 cpp_field = HasDeadFollowProbeField<GfxGlobalSettings>::value ? 1u : 0u;
  autoport_proof::note_hit_for("dead-follow-probe", 1);
  autoport_proof::publish("dead_probe_cpp_field", cpp_field);
  autoport_proof::publish("dead_probe_symbols", s_worst);
  autoport_proof::publish("dead_probe_sites", cpp_field + s_worst);
  autoport_proof::publish("dead_probe_symbols_scanned", scanned);
  autoport_proof::publish("dead_probe_symbols_known", NumSymbols < 0 ? 0 : (u64)NumSymbols);
  autoport_proof::publish("dead_probe_passes", s_passes);
  // Une cle de TEXTE ne se vide jamais toute seule : liste vide => on publie "-", sinon la
  // derniere liste non vide resterait a cote d'un compte a zero.
  autoport_proof::publish_text("dead_probe_symbol_names",
                               s_worst_names.empty() ? "-" : s_worst_names.c_str());
  // Le regime de la feature : le champ mort vit sous OG_FEAT_PBR. Un binaire compile sans ce
  // drapeau rendrait 0 sans avoir rien nettoye — la preuve doit dire lequel des deux elle decrit.
#ifdef OG_FEAT_PBR
  autoport_proof::publish("dead_probe_build_pbr", 1);
#else
  autoport_proof::publish("dead_probe_build_pbr", 0);
#endif
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// lighting-legacy-purge : LE RECENSEMENT DES REGLAGES D'ECLAIRAGE DE L'ANCIEN MONDE.
//
// POURQUOI. L'owner (10/09) : « Modele d'ambiance, Materiaux PBR, Force de l'ambiance, Distance
// des ombres [...] c'est des trucs anciens [...] j'ai peur que ca rentre en collision avec notre
// nouvelle approche ». Sa crainte est fondee : `lighting-ao-indirect` a trouve un verrou
// safe-boot herite qui epinglait l'AO a zero en silence, ligne de menu sur HBAO et moteur a
// zero. Un reglage qu'on croit mort et qui pilote encore un chemin de code est exactement ce
// que ce recensement rend impossible a ignorer.
//
// CE QU'IL COMPTE. `lighting_legacy_sites` = le nombre de SITES de l'ancien monde encore VIVANTS
// dans CE binaire, somme de trois sondes independantes qui ne peuvent pas se couvrir l'une
// l'autre :
//   1. GOAL   — le pont `pc-set-*` ou le libelle `*...-label*` est-il encore un symbole de la
//               table du noyau ? On MARCHE la table (pas de 8 octets, cf. dead_probe_census) et
//               on compare la CLE ENTIERE : `pc-set-rt-ambient!` est un prefixe de
//               `pc-set-rt-ambient-model!`, un `strstr` compterait deux fois le meme symbole.
//               `intern_from_c` est proscrit ici : il CREERAIT le symbole cherche.
//   2. C++    — l'option existe-t-elle encore dans la table de `recharged_gating` ? C'est LA
//               table qui decide qu'une rangee apparait dans « Recharged Lighting » : une option
//               absente est une rangee qui ne peut plus revenir par accident.
//   3. SHADER — l'uniforme repond-il encore sur un programme REELLEMENT LIE ? Mesure par
//               `lighting_census.cpp` sur le fil GL (`glGetUniformLocation`), la seule grandeur
//               qui voie ce que la carte a compile — un shader Android est fige dans un blob.
//
// POURQUOI CE ZERO EST FALSIFIABLE. Trois temoins sont publies a cote, et un temoin a zero rend
// la porte MUETTE, pas verte :
//   `lighting_legacy_censused`         combien de sites on cherche (non nul par construction) ;
//   `lighting_legacy_symbols_scanned`  combien de symboles la marche a vus (zero = table vide) ;
//   `lighting_legacy_control_goal`     combien de symboles SURVIVANTS de la refonte repondent ;
//   `lighting_legacy_control_gating`   idem pour les options de la refonte ;
//   `lighting_legacy_uniform_control`  idem pour les uniformes (publie par lighting_census).
// Sans eux, un zero obtenu parce que la sonde n'est branchee sur rien serait indistinguable
// d'un zero obtenu parce que l'ancien monde a ete retire.
namespace {

// Les symboles GOAL de l'ancien monde : les 14 ponts supprimes et les 12 libelles de rangee.
constexpr const char* kLegacyGoalSymbols[] = {
    "pc-set-pbr!",
    "pc-set-modern-materials!",
    "pc-set-rt-shadow-res!",
    "pc-set-rt-shadow-dist!",
    "pc-set-rt-shadow-strength!",
    "pc-set-rt-ambient!",
    "pc-set-rt-ambient-strength!",
    "pc-set-rt-ambient-contrast!",
    "pc-set-rt-ambient-model!",
    "pc-set-pbr-texture-relief!",
    "pc-set-pbr-specular-intensity!",
    "pc-set-pbr-displacement!",
    "pc-set-pbr-isolate!",
    "pc-set-mesh-subdiv-rounds!",
    "*pbr-materials-label*",
    "*modern-materials-label*",
    "*ambient-model-label*",
    "*ambient-strength-label*",
    "*shadow-distance-label*",
    "*shadow-quality-label*",
    "*texture-relief-label*",
    "*specular-intensity-label*",
    "*displacement-label*",
    "*mesh-subdiv-label*",
    "*pbr-test-preset-label*",
    "*pbr-isolate-label*",
    // Le libelle de la curiosite de projection de sonde : il ne portait plus de rangee, mais
    // sa chaine vivait encore dans le CGO. Un residu que rien ne cherchait aurait survecu a
    // une porte verte ; il est dans la liste pour que le zero le couvre.
    "*hemisphere-ambient-label*",
    // essai 3 : les 4 libelles d'OPTION du carrousel PBR ISOLATE. La rangee etait partie des
    // l'essai 1, mais ces globales restaient definies et FORMATEES au chargement de
    // progress-pc.gc : symboles internes, chaines dans le CGO, plus aucune rangee pour les
    // afficher. Rien ne les cherchait — elles auraient survecu a une porte verte.
    "*pbr-iso-both-label*",
    "*pbr-iso-nm-label*",
    "*pbr-iso-pom-label*",
    "*pbr-iso-neither-label*",
};
constexpr int kLegacyGoalCount = (int)(sizeof(kLegacyGoalSymbols) / sizeof(char*));

// LE TEMOIN de la sonde GOAL : quatre symboles du chemin unique de la refonte, qui doivent
// repondre. La marche les trouve par le MEME code que les autres ; s'ils manquent, c'est la
// marche qui est cassee, pas l'ancien monde qui a disparu.
constexpr const char* kLegacyGoalControl[] = {
    "pc-set-rt-light!",
    "pc-set-recharged-master!",
    "*recharged-lighting-label*",
    "*ambient-occlusion-label*",
};
constexpr int kLegacyGoalControlCount = (int)(sizeof(kLegacyGoalControl) / sizeof(char*));

// Les options de `recharged_gating` de l'ancien monde.
constexpr const char* kLegacyGatingOpts[] = {
    "pbr",          "pbr-relief",    "pbr-specular",       "pbr-displacement",
    "pbr-isolate",  "mesh-subdiv",   "modern-materials",   "rt-shadow-res",
    "rt-shadow-dist", "rt-shadow-strength", "rt-ambient",  "rt-ambient-model",
    "rt-ambient-strength", "rt-ambient-contrast",
};
constexpr int kLegacyGatingCount = (int)(sizeof(kLegacyGatingOpts) / sizeof(char*));

// LE TEMOIN de la sonde C++ : trois options du chemin unique, qui restent.
constexpr const char* kLegacyGatingControl[] = {"lighting", "ao-mode", "hdr-output"};
constexpr int kLegacyGatingControlCount = (int)(sizeof(kLegacyGatingControl) / sizeof(char*));

}  // namespace

static void lighting_legacy_census() {
  static u32 s_worst_goal = 0;
  static u32 s_passes = 0;
  static std::string s_worst_names;

  // ── sonde 1 : la table des symboles GOAL ──────────────────────────────────────────────────
  u32 goal_live = 0;
  u32 goal_control = 0;
  u32 scanned = 0;
  std::string names;
  if (SymbolTable2.offset && LastSymbol.offset) {
    for (u32 slot = SymbolTable2.offset; slot < LastSymbol.offset; slot += 8) {
      auto sym = Ptr<Symbol>(slot);
      if (!info(sym)->hash) {
        continue;  // slot jamais occupe
      }
      u32 stro = info(sym)->str.offset;
      if (!stro || stro >= (u32)EE_MAIN_MEM_SIZE - 128) {
        continue;
      }
      const char* nm = reinterpret_cast<const char*>(Ptr<u8>(stro + 4).c());
      size_t nlen = strnlen(nm, 96);
      if (!nlen || nlen >= 96) {
        continue;
      }
      scanned++;
      for (int i = 0; i < kLegacyGoalCount; i++) {
        if (strcmp(nm, kLegacyGoalSymbols[i]) == 0) {
          goal_live++;
          if (names.size() < 160) {
            if (!names.empty()) {
              names += ',';
            }
            names += nm;
          }
          break;
        }
      }
      for (int i = 0; i < kLegacyGoalControlCount; i++) {
        if (strcmp(nm, kLegacyGoalControl[i]) == 0) {
          goal_control++;
          break;
        }
      }
    }
  }
  // La table se remplit au fil des DGO : on garde le PIRE, pour qu'une apparition tardive ne
  // puisse pas etre lavee par une passe propre.
  if (goal_live >= s_worst_goal) {
    s_worst_goal = goal_live;
    s_worst_names = names;
  }
  s_passes++;

  // ── sonde 2 : la table de `recharged_gating` ──────────────────────────────────────────────
  u32 gating_live = 0;
  u32 gating_control = 0;
  std::string gating_names;
  for (int i = 0; i < kLegacyGatingCount; i++) {
    if (recharged_gating::by_name(kLegacyGatingOpts[i]) >= 0) {
      gating_live++;
      if (gating_names.size() < 160) {
        if (!gating_names.empty()) {
          gating_names += ',';
        }
        gating_names += kLegacyGatingOpts[i];
      }
    }
  }
  for (int i = 0; i < kLegacyGatingControlCount; i++) {
    if (recharged_gating::by_name(kLegacyGatingControl[i]) >= 0) {
      gating_control++;
    }
  }

  // ── sonde 3 : les uniformes, mesures sur le fil GL ────────────────────────────────────────
  const u32 uniform_live = lighting_census::legacy_uniform_sites();

  // ── LA PORTE ──────────────────────────────────────────────────────────────────────────────
  autoport_proof::publish("lighting_legacy_sites",
                          (u64)s_worst_goal + (u64)gating_live + (u64)uniform_live);
  autoport_proof::publish("lighting_legacy_goal_sites", s_worst_goal);
  autoport_proof::publish("lighting_legacy_gating_sites", gating_live);
  autoport_proof::publish("lighting_legacy_shader_sites", uniform_live);
  // Le recensement AVANT : combien de sites on CHERCHE. Non nul par construction ; un zero ici
  // dirait que la table de recherche a ete videe, pas que l'ancien monde a disparu.
  autoport_proof::publish("lighting_legacy_censused",
                          (u64)kLegacyGoalCount + (u64)kLegacyGatingCount +
                              (u64)lighting_census::legacy_uniform_censused());
  // Les temoins. Un temoin a zero rend la porte MUETTE, pas verte.
  autoport_proof::publish("lighting_legacy_symbols_scanned", scanned);
  autoport_proof::publish("lighting_legacy_control_goal", goal_control);
  autoport_proof::publish("lighting_legacy_control_gating", gating_control);
  autoport_proof::publish("lighting_legacy_uniform_programs",
                          lighting_census::legacy_uniform_programs());
  autoport_proof::publish("lighting_legacy_uniform_control",
                          lighting_census::legacy_uniform_control());
  // Le denominateur de CE recensement : `hits` est partage par tout le binaire.
  autoport_proof::publish("lighting_legacy_passes", s_passes);
  // Une cle de TEXTE ne se vide jamais toute seule : liste vide => "-", sinon la derniere liste
  // non vide resterait a cote d'un compte a zero.
  autoport_proof::publish_text("lighting_legacy_goal_list",
                               s_worst_names.empty() ? "-" : s_worst_names.c_str());
  autoport_proof::publish_text("lighting_legacy_gating_list",
                               gating_names.empty() ? "-" : gating_names.c_str());
  if (autoport_proof::feature_is("lighting-legacy-purge")) {
    autoport_proof::note_hit_for("lighting-legacy-purge", 1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// mesh-browser-removal : LE RECENSEMENT DU NAVIGATEUR DE MESH DE DEBUG.
//
// POURQUOI. Owner du 11/09, en validant l'item qui l'a livre : « TERMINE, MAIS IL FAUT SUPPRIMER
// CETTE FEATURE ELLE SERT A RIEN, Y COMPRIS SES ENTREES MENU ET BOUTON SUR OVERLAY TACTILE, ET
// RACCOURCI MANETTE IL ME SEMBLE ». La porte de l'item est `mesh_browser_sites == 0`.
//
// UNE PORTE `== 0` EST VERTE PAR INACTION. Publier un zero en dur la passe. Ce qui la rend
// honnete, ici, c'est que le compte est MESURE sur le binaire livre par quatre sondes qui ne
// peuvent pas se couvrir l'une l'autre, que chacune porte son TEMOIN (un temoin a zero rend la
// porte muette, pas verte), et qu'un bras AVANT a ete mesure avec le navigateur encore en place
// (`reports/mesh-browser-removal/notes/proof-recensement-AVANT.txt`).
//
//   1. GOAL    — la table des symboles du runtime, marchee comme dans `dead_probe_census` (pas de
//                8 octets, cf. find_symbol_in_area). C'est l'image REELLEMENT CHARGEE qui repond,
//                pas le source : un `mesh-browser-update` toujours dans GAME.CGO s'y voit.
//                `intern_from_c` est proscrit : il CREERAIT le symbole qu'on pretend supprime.
//   2. C++     — les champs `mb_*` de `GfxGlobalSettings`, detectes PAR LE COMPILATEUR (idiome
//                SFINAE). Re-ajouter un champ a gfx.h rearme la porte sans qu'une ligne d'ici ne
//                bouge — c'est ce qu'un `grep` recopie a la main ne sait pas faire.
//   3. GATING  — l'option `mesh-browser-checker` de `recharged_gating`, LA table qui autorise une
//                rangee de menu a exister.
//   4. OVERLAY — les pastilles du navigateur dans l'overlay tactile Android. Java vit HORS de
//                libgk.so : aucune sonde C++ ne le voit, c'est donc `TouchOverlayView` qui
//                rapporte (game/system/mesh_browser_census.h). Tant qu'il n'a rien dit, la sonde
//                rend 1 : INCONNU = DEFAUT, jamais « propre ».
namespace {

// L'idiome de detection : la reponse vient de la VRAIE declaration de `GfxGlobalSettings`.
#define MB_DETECT_FIELD(NAME, FIELD)                                                        \
  template <typename T, typename = void>                                                    \
  struct NAME : std::false_type {};                                                         \
  template <typename T>                                                                     \
  struct NAME<T, std::void_t<decltype(std::declval<T&>().FIELD)>> : std::true_type {};

MB_DETECT_FIELD(HasMbChecker, recharged_mesh_browser_checker)
MB_DETECT_FIELD(HasMbTargetActive, mb_target_active)
MB_DETECT_FIELD(HasMbHideTarget, mb_hide_target)
MB_DETECT_FIELD(HasMbGizmosTarget, mb_gizmos_target)
MB_DETECT_FIELD(HasMbIsolate, mb_isolate)
MB_DETECT_FIELD(HasMbPbrOverride, mb_pbr_override)
MB_DETECT_FIELD(HasMbPickSerial, mb_pick_serial)
MB_DETECT_FIELD(HasMbHoverOn, mb_hover_on)
MB_DETECT_FIELD(HasMbMarksStore, mb_marks_store)
MB_DETECT_FIELD(HasMbFlipCounters, mb_frame_no)
// LE TEMOIN de la sonde C++ : un champ du chemin NORMAL, qui doit rester. S'il rend 0, c'est le
// detecteur qui est casse (nom de type change, en-tete non inclus), pas le navigateur qui a
// disparu — et la porte doit se lire « muette », pas « verte ».
MB_DETECT_FIELD(HasRechargedMaster, recharged_master)
#undef MB_DETECT_FIELD

constexpr u32 kMbCppSites =
    (u32)HasMbChecker<GfxGlobalSettings>::value + (u32)HasMbTargetActive<GfxGlobalSettings>::value +
    (u32)HasMbHideTarget<GfxGlobalSettings>::value +
    (u32)HasMbGizmosTarget<GfxGlobalSettings>::value + (u32)HasMbIsolate<GfxGlobalSettings>::value +
    (u32)HasMbPbrOverride<GfxGlobalSettings>::value +
    (u32)HasMbPickSerial<GfxGlobalSettings>::value + (u32)HasMbHoverOn<GfxGlobalSettings>::value +
    (u32)HasMbMarksStore<GfxGlobalSettings>::value +
    (u32)HasMbFlipCounters<GfxGlobalSettings>::value;
constexpr u32 kMbCppCensused = 10;  // combien de champs on CHERCHE : non nul par construction

// La FAMILLE du navigateur cote GOAL. Deux formes, parce qu'aucune seule ne suffit :
//   * PREFIXES — `mb-`, `*mb-`, `pc-mb-` : la famille courte. Un `strstr("mb-")` attraperait
//     `climb-...` et rendrait la porte inatteignable a vie ; l'ancrage en DEBUT de nom, lui, est
//     exact. Le `*` des globales GOAL est traite comme un debut de nom.
//   * SOUS-CHAINES — `mesh-browser`, `mesh-index`, `mesh-marks` : sans ambiguite ou qu'elles
//     tombent dans le nom (`*mesh-browser*`, `pc-mesh-index-getf`, ...).
constexpr const char* kMbSymbolPrefixes[] = {"mb-", "*mb-", "pc-mb-", "mb_", "*mb_"};
constexpr const char* kMbSymbolSubstrings[] = {"mesh-browser", "mesh_browser", "mesh-index",
                                               "mesh_index", "mesh-marks", "mesh_marks"};
constexpr int kMbPrefixCount = (int)(sizeof(kMbSymbolPrefixes) / sizeof(char*));
constexpr int kMbSubstringCount = (int)(sizeof(kMbSymbolSubstrings) / sizeof(char*));

// LE TEMOIN de la sonde GOAL : des symboles du jeu normal qui doivent repondre. S'ils manquent,
// c'est la marche de la table qui est cassee, pas le navigateur qui a disparu.
constexpr const char* kMbGoalControl[] = {"target", "progress", "*target*", "camera-master"};
constexpr int kMbGoalControlCount = (int)(sizeof(kMbGoalControl) / sizeof(char*));

// La sonde GATING et son temoin.
constexpr const char* kMbGatingOpts[] = {"mesh-browser-checker"};
constexpr int kMbGatingCount = (int)(sizeof(kMbGatingOpts) / sizeof(char*));
constexpr const char* kMbGatingControl[] = {"lighting", "ao-mode"};
constexpr int kMbGatingControlCount = (int)(sizeof(kMbGatingControl) / sizeof(char*));

bool mb_symbol_matches(const char* nm) {
  for (int i = 0; i < kMbPrefixCount; i++) {
    const char* p = kMbSymbolPrefixes[i];
    if (strncmp(nm, p, strlen(p)) == 0) {
      return true;
    }
    // Une globale GOAL s'ecrit `*nom*` : le `*` de tete ne fait pas partie de la famille.
    if (nm[0] == '*' && strncmp(nm + 1, p, strlen(p)) == 0) {
      return true;
    }
  }
  for (int i = 0; i < kMbSubstringCount; i++) {
    if (strstr(nm, kMbSymbolSubstrings[i])) {
      return true;
    }
  }
  return false;
}

}  // namespace

static void mesh_browser_removal_census() {
  static u32 s_worst_goal = 0;
  static u32 s_passes = 0;
  static std::string s_worst_names;

  // ── sonde 1 : la table des symboles GOAL ──────────────────────────────────────────────────
  u32 goal_live = 0;
  u32 goal_control = 0;
  u32 scanned = 0;
  std::string names;
  if (SymbolTable2.offset && LastSymbol.offset) {
    for (u32 slot = SymbolTable2.offset; slot < LastSymbol.offset; slot += 8) {
      auto sym = Ptr<Symbol>(slot);
      if (!info(sym)->hash) {
        continue;  // slot jamais occupe
      }
      u32 stro = info(sym)->str.offset;
      if (!stro || stro >= (u32)EE_MAIN_MEM_SIZE - 128) {
        continue;
      }
      const char* nm = reinterpret_cast<const char*>(Ptr<u8>(stro + 4).c());
      size_t nlen = strnlen(nm, 96);
      if (!nlen || nlen >= 96) {
        continue;
      }
      scanned++;
      if (mb_symbol_matches(nm)) {
        goal_live++;
        if (!names.empty()) {
          names += ',';
        }
        names += nm;
      }
      for (int i = 0; i < kMbGoalControlCount; i++) {
        if (strcmp(nm, kMbGoalControl[i]) == 0) {
          goal_control++;
          break;
        }
      }
    }
  }
  // La table se remplit au fil des DGO charges : on garde le PIRE, pour qu'une apparition tardive
  // ne puisse pas etre lavee par une passe propre.
  if (goal_live >= s_worst_goal) {
    if (goal_live > s_worst_goal && !names.empty()) {
      // L'audit des faux positifs se fait sur la LISTE COMPLETE, pas sur la cle tronquee : elle
      // part dans le journal du moteur, que `proof-engine.log` conserve.
      lg::warn("[mb-census] {} symboles de la famille : {}", goal_live, names);
    }
    s_worst_goal = goal_live;
    s_worst_names = names;
  }
  s_passes++;

  // ── sonde 3 : la table de `recharged_gating` ──────────────────────────────────────────────
  u32 gating_live = 0;
  u32 gating_control = 0;
  for (int i = 0; i < kMbGatingCount; i++) {
    if (recharged_gating::by_name(kMbGatingOpts[i]) >= 0) {
      gating_live++;
    }
  }
  for (int i = 0; i < kMbGatingControlCount; i++) {
    if (recharged_gating::by_name(kMbGatingControl[i]) >= 0) {
      gating_control++;
    }
  }

  // ── sonde 4 : l'overlay tactile, rapporte par Java ────────────────────────────────────────
  const u32 overlay_live = mesh_browser_census::overlay_sites();

  // ── LA PORTE ──────────────────────────────────────────────────────────────────────────────
  autoport_proof::publish("mesh_browser_sites",
                          (u64)s_worst_goal + (u64)kMbCppSites + (u64)gating_live +
                              (u64)overlay_live);
  autoport_proof::publish("mesh_browser_goal_sites", s_worst_goal);
  autoport_proof::publish("mesh_browser_cpp_sites", kMbCppSites);
  autoport_proof::publish("mesh_browser_gating_sites", gating_live);
  autoport_proof::publish("mesh_browser_overlay_sites", overlay_live);
  // Le recensement AVANT : combien de sites on CHERCHE. Un zero ici dirait que la table de
  // recherche a ete videe, pas que le navigateur a disparu.
  autoport_proof::publish("mesh_browser_censused",
                          (u64)kMbCppCensused + (u64)kMbGatingCount + (u64)kMbPrefixCount +
                              (u64)kMbSubstringCount);
  // LES TEMOINS. Un temoin a zero rend la porte MUETTE, pas verte.
  autoport_proof::publish("mesh_browser_symbols_scanned", scanned);
  autoport_proof::publish("mesh_browser_symbols_known", NumSymbols < 0 ? 0 : (u64)NumSymbols);
  autoport_proof::publish("mesh_browser_control_goal", goal_control);
  autoport_proof::publish("mesh_browser_control_cpp",
                          (u64)(HasRechargedMaster<GfxGlobalSettings>::value ? 1 : 0));
  autoport_proof::publish("mesh_browser_control_gating", gating_control);
  autoport_proof::publish("mesh_browser_overlay_control", mesh_browser_census::overlay_control());
  autoport_proof::publish("mesh_browser_overlay_reports",
                          mesh_browser_census::overlay_reported());
  // Le denominateur de CE recensement : `hits` est partage par tout le binaire.
  autoport_proof::publish("mesh_browser_passes", s_passes);
  // Une cle de TEXTE ne se vide jamais toute seule : liste vide => "-", sinon la derniere liste
  // non vide resterait a cote d'un compte a zero.
  {
    std::string shown = s_worst_names;
    if (shown.size() > 300) {
      shown.resize(300);
      shown += "...";
    }
    autoport_proof::publish_text("mesh_browser_goal_list", shown.empty() ? "-" : shown.c_str());
  }
  if (autoport_proof::feature_is("mesh-browser-removal")) {
    autoport_proof::note_hit_for("mesh-browser-removal", 1);
  }
}

void pc_autoport_frame() {
  // recharged-gating-real : LE seul point de ce fichier qui tourne une fois par image RENDUE.
  // La valeur EFFECTIVE doit etre dans le champ meme quand aucun `pc-set-*` n'a bouge : un
  // ancetre eteint par le harnais (surcharge de gfx.h, epinglage refset) ou un balayage de
  // mesure ne passe par aucun setter. En premiere ligne, avant tout le reste, pour qu'aucun
  // travail de cette image ne lise un champ non compose.
  recharged_gating::tick();
  fire_red_census::end_frame();
  // recharged-naming : le recensement du nommage. Muet tant que le harnais ne nomme pas
  // cet item (voir game/system/naming_census.h).
  naming_census::tick();
  // builder-checkpoint-steals-work : le recensement des commits du constructeur et des scripts
  // du harnais qui ecrivent dans git. Muet tant que le harnais ne nomme pas cet item, une seule
  // passe par course (voir game/system/checkpoint_census.h).
  checkpoint_census::tick();
  autoport_proof::frame_tick();
  // hd-stretch-flag-in-game-logic : le recensement des consultations de l'armement, publie a
  // CHAQUE image et non toutes les 60 : `flush()` emet la derniere valeur publiee, donc une
  // consultation survenue dans les dernieres images d'une course en sortirait effacee.
  autoport_proof::publish_flag_census("hd-stretch-flag-in-game-logic");
  // dead-follow-probe : le recensement repasse toutes les 60 images (la table des symboles se
  // remplit au fil des DGO ; une seule passe au demarrage ne verrait pas un symbole tardif).
  {
    static u32 s_dead_probe_n = 0;
    if ((s_dead_probe_n++ % 60) == 0) {
      dead_probe_census();
      // lighting-legacy-purge : meme cadence et meme raison — la table des symboles se
      // remplit au fil des DGO, une seule passe au demarrage ne verrait pas un symbole tardif.
      lighting_legacy_census();
      // mesh-browser-removal : idem. La sonde overlay, elle, se met a jour toute seule des que
      // `TouchOverlayView` rapporte ; on la relit simplement a chaque passe.
      mesh_browser_removal_census();
    }
  }
  // lighting-census : l'ancre du jeu d'images de reference est un ETAT, pas une duree. Elle se
  // pose quand *target* est vivant ET que le warp de niveau a deja lance (start 'play ...) —
  // la garde que `pad_replay` n'applique qu'au warp F1 (voir pad_replay_anchor_reached).
  // A cette ancre, et pas a celle du titre, on refixe TOUTES les sources d'alea : entre le
  // titre et le niveau il se consomme un nombre variable de tirages, et sans ce second forcage
  // l'etat du jeu au moment de la mesure differerait d'une course a l'autre.
  refset_pump(false);
  // perf-stock-baseline : la campagne pose sa demande de teleport depuis le fil GL ; c'est ici,
  // sur le fil GOAL, qu'elle devient un `(start 'play ...)`. Hors campagne, rien n'est en
  // attente et l'appel sort a sa premiere ligne.
  perf_baseline_warp_maybe();
}

// ── recharged-gating-real : le grisage du menu vient du C++ ──────────────────────────────────
// La dependance entre options etait ecrite DEUX fois — une lambda `option-disabled-func` par
// rangee cote GOAL, et ~92 portes recopiees a la main cote C++. Deux ecritures d'une meme regle
// divergent, et elles avaient diverge : des rangees grisees a l'ecran continuaient de couter,
// parce que rien ne comparait les deux moities. Le grisage passe donc par la MEME table que la
// porte du moteur (game/system/recharged_gating.h), et GOAL ne porte plus sa propre copie.

// 1 si un ANCETRE de cette option est eteint : c'est le predicat de grisage du menu, et c'est
// EXACTEMENT celui que le moteur applique. GOAL ne porte plus sa propre copie de la regle.
// Un identifiant inconnu rend 0 : une rangee mal nommee reste utilisable plutot que de se
// griser toute seule sans que rien ne le dise — et le recensement du menu, lui, la compte.
s32 pc_gating_disabled(u32 id_str) {
  const char* id = id_str ? Ptr<String>(id_str).c()->data() : nullptr;
  const int opt = recharged_gating::by_name(id);
  return (opt >= 0 && recharged_gating::disabled_by_ancestor(opt)) ? 1 : 0;
}
void pc_gating_menu_begin() {
  recharged_gating::menu_begin();
}
void pc_gating_menu_row(u32 page_str, u32 id_str) {
  const char* page = page_str ? Ptr<String>(page_str).c()->data() : nullptr;
  const char* id = id_str ? Ptr<String>(id_str).c()->data() : nullptr;
  recharged_gating::menu_row(page, id);
}
// 1 quand le harnais mesure CET item. Le recensement des portes a besoin de `init-game-options`,
// que le jeu n'appelle qu'a l'OUVERTURE du menu : sous mesure, GOAL le force une fois au boot
// pour qu'une course puisse recenser sans qu'un humain ouvre le menu. Hors mesure on ne touche a
// rien — forcer le cablage pour tout le monde changerait le jeu livre. C'est l'INSTRUMENT qui est
// sous drapeau, jamais le correctif (meme patron que `pc_scl10n_wanted`).
// La page ou une rangee doit vivre, deduite de la table des portes : 0 Recharged, 1 Grass,
// 2 Recharged Lighting, -1 inconnue. C'est GOAL qui construit ses pages avec ca, au lieu de
// porter sa propre liste — une liste ecrite a la main deriverait de la hierarchie au premier
// ajout, et on referait sur la PLACE des options la faute qu'on corrige sur leur EXTINCTION.
s32 pc_gating_page(u32 id_str) {
  const char* id = id_str ? Ptr<String>(id_str).c()->data() : nullptr;
  return recharged_gating::page_of(recharged_gating::by_name(id));
}

s32 pc_gating_wanted() {
  return recharged_gating::census_wanted() ? 1 : 0;
}

void pc_gating_menu_end() {
  recharged_gating::menu_end();
}

// LE LIBELLE PORTEUR D'UNE RANGEE : l'indice affiche, celui que l'ouverture preselectionne, le
// nombre de lignes de la page de choix, et le texte lui-meme. Le module confronte `shown` a la
// valeur VOULUE de sa table — GOAL n'est donc pas juge sur sa propre arithmetique.
void pc_gating_row_value(u32 id_str, s32 shown, s32 presel, s32 rows, u32 value_str) {
  const char* id = id_str ? Ptr<String>(id_str).c()->data() : nullptr;
  const char* value = value_str ? Ptr<String>(value_str).c()->data() : nullptr;
  recharged_gating::menu_value(id, shown, presel, rows, value);
}

// Ce que GOAL compte sur la page qu'il vient de dessiner : des rangees verrouillees ENCORE
// presentes (doit rester zero) et le total de rangees masquees, temoin a confronter au compte du
// C++. Deux comptes tenus depuis les deux bouts de la chaine ne peuvent pas deriver en silence.
void pc_gating_mask_counts(s32 shown_locked, s32 masked) {
  recharged_gating::menu_mask_counts(shown_locked, masked);
}

// 1 quand le module RECLAME un recensement. Le balayage eteint un parent different a chaque
// fenetre : un recensement unique ne verrait qu'un seul regime, et le masquage ne serait jamais
// exerce. La lecture CONSOMME la demande.
s32 pc_gating_census_due() {
  return recharged_gating::census_due() ? 1 : 0;
}

void pc_npc_census_end() {
  npc_flicker::end_census();
}

// L'ETAT D'ARMEMENT DU CORRECTIF, LU PAR GOAL. Rend 1 par defaut — le binaire de l'owner
// EST corrige. Il ne rend 0 que si le harnais a nomme cet item et pose `armed=0` : c'est le
// bras d'ablation, et rien d'autre ne peut y tomber. Voir game/system/autoport_proof.h.
s32 pc_npcf_fix_armed() {
  // hd-stretch-flag-in-game-logic : recense la consultation. Polarite DANGEREUSE — un site GOAL
  // qui teste `(zero? ...)` prend la branche « comportement d'avant » des que ce pont est muet.
  // L'identifiant est l'armement GLOBAL : ce pont ne sait pas de quel item il parle, ce qui est
  // le defaut que `armed_for` corrige.
  autoport_proof::note_flag_consult(autoport_proof::kFlagDangerous, "__global-armed");
  return autoport_proof::armed() ? 1 : 0;
}

// L'ETAT D'ARMEMENT D'UN ITEM NOMME, LU PAR GOAL. Rend 1 par defaut ; il ne rend 0 que si le
// harnais a nomme CET item-la et pose `armed=0`. `pc_npcf_fix_armed` ci-dessus consulte l'etat
// GLOBAL : mesurer l'item A desarme du meme coup le correctif de l'item B. Voir armed_for().
s32 pc_autoport_armed_for(u32 id_str) {
  const char* id = id_str ? Ptr<String>(id_str).c()->data() : nullptr;
  // hd-stretch-flag-in-game-logic : LE PONT RECENSE SES APPELANTS. La porte de cet item lit
  // `proof_flag_game_sites` — le nombre d'identifiants distincts consultes ici pendant la course.
  // Le pont reste appelable exprès : un compteur qu'aucun code ne peut incrementer publierait
  // zero pour toujours et ne detecterait jamais la reintroduction du defaut.
  autoport_proof::note_flag_consult(autoport_proof::kFlagDangerous, id);
  return autoport_proof::armed_for(id) ? 1 : 0;
}

// UNE GRANDEUR QUELCONQUE, PUBLIEE PAR GOAL SOUS SON NOM. `proof_run.sh` ne moissonne que les
// lignes `cle=valeur` SEULES sur leur ligne : une grandeur noyee dans un `format` a six colonnes
// (HDMOVES, HDLEN...) n'atteint jamais proof.txt, et le rapport doit alors la recopier a la main —
// ce que les DIRECTIVES interdisent. Ce pont donne a GOAL le meme canal que le C++.
void pc_autoport_publish(u32 key_str, s64 value) {
  const char* k = key_str ? Ptr<String>(key_str).c()->data() : nullptr;
  autoport_proof::publish(k, (u64)(value < 0 ? 0 : value));
}

// perf-ocean-idle — L'ABLATION D'UN ITEM NOMME, EN POLARITE INVERSE (0 = correctif ARME).
// `__pc-autoport-armed-for` ci-dessus rend 1 quand l'item est arme. C'est le bon sens tant que le
// pont est relie et le MAUVAIS sens des qu'il ne l'est pas : un helper `pc-*` non relie laisse
// son emplacement de valeur a zero, et un correctif GOAL ecrit
// `(when (zero? (__pc-autoport-armed-for "x")) ...)` se desarmerait tout seul.
// Ici le zero veut dire « personne ne demande l'ablation » : un pont muet laisse le correctif
// ARME, seul sens compatible avec les DIRECTIVES (un correctif derriere un drapeau eteint par
// defaut n'existe pas pour l'owner).
//
// hd-stretch-flag-in-game-logic (2026-09-10) — CE QUE LA VERSION PRECEDENTE DE CE COMMENTAIRE
// DISAIT ET QUI EST FAUX : « sur Android tout helper `pc-*` absent de la liste a17 tombe sur
// `a17_pc_default` ». La liste a17 (android/gk_android_main.cpp:1323-1520) ne rebranche que la
// surface COMMUNE de `init_common_pc_port_functions`, la seule que l'override Android saute.
// Les `__pc-autoport-*` sont enregistres par `InitMachine_PCPort` (ce fichier), appelee par
// `jak1::InitMachineScheme` qui est la VRAIE depuis la phase D4 — et `__pc-autoport-frame`, 126
// lignes plus haut dans la meme fonction, est ce qui remplit `frames=` de toutes les preuves
// appareil du backlog. Le pont est donc relie sur l'appareil. La polarite sure reste la bonne
// regle, mais ce n'est plus Android qui la motive.
s32 pc_autoport_disarmed_for(u32 id_str) {
  const char* id = id_str ? Ptr<String>(id_str).c()->data() : nullptr;
  // hd-stretch-flag-in-game-logic : LE TEMOIN de la porte. Ce pont-ci est enregistre deux lignes
  // apres `__pc-autoport-armed-for` dans le meme `InitMachine_PCPort` ; s'il compte des appels
  // venus de GOAL, la famille est bien reliee sur cette machine et un `proof_flag_game_sites=0`
  // dit « aucun site », pas « aucun pont ».
  autoport_proof::note_flag_consult(autoport_proof::kFlagSafe, id);
  return autoport_proof::armed_for(id) ? 0 : 1;
}

// perf-ocean-idle — LE COMPTEUR `hits=` DE LA LIGNE FEATURE, ALIMENTE PAR GOAL. `note_hit` ne
// compte que feature ARMEE : c'est ce qui rend le bras `--off` lisible (`hits=0`). Sans ce pont,
// un correctif ecrit entierement en GOAL ne peut pas prouver qu'il a tire, et le validateur le
// refuse pour « rien ne prouve que la feature a tire ». ATTENTION : `hits` est un compteur
// PARTAGE par tous les modules du binaire ; un correctif qui s'en sert publie A COTE son propre
// denominateur, sinon son chiffre ne parle de rien.
void pc_autoport_hit(s64 n) {
  autoport_proof::note_hit((u64)(n < 0 ? 0 : n));
}

// ─── Grecharged-settings-case-l10n — LE PONT DU RECENSEMENT DU MENU ───────────────────────────
// GOAL seul sait quelles LIGNES le menu Recharged contient et quel identifiant de banc alimente
// le libelle de chacune ; le C++ seul sait relire les 23 bancs `<n>COMMON.TXT` livres. Ces
// quatre ponts joignent les deux moities. Voir game/system/settings_case_l10n.h.
// ─── title-tap-prompt-regression — L'INVITE DU TITRE SE CHOISIT SUR LE TACTILE ────────────────
// Le defaut de l'owner (11/09) : « SUR ANDROID (AVEC TACTILE) ON A "Appuie sur start" AU LIEU DE
// "Appuie sur start ou touche l'ecran" ». L'ancienne version decidait a la CONSTRUCTION en
// surchargeant #x16e dans une banque « android » — donc par PLATEFORME, ce qui est faux pour la
// SHIELD, et mort depuis que le generateur de cette banque a ete archive.
//
// Desormais GOAL demande le fait (`__pc-touch-screen?`), choisit son id, dessine, puis DECLARE ce
// qu'il a dessine (`__pc-title-prompt-drawn`). Le juge ci-dessous relit le fait tactile de son
// cote et lit les OCTETS de la chaine remise a `print-game-text` : il ne croit pas GOAL sur
// parole. `title_prompt_wrong` compte une image fautive quand
//   * personne n'a pose le fait tactile (`source == kNone`) — un binaire sans ecrivain rendrait
//     « pas de tactile », donc l'invite courte, donc un vert par INACTION sur le defaut meme ;
//   * l'id dessine ne correspond pas au fait tactile ;
//   * la banque ne porte pas la chaine — `lookup-text!` rend alors « UNKNOWN ID <n> », et c'est
//     exactement comme cela que #x1728 avait fini a l'ecran (MESH BROWSER, « UNKNOWN ID 5928 ») ;
//   * la chaine est vide ;
//   * L'INVITE NE TIENT PAS SUR UNE LIGNE. Refus de l'owner du 11/09 : la porte etait VERTE et
//     le defaut INTACT, parce qu'elle lisait la chaine REMISE a `print-game-text` et jamais ce
//     qui arrive a l'ecran. Rien n'etait coupe : la boite faisait 352 de large, l'invite 378,1,
//     et elle se REPLIAIT en deux lignes au pire endroit. La trace de dessin de l'appareil
//     (`FONT-STR`, armee une fois par la meme fonction GOAL) l'a montre mot pour mot :
//       FONT-STR len=26 str=Appuie sur start ou touche
//       FONT-STR len=21 str=le~Y~-14H~-1V~Zcran            (= « l'ecran »)
//     GOAL declare donc le nombre de LIGNES que la mise en page a dessinees et celui qu'elle
//     demande, tous deux rendus par `print-game-text` lui-meme, et la porte exige : les deux
//     egaux, ET egaux a UN. `title_prompt_raw_width_q` / `title_prompt_scaled_width_q` sont
//     publies a cote — la seconde est exactement la grandeur que `print-game-text` compare a la
//     largeur de la boite (448), donc un lecteur peut refaire le calcul sans le code.
constexpr u32 kTitlePromptPlainId = 0x16e;   // (press-start) — engine/ui/text-h.gc:112
constexpr u32 kTitlePromptTapId = 0x17e7;    // (pc-text-press-start-or-tap) — text-h.gc

s32 pc_touch_screen_present() {
  return touch_screen::present() ? 1 : 0;
}

void pc_title_prompt_drawn(s64 text_id,
                           u32 shown_str,
                           s64 drawn_lines,
                           s64 needed_lines,
                           s64 raw_width_q,
                           s64 scaled_width_q) {
  static u64 s_frames = 0;
  static u64 s_wrong = 0;
  static u64 s_cut = 0;

  const char* shown = shown_str ? Ptr<String>(shown_str).c()->data() : nullptr;
  const u32 len = shown ? (u32)strlen(shown) : 0;
  // La chaine que `lookup-text!` fabrique quand l'id manque de la banque ET de la banque de repli.
  const bool unknown = shown && strncmp(shown, "UNKNOWN ID", 10) == 0;

  const bool touch = touch_screen::present();
  const u32 want = touch ? kTitlePromptTapId : kTitlePromptPlainId;
  const bool measured = touch_screen::source() != touch_screen::kNone;

  // CE QUI EST DESSINE, pas ce qui est remis. `needed_lines` est le nombre de lignes que la mise
  // en page produit sans plafond de hauteur, `drawn_lines` celui que la boite livree a rendu ;
  // les deux sortent de `print-game-text`, divises par la hauteur de ligne qu'il a lui-meme
  // employee. Zero veut dire que personne n'a mesure : c'est une faute, pas un zero. Plus d'une
  // ligne veut dire que l'invite est coupee en deux — le defaut que l'owner lit.
  const bool cut = needed_lines != 1 || drawn_lines != 1;

  s_frames++;
  if (!measured || (u32)text_id != want || len == 0 || unknown || cut) {
    s_wrong++;
  }
  if (cut) {
    s_cut++;
  }

  autoport_proof::publish("title_prompt_wrong", s_wrong);
  autoport_proof::publish("title_prompt_frames", s_frames);
  autoport_proof::publish("title_touch_present", touch ? 1 : 0);
  autoport_proof::publish_text("title_touch_source", touch_screen::source_name());
  autoport_proof::publish("title_touch_input_devices",
                          (u64)(s64)(touch_screen::input_devices() < 0
                                         ? 0
                                         : touch_screen::input_devices()));
  autoport_proof::publish("title_prompt_text_id", (u64)(u32)text_id);
  autoport_proof::publish("title_prompt_want_id", want);
  autoport_proof::publish("title_prompt_len", len);
  autoport_proof::publish("title_prompt_unknown_id", unknown ? 1 : 0);
  autoport_proof::publish("title_prompt_drawn_lines", (u64)(drawn_lines < 0 ? 0 : drawn_lines));
  autoport_proof::publish("title_prompt_needed_lines", (u64)(needed_lines < 0 ? 0 : needed_lines));
  autoport_proof::publish("title_prompt_cut", s_cut);
  // LES DEUX ENTREES DU REPLI, au millieme. `print-game-text` compare, mot par mot,
  // `get-string-length x relative-x-scale` a la largeur de la boite : sans ces deux nombres on ne
  // peut pas savoir OU la ligne se coupe, et donc pas savoir ce que l'ecran montre.
  autoport_proof::publish("title_prompt_raw_width_q", (u64)(raw_width_q < 0 ? 0 : raw_width_q));
  autoport_proof::publish("title_prompt_scaled_width_q",
                          (u64)(scaled_width_q < 0 ? 0 : scaled_width_q));

  // Les 16 premiers octets de ce qui est REELLEMENT remis a print-game-text : le rapport dit
  // quelle invite l'appareil dessine, sans capture d'ecran.
  if (shown) {
    char head[24];
    u32 n = len < 20 ? len : 20;
    for (u32 i = 0; i < n; i++) {
      const unsigned char c = (unsigned char)shown[i];
      head[i] = (c > 0x20 && c < 0x7f) ? (char)c : '_';
    }
    head[n] = '\0';
    autoport_proof::publish_text("title_prompt_head", n ? head : "-");
  } else {
    autoport_proof::publish_text("title_prompt_head", "-");
  }
  autoport_proof::note_hit_for("title-tap-prompt-regression", 1);
}

void pc_scl10n_begin(s64 current_language) {
  settings_case_l10n::begin_census((int)current_language);
}

void pc_scl10n_label(s64 text_id, u32 shown_str) {
  const char* shown = shown_str ? Ptr<String>(shown_str).c()->data() : nullptr;
  settings_case_l10n::note_label((int)text_id, shown);
}

void pc_scl10n_uncovered(u32 who_str) {
  const char* who = who_str ? Ptr<String>(who_str).c()->data() : nullptr;
  settings_case_l10n::note_uncovered_row(who);
}

void pc_scl10n_end() {
  settings_case_l10n::end_census();
}

// 1 quand le harnais mesure CET item. Le recensement appelle `init-game-options` au boot, ce que
// le jeu ne fait qu'a l'ouverture du menu : hors mesure, on ne touche a rien. C'est l'INSTRUMENT
// qui est sous drapeau, jamais le correctif — les libelles traduits sont dans le banc pour tous.
s32 pc_scl10n_wanted() {
  return autoport_proof::feature_is("recharged-settings-case-l10n") ? 1 : 0;
}

// ─── Ghd-skin-origin-stretch — LE COMPTE DE LA PORTE, ASSEMBLE EN UN SEUL ENDROIT ─────────────
// `validators/generic.sh` lit UNE grandeur : `hd_bones_stretched`. Elle doit valoir 0 seulement
// si l'owner ne voit plus RIEN — pas seulement si l'etirement a disparu. Ses termes :
//   moitie GOAL (`goal_bad`)  : os ecrits loin de la pose commandee par le reciblage de la meme
//                               image, echelle de base hors de [1/3, 3] x bind, matrice merc qui
//                               ne porte pas la longueur du squelette, os deplaces entre le
//                               :post et draw-bones (jak-hd.gc) ;
//   moitie GPU (Merc2)        : os CONSOMMES hors de la pose commandee (c'est ce terme qui voit
//                               le « modele transpose » du 2026-09-03 : 17 688 os a 14,18 m sur
//                               le bras affine_arm=1), hors d'echelle, ou differents de ce que
//                               GOAL avait ecrit ;
//   `tpose_drawn`             : images ou un compagnon a ete DESSINE en pose de bind (t-pose).
//                               C'etait l'angle mort : `hd-root-scan!` saute ces images-la
//                               (`st-warm=0`) et `HDLEN9 tpose=0` ne les couvre pas, pendant que
//                               le telephone en comptait 214 en 3,5 min de jeu reel ;
//   `bone_off_pilot`          : images ou l'os HD de reference n'est PAS sur l'os pilote qu'il
//                               recopie — la forme HD-specifique du saut de racine.
// `root_jumps` (l'os de reference contre `root trans` du pilote) est publie A COTE et n'entre
// PAS dans la somme : sur les 15 episodes de la course appareil du cycle 8, les 15 portent
// `hd_moins_pilote_m = 0.0000`, c'est-a-dire un os HD exactement sur l'os stock. Ce residu est
// partage avec la chaine de peau stock, que cet item n'a pas le droit de toucher.
void pc_hd_proof(s64 goal_bad,
                 s64 tpose_drawn,
                 s64 bone_off_pilot,
                 s64 root_jumps,
                 s64 bindpose_occasions,
                 s64 hits_cumulative) {
  const u64 gpu = merc2_hd_stretch_verdict();
  const u64 total = (u64)goal_bad + (u64)tpose_drawn + (u64)bone_off_pilot + gpu;
  autoport_proof::publish("hd_bones_stretched", total);
  autoport_proof::publish("hd_goal_side_bad", (u64)goal_bad);
  autoport_proof::publish("hd_gpu_side_bad", gpu);
  autoport_proof::publish("hd_tpose_drawn_frames", (u64)tpose_drawn);
  autoport_proof::publish("hd_bone_off_pilot_frames", (u64)bone_off_pilot);
  autoport_proof::publish("hd_root_jumps", (u64)root_jumps);
  autoport_proof::publish("hd_bindpose_occasions", (u64)bindpose_occasions);
  autoport_proof::publish("hd_gpu_cmd_bones", merc2_hd_stretch_diag(0));
  autoport_proof::publish("hd_gpu_scale_bones", merc2_hd_stretch_diag(1));
  autoport_proof::publish("hd_gpu_ring_bad", merc2_hd_stretch_diag(2));
  autoport_proof::publish("hd_gpu_bones_judged", merc2_hd_stretch_diag(3));
  autoport_proof::publish("hd_diag_bone_length", merc2_hd_stretch_diag(4));
  autoport_proof::publish("hd_diag_bad_bones", merc2_hd_stretch_diag(5));
  autoport_proof::publish("hd_gpu_ring_judged", merc2_hd_stretch_diag(6));
  autoport_proof::publish("hd_gpu_cmd_judged", merc2_hd_stretch_diag(7));
  // `hits` doit compter les fois ou LE CORRECTIF a tourne, pas les images. GOAL rend un cumul ;
  // on en publie l'increment, sinon `hits` compterait N fois le meme cumul.
  static s64 s_last_hits = 0;
  if (hits_cumulative > s_last_hits) {
    autoport_proof::note_hit((u64)(hits_cumulative - s_last_hits));
    s_last_hits = hits_cumulative;
  }
}

// Une image ou le compagnon HD a ete MAINTENU la ou l'ancien code l'eteignait.
void pc_npcf_note_cover() {
  npc_flicker::note_hd_noanim_cover();
}

void pc_npc_clone_fail(u32 merc_name) {
  npc_flicker::note_clone_remap_fail(merc_name ? Ptr<String>(merc_name).c()->data() : nullptr);
}

// LE CORRECTIF, LU PAR `clone-anim-once`. Rend 1 quand le clone doit GARDER la pose de l'image
// precedente au lieu de se masquer, 0 quand il doit retomber sur l'ancien comportement (jamais
// dessine encore, serie de maintien plus longue que le plafond, ou feature desarmee par le
// harnais). Voir le pave de `should_hold_clone` dans game/system/npc_flicker.h.
s32 pc_npcf_clone_hold(s32 pid) {
  return npc_flicker::should_hold_clone((u32)pid) ? 1 : 0;
}

// Gcutscene-npc-flicker-2 (cycle 3) — L'ETAT VIVANT DU RECENSEMENT, POUR L'ECRAN DE L'OWNER.
// Rend un entier compose, lu par draw-pc-fps-counter (pc/pckernel.gc) pendant une cinematique :
//   bit 0        une cinematique est recensee
//   bits 1..16   cycles de cause defectueuse fermes dans la scene en cours (plafonne a 65535)
//   bits 17..32  blinks (episodes trop courts pour compter)
//   bits 33..40  cause du dernier cycle (Reason + 1 ; 0 = aucun)
//   bits 41..56  coupes de camera / masquages voulus
// Un seul entier, sans allocation GOAL : on l'appelle a chaque image sans rien fuir.
u64 pc_npc_census_live() {
  const npc_flicker::Live l = npc_flicker::live_status();
  auto cap16 = [](u64 v) { return v > 0xffff ? (u64)0xffff : v; };
  u64 r = l.in_scene ? 1 : 0;
  r |= cap16(l.cycles) << 1;
  r |= cap16(l.blinks) << 17;
  r |= ((u64)(l.last_reason < 0 ? 0 : (l.last_reason + 1)) & 0xff) << 33;
  r |= cap16(l.coupes) << 41;
  return r;
}

// Gloading-screen (owner 2026-08-30) — la cadence REELLE de l'ecran de chargement et le decoupage
// du travail GOAL qui la detruit. Voir game/system/load_gate.h : `LOADSCREEN-GAP` se tait des que
// la barriere de residence s'ouvre, c'est-a-dire exactement au moment que l'owner decrit
// (« l'animation freeze sur la FIN »). Ces quatre ponts donnent a GOAL une VRAIE horloge : la
// sienne est plafonnee a 4 frames d'increment sur l'appareil et sous-estime un gel par
// construction.
void pc_loading_screen_tick(s32 hold_mask) {
  load_gate::loading_screen_tick(hold_mask);
}

void pc_loading_screen_end() {
  load_gate::loading_screen_end();
}

// Gloading-screen-window : l'ENCADREMENT. Voir game/system/load_gate.h.
void pc_lswin_open(u32 label) {
  load_gate::loading_window_open(label ? Ptr<String>(label).c()->data() : nullptr);
}

void pc_lswin_level(u32 name, s32 drawable) {
  load_gate::loading_window_level(name ? Ptr<String>(name).c()->data() : nullptr, drawable);
}

void pc_lswin_frame(s32 held, s32 black) {
  load_gate::loading_window_frame(held, black);
}

void pc_lswin_actors(s32 spawn_on, s32 sweep_complete) {
  load_gate::loading_window_actors(spawn_on, sweep_complete);
}

void pc_lswin_note(u32 what, s32 value) {
  load_gate::loading_window_note(what ? Ptr<String>(what).c()->data() : nullptr, value);
}

void pc_lswin_close(u32 why) {
  load_gate::loading_window_close(why ? Ptr<String>(why).c()->data() : nullptr);
}

void pc_goal_slice_begin(s32 slot) {
  load_gate::goal_slice_begin(slot);
}

s32 pc_goal_slice_expired(s32 slot) {
  const char* boundary = std::getenv("OG_BOOT_REPLAY_BOUNDARY");
  if (!boundary || std::strcmp(boundary, "actors-sweep") || !boot_replay::active()) {
    return load_gate::goal_slice_expired(slot);
  }

  boot_replay::checkpoint("goal-slice-slot", &slot, sizeof(slot));
  s32 expired = load_gate::goal_slice_expired(slot);
  boot_replay::input("goal-slice-expired", &expired, sizeof(expired));
  if (expired != 0 && expired != 1) {
    std::fprintf(stderr, "[boot-replay] invalid goal-slice-expired=%d for slot=%d\n", expired,
                 slot);
    std::fflush(stderr);
    std::abort();
  }
  return expired;
}

// Grecharged-grass-poc: push the "recharged grass" on/off toggle from GOAL
// (-> *pc-settings* recharged-grass?) down to the renderer. 0 = off (stock).
void pc_set_recharged_grass(u32 on) {
  recharged_gating::set(recharged_gating::kGrass, (on != 0));
}

// External-asset-root: toggle runtime custom texture replacements (user PNGs
// under <root>/custom_assets/texture_replacements). 0 = off (stock).
void pc_set_load_custom_assets(u32 on) {
  recharged_gating::set(recharged_gating::kLoadCustomAssets, (on != 0));
}

// Grecharged-bundled-textures: 0/1 toggle for the package-bundled first-party replacement
// textures (base albedo swaps only; the bundle's PBR maps follow the PBR path instead).
void pc_set_recharged_textures(u32 on) {
  // Grecharged-texture-hotreload : SEUL ecrivain de ce drapeau — la rangee du menu l'appelle au
  // geste (progress-pc.gc), et `update-to-os` le rappelle a CHAQUE image avec la valeur du champ.
  // C'est donc le seul point ou un stimulus de preuve peut tenir : pose plus bas, il serait
  // efface a l'image suivante. Identite hors mesure (voir hotreload_stimulus).
  recharged_gating::set(recharged_gating::kTextures, custom_tex::hotreload_stimulus(on != 0));
}

// Grecharged-managed-assets: 0/1 toggle for the DOWNLOADED texture pack. The
// loader consults it through Gfx::recharged_active, and a change invalidates
// the pack index so the next level load picks the new state up.
void pc_set_managed_assets(u32 on) {
  const bool v = (on != 0);
  // La comparaison porte sur la valeur VOULUE : le champ, lui, porte desormais la valeur
  // effective (stock des qu'un ancetre est eteint), et le comparer declencherait l'invalidation
  // au basculement d'un PARENT au lieu de celui de cette option.
  if (recharged_gating::desired(recharged_gating::kManagedAssets) != (v ? 1.0 : 0.0)) {
    recharged_gating::set(recharged_gating::kManagedAssets, v);
    managed_assets::invalidate();
    lg::info("managed assets: {} by setting", v ? "enabled" : "disabled");
  }
}

// Grecharged-master-toggle: push the GLOBAL Recharged master from GOAL
// (-> *pc-settings* recharged-master?). 0 = every recharged feature forced to its stock
// state via Gfx::recharged_active() (the individual flags keep the user's values, so the
// configuration comes back exactly when the master returns ON). Logs on CHANGE only
// (pushed every frame by update-to-os), so a device log proves the GOAL->C++ link.
void pc_set_recharged_master(u32 on) {
  bool v = (on != 0);
  // Valeur VOULUE et non le champ : celui-ci porte la valeur effective depuis
  // recharged_gating, et un parent eteint y ecrit stock — le log ne doit parler que du geste.
  if (v != (recharged_gating::desired(recharged_gating::kMaster) != 0.0)) {
    lg::info("[recharged-master] toggle -> {}", v ? "ON" : "OFF");
  }
  recharged_gating::set(recharged_gating::kMaster, v);
}

// Glighting-hdr / SPEC-refonte-lumiere §6.2: push the ECLAIRAGE RECHARGE master from GOAL
// (-> *pc-settings* recharged-lighting?). This is THE root of the lighting overhaul, and it is
// NOT the project master: OFF restores Naughty Dog's lighting and keeps every other Recharged
// layer (HD models, grass, textures, HUD) untouched. Every lighting gate composes it through the
// single Gfx::lighting_active() helper, which ANDs it with recharged_master_active(). Replaces
// pc-set-rt-light!'s role as "the lighting switch" — that one only ever picked the A/B composite,
// which is exactly what misled the owner on 2026-09-06 (HDR kept running with it OFF).
// Logs on CHANGE only (pushed every frame by update-to-os), so a device log proves the link.
void pc_set_recharged_lighting(u32 on) {
  bool v = (on != 0);
  // Valeur VOULUE et non le champ : celui-ci porte la valeur effective depuis
  // recharged_gating, et un parent eteint y ecrit stock — le log ne doit parler que du geste.
  if (v != (recharged_gating::desired(recharged_gating::kLighting) != 0.0)) {
    lg::info("[recharged-lighting] toggle -> {}", v ? "ON" : "OFF");
  }
  recharged_gating::set(recharged_gating::kLighting, v);
}

// water-ocean-mesh (SPEC-refonte-eau §1.2 regle 1, §7) : le maitre de la refonte EAU, pousse par
// image depuis `update-to-os` (hud-classes-pc.gc) comme son jumeau lumiere. Les portes d'eau ne
// lisent JAMAIS ce champ : elles passent par Gfx::water_active().
void pc_set_recharged_water(u32 on) {
  bool v = (on != 0);
  // Valeur VOULUE et non le champ : celui-ci porte la valeur effective depuis
  // recharged_gating, et un parent eteint y ecrit stock — le log ne doit parler que du geste.
  if (v != (recharged_gating::desired(recharged_gating::kWater) != 0.0)) {
    lg::info("[recharged-water] toggle -> {}", v ? "ON" : "OFF");
  }
  recharged_gating::set(recharged_gating::kWater, v);
}

// hdr-display-output : sortie HDR vers l'ECRAN (distincte du calcul HDR interne ci-dessus).
// Masque des modes reellement disponibles (systeme ET presentation) ; 0 = rangee cachee.
u64 pc_get_hdr_output_modes() {
  return hdr_output::modes_available();
}
// Le reglage du joueur (-> *pc-settings* hdr-output?). Prend effet a l'image suivante, fil GL.
void pc_set_hdr_output(u32 on) {
  hdr_output::set_enabled(on != 0);
  // Cette option n'a pas de champ dans GfxGlobalSettings : sa porte reste dans hdr_output.cpp.
  // recharged_gating en suit la valeur voulue, pour le grisage du menu et le recensement.
  recharged_gating::set(recharged_gating::kHdrOutput, on != 0);
}
// kind 0 = visibilite de la rangee (value 0/1) ;
// kind 1 = reglage etabli (value bit0 = valeur, bit1 = source auto-configuration) ;
// kind 2 = ou vit la rangee (value 1 = sous RECHARGED > RECHARGED LIGHTING, 0 = ailleurs),
//          trouve par GOAL en scrutant ses tableaux.
void pc_hdr_output_note(u32 kind, u32 value) {
  if (kind == 0) {
    hdr_output::note_option_visible((int)value);
  } else if (kind == 1) {
    hdr_output::note_setting_loaded((int)(value & 1), (int)((value >> 1) & 1));
  } else {
    hdr_output::note_menu_parent((int)value);
  }
}
// hdr-output-regime : ce que la ligne de menu doit DIRE. Empaquete pour le pont GOAL, qui ne
// passe que des entiers : format_id * 16 + regime (format_id = hdr_output::Format,
// regime 0 = aucune marge, 1 = marge accordee au retro-eclairage, 2 = l'ecran presente).
u64 pc_get_hdr_output_state() {
  return (u64)hdr_output::menu_state_packed();
}
// Ce que GOAL a REELLEMENT ecrit dans le libelle. La preuve compare a ce que le C++ sait.
void pc_hdr_output_label_note(u32 transport, u32 regime, u32 len) {
  hdr_output::note_menu_label((int)transport, (int)regime, (int)len);
}

// Grecharged-grass-overhang: push the "grass overhang" on/off toggle from GOAL
// (-> *pc-settings* recharged-grass-overhang?). 0 = off (walkable-top grass only, stock
// alpha overhang texture at every distance).
#ifdef OG_FEAT_GRASS_OVERHANG
void pc_set_grass_overhang(u32 on) {
  recharged_gating::set(recharged_gating::kGrassOverhang, (on != 0));
}
#endif

// lighting-ao-indirect — L'ANCIENNE AO EST SUPPRIMEE, PAS DEBRANCHEE (refus owner 2026-09-10 :
// « l'ancienne faut la degager complet j'ai peur que ca se colisionne »).
//
// CE QUI VIVAIT ICI. Un verrou « safe-boot » de l'ere du composite d'image (defect #6) : une
// sentinelle posee sur le disque des que l'AO s'allumait, et si la session mourait dans les 60 s
// qui suivaient, le boot SUIVANT epinglait l'AO a 0 pour la course entiere. Il gardait un
// estimateur qui n'existe plus tel quel — le mega-draw GTAO High qui declenchait le chien de
// garde KGSL est decoupe en bandes depuis (AmbientOcclusion.cpp) — et il avait un effet de bord
// que l'owner ne pouvait pas distinguer d'une panne : sa ligne de menu affichait HBAO et le
// moteur restait a zero, en silence. Un correctif d'hier devenu le defaut d'aujourd'hui.
//
// CE QUI LE REMPLACE : trois compteurs qui rendent son absence FALSIFIABLE. `ao_push_frames` est
// le denominateur (GOAL pousse le reglage a chaque image) ; `ao_push_open_frames` est la
// precondition comptee A PART, sans quoi un zero obtenu parce que l'eclairage est eteint serait
// indiscernable d'un zero obtenu parce que rien n'altere le reglage ; `ao_push_altered_frames`
// est le defaut lui-meme : une image ou la valeur envoyee par GOAL n'est pas celle que la porte
// du moteur porte. Avec le verrou, il montait. Sans lui, il reste a zero et on peut le dire.
namespace {
uint64_t s_ao_push_frames = 0;       // pushes GOAL vus (denominateur)
uint64_t s_ao_push_open_frames = 0;  // ... dont les ancetres etaient allumes (precondition)
uint64_t s_ao_push_altered = 0;      // ... ou la porte ne portait PAS la valeur poussee
}  // namespace

// Grecharged-ambient-occlusion: push the AO algorithm selector + quality + strength from GOAL
// (-> *pc-settings* ambient-occlusion / ao-quality / ao-strength). mode: 0 off / 1 SSAO / 2 HBAO
// / 3 GTAO; quality: 0 low / 1 medium / 2 high; strength: 0 weaker / 1 default / 2 stronger. Logs
// on CHANGE only (pushed every frame by update-to-os), so a device log proves the GOAL->C++ link.
void pc_set_ambient_occlusion(u32 mode, u32 quality, u32 strength) {
  int m = (int)mode;
  int q = (int)quality;
  if (m < 0 || m > 3) {
    m = 0;
  }
  if (q < 0 || q > 2) {
    q = 1;
  }
  int s = (int)strength;
  if (s < 0 || s > 2) {
    s = 1;
  }
  // Les trois "valeurs precedentes" sont les valeurs VOULUES : sous un ancetre eteint les trois
  // champs valent stock, et les comparer ferait re-loguer a chaque image.
  if ((double)m != recharged_gating::desired(recharged_gating::kAoMode) ||
      (double)q != recharged_gating::desired(recharged_gating::kAoQuality) ||
      (double)s != recharged_gating::desired(recharged_gating::kAoStrength)) {
    lg::info("[recharged-ao] mode -> {} quality -> {} strength -> {}", m, q, s);
  }
  recharged_gating::set(recharged_gating::kAoMode, m);
  recharged_gating::set(recharged_gating::kAoQuality, q);
  recharged_gating::set(recharged_gating::kAoStrength, s);

  // L'OPTION PILOTE-T-ELLE LE MOTEUR ? On compare la valeur que GOAL vient d'envoyer a celle que
  // la porte porte reellement, relue par l'autre bout de la chaine. Ce n'est pas un miroir : a
  // gauche l'argument BRUT du pont, a droite la valeur composee de la table des portes
  // (master > eclairage > ao-mode). On passe par `effective`/`disabled_by_ancestor` et non par
  // `mode()`, qui incrementerait les compteurs eval/exec que le balayage de `recharged-gating-real`
  // lit — un instrument n'a pas le droit d'en fausser un autre.
  const bool ao_ancestors_on = !recharged_gating::disabled_by_ancestor(recharged_gating::kAoMode);
  const int ao_gate_mode = (int)std::lround(recharged_gating::effective(recharged_gating::kAoMode));
  s_ao_push_frames++;
  if (ao_ancestors_on) {
    s_ao_push_open_frames++;
    if (ao_gate_mode != (int)mode) {
      s_ao_push_altered++;
    }
  }
  autoport_proof::publish("ao_push_frames", s_ao_push_frames);
  autoport_proof::publish("ao_push_open_frames", s_ao_push_open_frames);
  autoport_proof::publish("ao_push_altered_frames", s_ao_push_altered);
}

// Grecharged-foliage-wind: push the light-wind sway toggle from GOAL (pc-set-foliage-wind!).
// 0 = off => byte-identical stock render (no palm/shrub displacement). Logs on CHANGE only
// (update-to-os pushes this every frame), so a device log proves the GOAL->C++ link.
void pc_set_foliage_wind(u32 on) {
  bool v = (on != 0);
  // Valeur VOULUE : le champ porte l'effective, un parent eteint y ecrit stock.
  if (v != (recharged_gating::desired(recharged_gating::kFoliageWind) != 0.0)) {
    lg::info("[foliage-wind] toggle -> {}", v ? "ON" : "OFF");
  }
  recharged_gating::set(recharged_gating::kFoliageWind, v);
}

// Grecharged-title-logo-fullres: push the CRISP TITLE LOGO toggle from GOAL
// (pc-set-crisp-title-logo!). ON draws the title-screen JAK AND DAXTER logo (and the ND boot logo)
// at NATIVE resolution while the 3D world stays at RENDER SCALE. 0 = stock pipeline. Logs on
// CHANGE only (update-to-os pushes this every frame), so a device log proves the GOAL->C++ link.
void pc_set_crisp_title_logo(u32 on) {
  bool v = (on != 0);
  // Valeur VOULUE : le champ porte l'effective, un parent eteint y ecrit stock.
  if (v != (recharged_gating::desired(recharged_gating::kCrispTitleLogo) != 0.0)) {
    lg::info("[crisp-logo] toggle -> {}", v ? "ON" : "OFF");
  }
  recharged_gating::set(recharged_gating::kCrispTitleLogo, v);
}

// lighting-legacy-purge (2026-09-11) : `pc_set_mesh_subdiv_rounds` est SUPPRIME. La
// pre-subdivision qu'il pilotait n'etait atteignable que sous DISPLACEMENT = 2
// (TESSELLATION), un mode jamais livre et retire par cet item.

// Grecharged-hd-models: push the "enhanced models" on/off toggle from GOAL
// (-> *pc-settings* recharged-enhanced-models?). 0 = off (stock low-poly). Applies live to
// village FR3 (Samos/Keira); the common FR3 (Jak/Daxter) is seeded from persisted settings at
// renderer init, so toggling those takes effect on relaunch.
#ifdef OG_FEAT_HD_MODELS
void pc_set_recharged_enhanced_models(u32 on) {
  // Grecharged-hd-models2 discriminator: the GOAL side pushes this EVERY frame from *pc-settings*
  // (update-to-os), so a push of the pre-settings-load default silently flips the renderer-ctor
  // seed and later level loads read STOCK fr3. Log transitions so runs carry the flip evidence.
  bool v = (on != 0);
  // Les DEUX lectures (le test et l'ancienne valeur imprimee) sont la valeur VOULUE : le champ
  // porte l'effective, et sous un master eteint il vaut stock a chaque image.
  const bool prev = (recharged_gating::desired(recharged_gating::kEnhancedModels) != 0.0);
  if (v != prev) {
    // lg (not raw stdout): on Android only lg::* routes to logcat.
    lg::info("HD-MODELS toggle push: {} -> {}", prev, v);
  }
  recharged_gating::set(recharged_gating::kEnhancedModels, v);
}

// Grecharged-hd-models4: per-actor coverage registry (global-scope prototypes above, before
// namespace jak1). An HD companion process registers which driver actor (pid) its merc
// submissions replace; Merc2 only suppresses a stock draw whose OWN pid is covered by an
// actively-found companion, so uncovered same-model actors (the ND-logo eichar) always keep
// their stock draw.
void pc_hd_cover(u32 companion_pid, u32 driver_pid) {
  ::merc2_hd_cover(companion_pid, driver_pid);
}
void pc_hd_uncover(u32 companion_pid) {
  ::merc2_hd_uncover(companion_pid);
  // Ghd-skin-origin-stretch : le rig N'EST PAS oublie ici. `pc-hd-uncover!` est aussi appele
  // PENDANT la vie du compagnon (jak-hd.gc, miroir hidden : uncover puis cover), et le rig n'est
  // enregistre qu'une fois par vie — mesure x86 c6inj1 : `norig=11818` paquets HD sans rig,
  // `rigs=0`. Les pids GOAL ne sont jamais reutilises (gkernel.gc, next-pid monotone) : Merc2
  // purge les rigs non vus depuis 3000 images, comme ses autres memoires par pid.
}
// Ghd-skin-origin-stretch : GOAL declare, joint par joint, le rig du compagnon HD — parent,
// joint PILOTE e lu par k dans le modele stock (255 = aucun), mode de reciblage (0 monde,
// 1 local, 2 colle, 3 orientation) et position de bind (`jgeo data k`) — pour que Merc2 mesure
// chaque os CONSOMME par le GPU contre sa longueur de repos (HDSKINLEN) et contre la pose que
// l'animation du pilote lui COMMANDE (HDCMD). Les positions arrivent en ENTIERS x64 (resolution
// 1/64 u, soit 0,004 mm) : aucun float ne traverse la frontiere FFI ici, meme regle que le bloc
// physique ci-dessous. parent = -1 (ou tout hors [0,128)) = racine.
// HUIT ARGUMENTS : (pid k parent e mode ix iy iz). Ils ne passent PAS par
// make_function_symbol_from_c — la rampe x86 `_arg_call_systemv` (asm_funcs_x86_64.asm:7-37) ne
// transmet au C que les 6 registres SysV ; les arguments GOAL 7 et 8 (r10, r11) y sont empiles
// pour etre SAUVES, pas lus, et un C a 8 parametres lirait iy/iz dans la sauvegarde de xmm8.
// La rampe a tableau (`_stack_call_systemv` :47-70, `_stack_call_arm64`) collecte les 8
// registres GOAL et passe le tableau : c'est la liaison de `_format`, `link` et `rpc-call`.
u64 pc_hd_skel_joint(u64* args) {
  const u32 pid = (u32)args[0];
  const int k = (int)(s64)args[1];
  const int parent = (int)(s64)args[2];
  const int e = (int)(s64)args[3];
  const int mode = (int)(s64)args[4];
  const s64 ix = (s64)args[5], iy = (s64)args[6], iz = (s64)args[7];
  ::merc2_hd_skel_joint(pid, k, parent, e, mode, ix / 64.f, iy / 64.f, iz / 64.f);
  return 0;
}
// Ghd-skin-origin-stretch : L'ANNEAU GOAL. Le squelette GOAL etait PROPRE a l'image ou le GPU
// consommait des chaines de 4,5 m ; comme pos = [bindpos,1].bindinv.W.cam = W.t.cam exactement,
// les translations consommees different de celles ecrites. GOAL enregistre une fois les trois
// adresses de `*hd-ring*` / `*hd-ring-cam*` / `*hd-ring-stamp*` (offsets dans ee_main_memory) et,
// par compagnon, son emplacement (0..10) ; Merc2 relit la cellule de l'image du paquet et
// compare, par os, ce que GOAL a ecrit a ce qu'il consomme (sonde HDRING). Trois et deux
// arguments : rampe classique, comme pc-hd-cover!.
void pc_hd_ring(u32 ring_addr, u32 cam_addr, u32 stamp_addr) {
  ::merc2_hd_ring(ring_addr, cam_addr, stamp_addr);
}
void pc_hd_ring_slot(u32 pid, u32 slot) {
  ::merc2_hd_ring_slot(pid, (int)slot);
}

// ─── recharged-secondary-motion — LA PORTE, ASSEMBLEE LA OU LE SOLVEUR ECRIT ────────────
// Appele par `jak-hd-physics.gc` a chaque maillon ECRIT, donc 4 fois par image quand les deux
// chaines de keira-hd sont resolues. Trois roles, et un seul appel pour les trois :
//   1. dire a Merc2 quel joint juger (il ne peut pas le deviner : ces joints n'existent pas
//      dans le modele stock) ;
//   2. remplir `hits=` de la ligne FEATURE avec CE QUI A REELLEMENT TOURNE — un maillon ecrit,
//      pas une image dessinee. `note_hit` est un compteur PARTAGE avec les autres items du
//      binaire : `sm_links_written` publie SON denominateur a cote, sinon un `hits` non nul
//      venu d'ailleurs se lirait comme « la physique a tourne » ;
//   3. publier la grandeur de la porte. Publier ici plutot que dans le battement de
//      `hd-len-scan!` la rend independante de `*hd-stretch-arm*`, qui appartient a un AUTRE item.
// LE PLAFOND, RECOPIE DU DOCUMENT. `SPEC-breast-softbody.md` §22 « Dynamic Soft Limits »
// (l.298-306), verbatim :
//     Local tissue elongation: common 5-15%, large 15-21%, exceptional 21-25%
//     Absolute stretch clamp:  25%
// Owner, 2026-08-28, en jeu : « ils s'allongent enormement sur des mouvements brusques ».
// AUCUN NOMBRE CHOISI ICI : 1250 est le « 25% » que la ligne ci-dessus ecrit, en millienes.
static constexpr u64 kSmStretchClampX1000 = 1250;

void pc_hd_phys_joint(u32 pid, u32 k, u32 rmax_x1000, u32 rmin_x1000, u32 cmax_x1000) {
  ::merc2_hd_phys_joint(pid, (int)k, 1);
  static u64 s_links_written = 0, s_goal_judged = 0, s_goal_over = 0, s_goal_worst_x1000 = 0;
  static u64 s_cmd_worst_x1000 = 0, s_clamp_hits = 0, s_squash_worst_x1000 = 0;
  s_links_written++;
  autoport_proof::note_hit();
  // BRAS SQUELETTE : `rmax`/`rmin` sont les rapports base LIVREE / base ANIMEE, deja formes par
  // le solveur sur la matrice qu'il vient d'ecrire.
  //
  // UNE SEULE DIRECTION, LA HAUSSE — ET C'EST LA MESURE APPAREIL DU 2026-09-07 QUI L'A DIT.
  // La premiere version de ce verdict prenait le pire des DEUX sens, `max(rmax, 1/rmin)`. Course
  // appareil 06:00, 3 840 images : `sm_skel_over=6` avec un pire a 1,383 alors que le COMMANDE en
  // hausse plafonnait a 1,372 et que le plafond avait morde 53 fois — un pire LIVRE au-dessus du
  // COMMANDE est arithmetiquement impossible dans le sens de la hausse, donc les 6 venaient de
  // l'ECRASEMENT (1/0,723 = 1,383). Or §10 l.165 PRESCRIT une contraction de -30 %
  // (`SupineProjectionScale = 0.70`) et §22 l.303 ecrit « elongation » et « stretch » : un
  // verdict bilateral compte comme defaut ce que la spec COMMANDE. Meme arbitrage que [NOTE-586]
  // (2026-08-20 13:20), applique ici au verdict et plus seulement a l'operateur.
  // L'ecrasement reste PUBLIE (`sm_skel_squash_worst_x1000`) : il n'est pas juge, il est lisible.
  // `rmin = 0` = une ligne EFFONDREE, matrice degeneree : celle-la entre dans le verdict, sinon
  // elle passerait en silence comme un NaN passe tout predicat de comparaison.
  s_goal_judged++;
  if (rmax_x1000 > s_goal_worst_x1000) {
    s_goal_worst_x1000 = rmax_x1000;
  }
  if (rmax_x1000 > kSmStretchClampX1000 || rmin_x1000 == 0) {
    s_goal_over++;
  }
  if (rmin_x1000 > 0) {
    const u64 sq = 1000000ull / rmin_x1000;
    if (sq > s_squash_worst_x1000) {
      s_squash_worst_x1000 = sq;
    }
  }
  // CE QUE L'OPERATEUR COMMANDAIT, avant le plafond de §22 l.303. Sans cette valeur, « le
  // plafond a mordu » et « le canal est muet » rendent tous les deux `sm_skel_worst = 1250`, et
  // la porte serait un miroir d'elle-meme. `sm_clamp_hits` est le canal PROUVE LU : il compte les
  // maillons ou le plafond a effectivement retranche, pas les fois ou on le lui a demande.
  if (cmax_x1000 > s_cmd_worst_x1000) {
    s_cmd_worst_x1000 = cmax_x1000;
  }
  if (cmax_x1000 > kSmStretchClampX1000) {
    s_clamp_hits++;
  }
  // LA PORTE : le bras SQUELETTE, et lui seul. Il compare la base LIVREE a la pose COMMANDEE de
  // la MEME image — les deux membres sont dans le meme etat, donc l'ecart est l'etirement que la
  // physique ajoute, et rien d'autre.
  //
  // POURQUOI LE BRAS GPU N'ENTRE PAS (ENCORE) DANS LE VERDICT. Sa reference n'est pas la pose
  // commandee mais le BIND compose par le reciblage (`bindinv . W . cam`) ; le lien entre les
  // deux references n'est pas mesure. Ce que la mesure dit, et rien de plus : son PLANCHER vaut
  // 1,005 sur la course appareil du 2026-09-07 (donc sa reference est bien ~1, l'hypothese d'une
  // echelle geometrique de 1,30 est REFUTEE), et le plafond du bras squelette ne le borne pas par
  // construction puisque `bindinv` MELANGE les lignes de W. Il est publie en entier — compte,
  // denominateur, plancher, pire en hausse — pour que l'essai suivant puisse le promouvoir sur
  // une mesure et pas sur un raisonnement. Sa fidelite a ce que GOAL ecrit est deja tenue par
  // l'acquis `hd_bones_stretched` (`hd_gpu_ring_bad=0`).
  autoport_proof::publish("secondary_motion_defects", s_goal_over);
  autoport_proof::publish("sm_skel_over", s_goal_over);
  autoport_proof::publish("sm_skel_judged", s_goal_judged);
  autoport_proof::publish("sm_skel_worst_x1000", s_goal_worst_x1000);
  autoport_proof::publish("sm_skel_squash_worst_x1000", s_squash_worst_x1000);
  autoport_proof::publish("sm_cmd_worst_x1000", s_cmd_worst_x1000);
  autoport_proof::publish("sm_clamp_hits", s_clamp_hits);
  autoport_proof::publish("sm_gpu_over", ::merc2_sm_diag(0));
  autoport_proof::publish("sm_gpu_judged", ::merc2_sm_diag(1));
  autoport_proof::publish("sm_gpu_worst_x1000", ::merc2_sm_diag(2));
  autoport_proof::publish("sm_gpu_floor_x1000", ::merc2_sm_diag(3));
  autoport_proof::publish("sm_gpu_stretch_over", ::merc2_sm_diag(4));
  autoport_proof::publish("sm_gpu_stretch_worst_x1000", ::merc2_sm_diag(5));
  autoport_proof::publish("sm_links_written", s_links_written);
}
#endif

// Grecharged-secondary-motion: data-driven secondary-motion (chain physics) parameter store + FFI.
// The GOAL side owns no floats across the FFI boundary here: EVERY value-returning entry point below
// returns MILLI-units (llround(value * 1000.0)) as an s64, and the caller divides by 1000. That keeps
// the whole surface int-FFI (the pc-set-rt-ambient-strength! convention) with 3 decimals of headroom,
// which is more than the authored data carries.
#ifdef OG_FEAT_PHYSICS
// Pushed every frame from (update-to-os) via pc-set-physics!, exactly like the HD-MODELS toggle.
static bool s_physics_on = false;
static int s_physics_level = 1;

// Defined further down with the parameter store; forward-declared so the toggle push below can
// trigger a re-parse without moving the store above its own dependencies.
static int pc_physics_parse_file();

// FORCAGE DE MESURE — `physics?` EST UN REGLAGE DE MENU PERSISTE, ET SUR LE REDMI IL EST A #f.
// Mesure du 2026-09-07 : `/storage/emulated/0/OpenGOAL/jak1/settings.ini` ligne 98 porte
// `physics? = #f`, et le journal de la course appareil de 05:38 le dit sans ambiguite —
// `[hd-phys] toggle push: false lvl 1 -> false lvl 2`, zero maillon ecrit, donc une porte qui
// aurait rendu « 0 defaut » sur un solveur ETEINT. C'est exactement `OFF = inexistant`.
// Le defaut LIVRE par le jeu est `#t` (pckernel-impl.gc:393) : ce drapeau ne modifie donc pas le
// binaire de l'owner, il remet la valeur d'usine le temps d'une mesure, et RIEN n'est ecrit dans
// le fichier de reglages du telephone — on ne touche pas la config de l'owner.
// Env (bureau) ou propriete (appareil), comme tous les leviers de ce fichier : une variable
// d'environnement seule est MUETTE sur Android, l'application ne recoit pas l'environnement du
// shell qui la lance.
static bool phys_force_on() {
  static int s_v = -1;
  if (s_v < 0) {
    s_v = 0;
    if (const char* e = std::getenv("OG_PHYSICS_FORCE")) {
      if (e[0] && std::strcmp(e, "0") != 0) {
        s_v = 1;
      }
    }
#if defined(__ANDROID__)
    if (!s_v) {
      char b[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.physics", b) > 0 && b[0] && std::strcmp(b, "0") != 0) {
        s_v = 1;
      }
    }
#endif
  }
  return s_v != 0;
}

void pc_set_physics(u32 on, u32 level) {
  bool v = (on != 0) || phys_force_on();
  int lv = (int)level;
  if (v != s_physics_on || lv != s_physics_level) {
    // lg (not raw stdout): on Android only lg::* routes to logcat.
    lg::info("[hd-phys] toggle push: {} lvl {} -> {} lvl {}", s_physics_on, s_physics_level, v, lv);
    // Owner iteration loop: flipping the physics toggle (or the precision level) in the menu is the
    // documented way to re-read a hot-pushed physics_chains.txt. Re-parsing here bumps the
    // generation, and every live sim slot re-binds its chains on its next step. (The parse marks
    // the store loaded itself, so a toggle arriving before the first ensure_loaded() does not get
    // followed by a second, redundant parse. Generation is an opaque change token, never a count.)
    pc_physics_parse_file();
  }
  s_physics_on = v;
  s_physics_level = lv;
}

// ---- recharged_assets/physics_chains.txt parameter store -------------------------------------
// class bits: primary=1 secondary=2 accessory=4
enum PhysClassBits { kPhysClassPrimary = 1, kPhysClassSecondary = 2, kPhysClassAccessory = 4 };
// chain param ids (pc_physics_chain_param_mi):
//   0 stiffness(Hz) 1 damping 2 gravity 3 maxangle(deg) 4 inertia 5 stretch 6 radius(units)
//   7 rootlock(links pinned rigidly at the root) 8 gradient(root->tip freedom exponent)
//   9 animmode(0 keep / 1 replace / 2 excite) 10 excite(scale) 11 friction(0..1 contact)
// CYCLE 3 (owner 2026-08-06) — authored-animation priority, freedom floor, descendant policy:
//   12 authored(engage threshold: authored offset as a FRACTION of the chain's own length; 0 = off)
//   13 authrise(blend-in rate /s) 14 authfall(blend-out rate /s) 15 authstiff(stiffness x at w=1)
//   16 rootfree(floor of the root->tip freedom ramp, 0..1 — a SHORT chain must still bend)
//   17 nodesc(1 = do NOT rigid-re-glue this chain's descendants: they carry their own animation)
//   18 colskip(leading links exempt from BODY COLLISION — the chain's ATTACHMENT to the body sits
//      inside the body volume by construction. Until cycle 3 that exemption was implied by
//      rootlock=, so freeing a hair root to move would also have started colliding it with the
//      skull it is glued to: a permanent penetration no tuning could clear. The two ideas are
//      separated here — `rootlock` is "does this link move?", `colskip` is "is this link inside
//      the body on purpose?". Effective value is max(rootlock, colskip), so 0 = exactly the
//      pre-cycle-3 behaviour.)
//   19 mass(cycle 3b, owner K: "on ne sent pas la masse... trop leger et JELLY". Amplitude was not
//      the defect — the RESPONSE was. A heavier chain resists starting and keeps going once it has:
//      omega_eff = omega / sqrt(mass), so the natural frequency drops with real mass while the
//      swing envelope (cone + stretch) is untouched. 1.0 = the pre-cycle-3b spring.)
// CYCLE 4 (owner 2026-08-06 14:45, "as-tu defini un HAUT et un BAS, une MASSE ?"):
//   20 hang(0..1 — HOW MUCH OF THIS CHAIN'S REST DIRECTION IS GRAVITY'S rather than the animator's.
//      Gravity was already applied in WORLD space, but the chain's whole equilibrium was pinned to
//      the AUTHORED bone direction: the spring pulls to the authored pose and the swing cone is
//      centred on the authored direction, so a cuff modelled sticking out along a horizontal forearm
//      can only ever wobble around "forward" — which is exactly what the owner sees on Gol's sleeve.
//      hang= rebuilds the chain's rest pose each frame from world DOWN instead: rest_dir =
//      normalize(mix(authored_dir, (0,-1,0), hang)), link lengths preserved. 0 = the authored pose is
//      the rest pose (every pre-cycle-4 chain, unchanged); 1 = pure cloth, hangs straight down from
//      its anchor whatever the bone underneath is doing.)
//   21 swing(0..1 — how much of the chain's ROTATION reaches the bone. The write-back turns a bone by
//      swing(rest-direction -> simulated-direction) about its own origin, which for a one-link chain
//      pivots the whole mesh about the bone's root: the tip travels, the base does not. On a cloth
//      flap that is right; on a BREAST it is exactly the owner's "seuls les bouts de ses seins
//      bougent". Lowering swing keeps the full simulated TRANSLATION — so every vertex weighted to
//      the bone moves together, as a volume — while damping the pivot. 1.0 = pre-cycle-4 write-back.)
// CYCLE 5 (owner 2026-08-06) — MANDATORY per-chain FAMILY, and the geometry a chain needs to be
// judged against the model instead of against itself:
//   22 family(0 = UNDECLARED / not classified, 1 = A, 2 = B. Declared in the data as a LETTER.
//      A = BODY: hair, chest, ears. Simulated at all times, but its equilibrium target is the
//      MODEL POSE — no lower (droop) and no higher. B = HANGS: straps, accessories, hanging
//      cloth. Gravity dictates its rest; it must NEVER be pulled back to the model pose. One
//      setting shared by both families is the defect this id exists to make detectable.)
//   23 side(0 = none/centred, 1 = L, 2 = R. Declared as a LETTER. Lets cross-side penetration be
//      accounted for by name — a left jacket flap crossing through the RIGHT leg is a different
//      failure from the same flap grazing its own leg.)
//   24 extent(UNITS of rigidly-skinned geometry hanging BELOW this chain's last bone. Jak's two
//      jacket pendants are one joint each with all the cloth underneath: colliding the bone point
//      proved nothing, the bone stayed outside the thigh while the cloth swept through the other
//      leg. Non-zero moves the collision test to the middle of that continuation and inflates the
//      radius to circumscribe it. 0 = the bone is the whole chain, i.e. every pre-cycle-5 line.)
//   25 anch(GAIN applied to the per-link `anp=` point of SPEC 31 — the fixed point the section
//      names, "r = 0 at chest attachment". 0 = the deformation tensor stays anchored on the BONE
//      ORIGIN, which is where it has always been and which the spec names nowhere; that is the
//      identity by algebra, not by tuning. 1 = anchored on the measured r=0 point. (C132)
//      Slot 25 previously CARRIED THE NAME `compress` — a cycle-5 idea that was documented and
//      never parsed, never read, and never present in any shipped data. It is reused here rather
//      than left as a second empty slot; nothing is lost, but do not read old notes about
//      `compress` as if this index held it.
// CYCLE 6 (owner 2026-08-07) — the audit's OWN positive control:
//   26 inject(UNITS by which this chain is DELIBERATELY displaced into the body, so the
//      penetration audit can be shown to FIRE before any zero it reports is believed. Three
//      vacuous zeros in a single day (resid/push, idledrift/idlewin, restdevA/restwin) are what
//      this id exists to make impossible: arm it, watch the counter rise, disarm it, watch it fall
//      back. Default 0 = OFF, and it MUST default off — a control left armed is a defect shipped.)
// CYCLE 7 (owner AB/AG, supervisor gate AH) — amplitude that does not cost firmness:
//   27 couple(ANCHOR COUPLING GAIN. A chain's only excitation until now was the lag it develops
//      behind its own moving target, and that lag is g/omega^2 — inversely proportional to the
//      SQUARE of the stiffness. So "plus de jiggle ET un poil plus de fermete" was literally
//      unreachable: every notch of firmness bought was paid for out of the travel, which is how
//      cycle 6 ended up "beaucoup plus FLASQUE" and still "ne bouge PAS ASSEZ". This adds the
//      pseudo-force of the accelerating anchor frame explicitly, scaled by this gain, so the
//      deviation equation becomes d'' + 2*zeta*w*d' + w^2*d = -(1 + couple)*a_anchor. Amplitude
//      is then set by `couple` and firmness by `stiffness`, independently. 0 = OFF and it MUST
//      default off: every chain that shipped before this cycle keeps its exact behaviour.)
// CYCLE 8 (owner, 11e passe 2026-08-11: « le bas de son pantacourt clipe toujours a l'interieur de
// ses mollets au lieu d'etre visible, comme si son pantacourt s'arretait aux genoux »):
//   28 shell(INNER RADIUS, in units, of the SLEEVE this link forms AROUND a limb — the distance
//      from that limb's axis out to the cloth. A pant flap is a CLOSED shell wrapped around the
//      calf, so its fitted radius (429 left / 443 right) is the radius of that sleeve, yet the
//      solver spends it as the radius of a PUSH-OUT SPHERE centred on the link: the flap's centroid
//      sits 95u from the calf axis — i.e. essentially ON it — so the contact test reads a ~700u
//      penetration and ejects the flap sideways every frame, burying half the cloth inside the leg.
//      Pushing a sleeve OUT of the limb it encircles is geometrically meaningless; what such a link
//      owes is CONCENTRICITY, and this id is how the engine is told which links are sleeves and how
//      wide. 0 = this link is not a sleeve, and 0 is the default of every chain that shipped before
//      this cycle, so adding the key moves nothing that does not declare it.)
//   30 lyield(C135 — GAIN on SPEC 11's DOUBLE-COUNT correction. The chain's own rigid stage
//      already delivers part of the root-to-apex elongation SPEC 11 asks for; until now the
//      deformation tensor was handed the TOTAL target anyway, so the delivered length overshot
//      (1.336 / 1.318 against a band of 1.18-1.26). The engine already MEASURES that rigid stage
//      each frame (`*phys-rsv*`, NOTE-574/575) and publishes it as PHYSRIGID. This gain says how
//      much of it to divide out of `HangingLengthScale` before the orientation mix:
//          phl_effective = phl / (1 + lyield * (rigide - 1))
//      0 = the tensor keeps receiving the TOTAL target — the divisor is 1 BY ALGEBRA, so 0 is
//      bit-identical to every build before this cycle and is therefore the default. 1 = the full
//      correction, which is exactly the c128 experiment. It is a GAIN and not a switch because
//      SPEC 11's two clauses (length band AND COM band) bound it from OPPOSITE sides: the
//      admissible window measured on two archived traces is [0.896, 0.931] for chestL and
//      [0.700, 0.816] for chestR. It is DATA, not a constant, so re-deriving it costs no build.)
//   31 medw(C137 — SPEC 10's MEDIAL WALL, in units, measured on the SHIPPED mesh. SPEC 10 asks for
//      « Outward COM migration per breast: 4-10% W0 » and the delivered organ migrates INWARD
//      (-2.26 / -7.16 % W0): a SIGN, not an amplitude. The tensor already widens the organ when
//      supine (`SupineWidthScale`, sx = 1.2257 / 1.2057) but it widens it ABOUT THE JOINT, so the
//      MEDIAL edge of the flesh crosses the sagittal plane it rests against. SPEC 10 l.174 says in
//      bold « The entire breast shall not simply scale uniformly from its center », and SPEC 8
//      l.145 « flattening redistributes material laterally ». This key is the distance from the
//      chain's ROOT JOINT to that medial boundary, along the chain's OUTWARD lateral axis, and the
//      engine slides the organ out by exactly the penetration the widening would otherwise cause:
//          d_out = medw * max(0, sx - 1)
//      It is a NON-PENETRATION, not a tuning value: `max(0, .)` makes it ONE-SIDED, because a
//      sternum resists compression of the medial boundary and never pulls. Consequences, all by
//      algebra and not by setting: standing sx = 1.0000 -> 0 (SPEC 2/9 « Additional Procedural Sag
//      = 0% » untouched); prone sx = 0.92 < 1 -> 0 (SPEC 11 untouched); side-lying sx = 0.80 on the
//      gravity side -> 0 (SPEC 12, one of the four HELD sections, untouched).
//      Measured on out/jak1/fr3/skin/keira-hd-lod0.glb: the `chest` joint sits exactly on the
//      sagittal plane (x = 0.000), the two roots at +/-379.90 u from it (exact mirror), and the
//      most medial flesh vertex of EACH breast at +54.24 u from that plane — identical on both
//      chains to 0.01 u, which is what makes it the sternum and not an outlier. Hence
//      medw = 379.90 - 54.24 = 325.66 (chestL) / 325.67 (chestR).
//      0 = the wall is ABSENT and the term is exactly 0 — bit-identical to every build before this
//      cycle, and therefore the default of every chain that does not declare it.)
//   32 rbrot(C140 — SPEC 37's ROTATION TRIGGER for the rebase, DECLARED IN DEGREES in the file and
//      STORED AS `1000 * (1 - cos(theta))` so the engine never needs a trig call. SPEC 37 l.441-444 asks
//      for a rebase on « animation root discontinuity ... or implausibly large one-frame transform
//      changes », and « artificial transforms must not generate physical breast impulses ». The
//      rebase ACTION already carries both halves (translation AND rotation, jak-hd-physics.gc
//      :2686-2694); its TRIGGER is a DISTANCE and nothing else — `rbd > 7 * b0`. An anchor that
//      spins in place therefore passes straight through it and the whole spin is delivered to the
//      chain as an impulse. This key is the angle above which one frame of anchor rotation is
//      declared implausible. It is OURS, not the document's: SPEC 37 names the class of event and
//      gives no number, so the value must be justified by the measured distribution and declared
//      as a choice (DIRECTIVES 2026-08-20 02:50).
//      THE SIGN IS THE ARM. A NEGATIVE angle = MEASURE ONLY (count the frames that would cross
//      |theta|, rebase nothing); a POSITIVE angle = measure AND rebase; 0 = the term is
//      unreachable, so the build is bit-identical to every build before this cycle, and that is
//      the default of every chain that does not declare the key.)
static constexpr int kPhysNumChainParams = 33;
// level param ids (pc_physics_level_param_mi):
//   0 substeps 1 iters 2 collide 3 classmask 4 fixedhz  -- ALSO returned in milli.
static constexpr int kPhysNumLevelParams = 5;
static constexpr int kPhysMaxLevels = 8;

struct PhysChain {
  std::string name;
  int class_bits = 0;
  //                                   0  1  2  3    4  5  6  7  8    9 10    11
  float params[kPhysNumChainParams] = {0, 0, 0, 0, 1.f, 0, 0, 0, 0, 1.f, 0, 0.5f,
                                       // 12 authored 13 authrise 14 authfall 15 authstiff
                                       // authored DEFAULTS OFF (0) ON PURPOSE. Cycle 2 removed jak1's
                                       // hand-keyed pseudo-WIND from physics-owned bones and the owner
                                       // re-confirmed at cycle 3 that it stays removed. A nonzero
                                       // default would let that same wind cross the engage threshold
                                       // and take the chain back — re-introducing the exact
                                       // double-writer the owner rejected. So authored priority is
                                       // OPT-IN, declared only on bones ND genuinely ACTS with.
                                       0.f, 8.f, 3.f, 4.f,
                                       // 16 rootfree 17 nodesc 18 colskip 19 mass
                                       // rootfree DEFAULTS to 0.3 — cast-wide by construction (owner
                                       // cycle-3 I). Without a floor the stiffest free link only ever
                                       // keeps 1/nfree of the swing cone, which is what left Jak's
                                       // 2-joint coiffe and Keira's short back hair reading as stiff.
                                       // It can only ever RAISE a link's freedom, never lower it, so
                                       // no already-accepted chain (Jak's straps at 0.75, Keira's
                                       // bangs at 0.5) is touched by the default.
                                       0.3f, 0.f, 0.f, 1.f,
                                       // 20 hang 21 swing — both default to the pre-cycle-4
                                       // behaviour EXACTLY (rest pose = the authored pose, full
                                       // rotation written back), so adding them cannot move a single
                                       // chain the owner has already accepted. They only do
                                       // something where the data asks for it.
                                       0.f, 1.f,
                                       // 22 family 23 side 24 extent 25 compress — all default to
                                       // 0 = UNDECLARED. family/side are letters in the data (A/B,
                                       // L/R) and 0 means the chain has not been classified at all;
                                       // extent/compress are units and 0 means "no allowance", so a
                                       // chain that never declares compress= may not compress.
                                       0.f, 0.f, 0.f, 0.f,
                                       // 26 inject — the penetration audit's POSITIVE CONTROL, and
                                       // the one param whose default is a safety property rather
                                       // than a behaviour: a control left armed ships a chain
                                       // buried in the body. 0 = disarmed.
                                       0.f,
                                       // 27 couple — anchor-coupling gain. 0 = the pre-cycle-7
                                       // excitation exactly (lag behind the moving target and
                                       // nothing else), so adding this key moves no chain that
                                       // does not ask for it.
                                       0.f,
                                       // 28 shell — sleeve inner radius in units. 0 = "this link
                                       // is not a sleeve", which is what every chain written
                                       // before cycle 8 says by omission, so the concentricity
                                       // constraint can only ever engage where the data asks.
                                       0.f,
                                       // 29 b0 — SPEC 6's B0: the ROOT-TO-APEX length of the FLESH,
                                       // in units, measured on the mesh. NOT the bone length: on
                                       // Keira the bone chest->lBoob is 977 u while the tissue runs
                                       // 602 u, so a bound expressed "in B0" against the bone is
                                       // 1.62x too loose and SPEC 22's apex ceiling cannot fire.
                                       // 0 = UNDECLARED, and the engine then falls back to the bone
                                       // length exactly as before — so adding this key moves no
                                       // chain that does not carry it.
                                       0.f};
  std::vector<std::string> joints;   // ordered root -> tip
  std::vector<float> link_radius;    // radii= : per-LINK collision radius, mesh-derived
  // comw= : per-LINK share of the organ's skin mass, mesh-derived, ONE PER LINK root -> tip.
  // SPEC 6 defines `P0` as the breast CENTER-OF-MASS position and SPEC 22 bounds "Breast COM";
  // a centre of mass is a MASS-WEIGHTED MEAN, so the reader of a per-link excursion needs the
  // per-link mass to form it. Under linear blend skinning the identity is exact:
  //   d_COM = (1/N) * SUM_j W_j * (M_j^sim - M_j^auth) * c_j,   comw[l] = W_l / N.
  // The anchored flesh (chest, shoulder) is NOT listed: it is not simulated, its excursion is
  // zero by construction, and it is accounted for by the weights summing to LESS than 1.
  // 0/absent = UNDECLARED, and the engine then publishes no COM at all rather than a wrong one,
  // so adding this key moves no chain that does not carry it.
  std::vector<float> link_comw;
  // spr= : SPEC 31 « r = 0 at chest attachment and r = 1 at distal/apex region ». UNE
  // valeur par maillon, root -> tip : l'abscisse `r` de la CHAIR que ce maillon pilote,
  // moyenne ponderee par le poids de peau, mesuree sur le mesh LIVRE
  // (.autoport/c138_graded_tensor.py). Donnee derivee, jamais un reglage. Vide = pas de
  // gradient : GOAL applique alors le tenseur UNIFORME d'avant, identite par algebre.
  std::vector<float> link_spr;
  // (C132) SPEC 31 — le point « r = 0 at chest attachment » que la section NOMME, en espace os
  // local de CE maillon, en unites, pose de bind. Le tenseur de deformation est aujourd'hui
  // applique autour de l'ORIGINE DU JOINT, qui tombe a r = -0.04 a -0.07 sur l'axe de SPEC 31 : ce
  // point est le point fixe que la section prescrit. Mesure sur le maillage LIVRE, jamais
  // ajuste a la main. Vide = pas d'enregistrement `anp=` : GOAL n'applique alors AUCUN offset,
  // ce qui est exactement le comportement d'avant ce cycle.
  std::vector<std::array<float, 3>> link_anp;
  // `pk <Key> <value>` : the CHARACTER PRESET, copied VERBATIM from SPEC-breast-softbody.md
  // section 38 by .autoport/preset_apply.py — key name and number, never re-typed by hand.
  // The owner, 2026-08-22: « les memes proprietes des presets ont des valeurs differentes, on
  // pourrait donc imaginer que ces knobs influencent proprement le tout ». A preset that gives
  // the SAME keys with DIFFERENT numbers for two characters writes INPUTS, not observations —
  // so every key here is a channel the engine READS, and a key the engine does not read is
  // reported as CANAL ABSENT rather than silently ignored.
  // Parallel vectors, insertion order preserved; lookup is BY NAME (see kPhysPresetKeys).
  std::vector<std::string> pkey;
  std::vector<float> pval;
  // (C51) ax= : the APEX region representative, per LINK — `w` is the share of the distal
  // region's skin mass this link carries, `p` the mass-weighted centroid of that region in THIS
  // link's bone-local bind space (game units). Comes from recharged_assets/physics_mesh.txt
  // (.autoport/physics_c14_meshsamples.py), derived data, never hand-tuned. Same algebra as
  // link_comw, applied to a SUB-POPULATION instead of the whole cloud:
  //   d_apex = SUM_l w_l * (M_l^sim - M_l^auth) * p_l
  // exact under linear blend skinning. The ANCHORED share (chest carries 41-43% of this region)
  // is not simulated, does not move, and is accounted for by the weights summing to LESS than 1
  // — which is also why an apex ceiling can be out of reach with no tuning able to change it.
  // Empty = no ax= record; GOAL then publishes no apex at all rather than an apex of zero.
  std::vector<float> link_apexw;                 // outer index = link
  std::vector<std::array<float, 3>> link_apexp;  // outer index = link
  // (C128) SPEC 11 — L'ETAGE RIGIDE. Le vecteur racine->apex de la chair est, sous skinning
  // lineaire, EXACTEMENT une somme par OS :  d = SUM_b (ds_b . R_b + dm_b t_b), ou ds_b et dm_b
  // sont des constantes du MESH LIVRE (differences de centroides ponderes entre la population
  // DISTALE et la population PROXIMALE, chacune renormalisee par son propre total). Consequence
  // exploitee : SUM_b dm_b = 0 exactement, donc t_b peut etre pris RELATIF A L'ANCRE — ce qui
  // annule la contribution de translation de l'ancre et divise les magnitudes par ~100, rendant
  // le transport en milli-unites sans effet. Ordre : [0]=ancre, [1]=maillon 0, [2]=maillon 1 ;
  // chaque entree = {ds.x, ds.y, ds.z, dm*1000}. L'entree de l'ancre porte dm = 0 par
  // construction et n'est pas lue. Vide = pas d'enregistrement rg= : GOAL ne corrige alors rien,
  // et le comportement est EXACTEMENT celui d'avant le cycle 128.
  std::array<std::array<float, 4>, 3> rigid_stage{};
  bool rigid_stage_set = false;
  std::vector<std::string> xchains;  // xchain= : chains this chain must be collided against
  // (C14) per-link EXTREMAL skinned-vertex offsets, bone-local bind space, game units, <=5 per
  // link. This is the geometry the mesh-surface penetration audit samples: the owner's eyes live
  // on the mesh, and every bone-level counter before this one produced a zero he could refute by
  // looking. Comes from recharged_assets/physics_mesh.txt (derived data, physics_c14_meshsamples.py),
  // never hand-tuned. Outer index = link; empty = no sample reaches beyond the link radius.
  std::vector<std::vector<std::array<float, 3>>> mesh_samples;
};

// A body collision volume: a SPHERE on `joint`, or — when `joint2` is set — a CAPSULE (swept
// sphere) spanning `joint` -> `joint2`, so it follows two animated bones. `chains` restricts which
// chains of the model the volume pushes out; an EMPTY list means it applies to every chain (legacy
// behavior). `tier` selects how aggressively it is kept at lower precision levels. Several
// colliders may sit on the same joint with different filters/radii.
struct PhysCollider {
  std::string joint;
  float radius = 0.f;
  // CYCLE 3 (owner C): a constant-radius capsule cannot model a FLARED trouser leg or a shoulder,
  // and Jak's jacket hem clipped straight through because of it. `radius2` gives the far end its own
  // radius, so the volume is a CONE; <= 0 means "same as radius" (a plain cylinder, as before).
  float radius2 = 0.f;
  std::vector<std::string> chains;  // empty = applies to ALL chains
  std::string joint2;               // empty = sphere; non-empty = CAPSULE from `joint` to `joint2`
  int tier = 1;  // 1 = core (on at every precision level with collisions), 2 = extended
  int side = 0;             // 0 = none, 1 = L, 2 = R (cross-side penetration accounting)
  std::string chainref;     // non-empty: centre this sphere on the SIMULATED TIP of that chain
  // CYCLE 7 (owner, 6e passe 2026-08-11): « lBoob et rBoob sont des spheres nues posees sur le
  // joint-racine, alors que tout le reste du corps est en capsules derivees. Une sphere au joint
  // ne peut pas epouser un sein. » Le centre d'une sphere n'a aucune raison d'etre le joint : la
  // geometrie qu'elle represente a un CENTRE, mesure sur le mesh (centroide des sommets skinnes du
  // joint, exprime dans l'espace bind du joint, en unites de jeu). Le moteur le transforme par la
  // matrice de l'os, donc le volume suit l'animation comme le joint lui-meme.
  // Absent des donnees = 0,0,0 = le comportement d'avant, au bit pres.
  float ox = 0.f, oy = 0.f, oz = 0.f;
};

struct PhysModel {
  std::vector<PhysChain> chains;
  std::vector<PhysCollider> colliders;
  // bone-local body SURFACE samples with outward normals — the real skinned surface the
  // chains are tested against (SPEC 18). Capsules stay as broad phase only.
  // Comes from the `bs` records of recharged_assets/physics_mesh.txt, the same derived file the
  // per-link `ms` samples above live in, with the same hot-reload and external-override
  // lifecycle. The two vectors are strictly parallel (one entry each per set); a pack with no
  // `bs` lines simply leaves them empty, which the FFI reports as zero sets.
  std::vector<std::string> bsurf_joint;                  // per set: the bone it sits on
  std::vector<std::vector<std::array<float, 6>>> bsurf;  // per set: {x,y,z,nx,ny,nz}
};

static std::map<std::string, PhysModel> s_phys_models;
static float s_phys_levels[kPhysMaxLevels][kPhysNumLevelParams] = {};
static int s_phys_level_count = 0;
static bool s_phys_loaded_once = false;
// Bumped on every (re)parse. GOAL slots compare it and re-bind their chains when it changes, so a
// hot-pushed physics_chains.txt takes effect on companions AND stock riders without a respawn.
static int s_phys_generation = 0;

static std::vector<std::string> phys_tokens(const std::string& line) {
  std::vector<std::string> out;
  size_t i = 0;
  while (i < line.size()) {
    while (i < line.size() && std::isspace((unsigned char)line[i])) {
      i++;
    }
    size_t start = i;
    while (i < line.size() && !std::isspace((unsigned char)line[i])) {
      i++;
    }
    if (i > start) {
      out.push_back(line.substr(start, i - start));
    }
  }
  return out;
}

// "key=value" -> true + the two halves. Anything without '=' is not a kv token.
static bool phys_kv(const std::string& tok, std::string& key, std::string& val) {
  auto eq = tok.find('=');
  if (eq == std::string::npos) {
    return false;
  }
  key = tok.substr(0, eq);
  val = tok.substr(eq + 1);
  return true;
}

static float phys_to_float(const std::string& s) {
  try {
    return std::stof(s);
  } catch (...) {
    return 0.f;
  }
}

// Shared key=value handling for the `collider` (sphere) and `capsule` lines — the two differ only
// in how many leading joint tokens they consume. Returns false for an unrecognized key so the
// caller can emit the usual one-shot "unknown key" warning.
// CYCLE 5 adds two keys:
//   side=L|R   which side of the body this volume belongs to, so a chain declaring side= can be
//              accounted for when it penetrates the OPPOSITE side (query field 5).
//   at=<chain> centre this sphere on the SIMULATED TIP of that chain instead of on a bone: the way
//              two chains (Keira's chests) are made to collide with each other (query field 6).
static bool phys_collider_kv(PhysCollider& col, const std::string& k, const std::string& v) {
  if (k == "radius") {
    col.radius = phys_to_float(v);
  } else if (k == "radius2") {
    col.radius2 = phys_to_float(v);
  } else if (k == "chains") {
    // comma-separated chain names, no spaces.
    size_t p = 0;
    while (p <= v.size()) {
      size_t comma = v.find(',', p);
      std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
      if (!one.empty()) {
        col.chains.push_back(one);
      }
      if (comma == std::string::npos) {
        break;
      }
      p = comma + 1;
    }
  } else if (k == "tier") {
    col.tier = (int)phys_to_float(v);
    if (col.tier < 1) {
      col.tier = 1;
    }
  } else if (k == "side") {
    // A LETTER, case-insensitive, like the chain's own side=. Anything else stays 0 (none) — the
    // chain-side warning already tells the owner the letter set, no need for a second one here.
    if (v == "L" || v == "l") {
      col.side = 1;
    } else if (v == "R" || v == "r") {
      col.side = 2;
    }
  } else if (k == "at") {
    col.chainref = v;
  } else if (k == "offset") {
    // offset=x,y,z — centre de la geometrie du joint dans SON espace bind, en unites de jeu.
    // Trois nombres exactement ; toute autre forme laisse l'offset a zero et sera signalee par le
    // "unknown key" du dessus si la cle elle-meme est fausse.
    float xyz[3] = {0.f, 0.f, 0.f};
    size_t p = 0;
    int n = 0;
    while (p <= v.size() && n < 3) {
      size_t comma = v.find(',', p);
      std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
      if (!one.empty()) {
        xyz[n++] = phys_to_float(one);
      }
      if (comma == std::string::npos) {
        break;
      }
      p = comma + 1;
    }
    if (n == 3) {
      col.ox = xyz[0];
      col.oy = xyz[1];
      col.oz = xyz[2];
    } else {
      lg::warn("[hd-phys] collider {} offset= wants three numbers 'x,y,z' (got '{}', ignored)",
               col.joint, v);
    }
  } else {
    return false;
  }
  return true;
}

// Parse recharged_assets/physics_chains.txt. Missing file is NOT an error (0 models = feature inert).
// Returns the number of [model ...] sections parsed.
static int pc_physics_parse_file() {
  // Bumped unconditionally, including on the failure paths below: any (re)parse invalidates the
  // chain bindings the GOAL side cached from the previous contents.
  s_phys_generation++;
  // Whoever got here HAS loaded the store — including pc_set_physics's menu-driven re-read, which
  // runs before any ensure_loaded() the first time the owner touches the toggle. Setting the flag
  // here (rather than only in the two ensure/reload wrappers) keeps that path from being followed
  // by a second, redundant parse and a second generation bump.
  s_phys_loaded_once = true;
  s_phys_models.clear();
  s_phys_level_count = 0;
  for (int i = 0; i < kPhysMaxLevels; i++) {
    for (int j = 0; j < kPhysNumLevelParams; j++) {
      s_phys_levels[i][j] = 0.f;
    }
  }

  // OWNER TUNING PATH (2026-08-06): physics_chains.txt is data the owner retunes by hand. The
  // package copy inside the APK would otherwise win over the external pack (see
  // get_recharged_assets_dir), turning a stiffness tweak into a 581 MB re-download. An EXTERNAL
  // copy therefore OVERRIDES the packaged one, and the chosen source is logged so a device gate
  // can prove which file is live.
  const char* phys_src = "package";
  auto path = file_util::get_recharged_assets_dir() / "physics_chains.txt";
  auto ext_dir = file_util::get_external_recharged_assets_dir();
  if (ext_dir) {
    auto ext_path = *ext_dir / "physics_chains.txt";
    if (file_util::file_exists(ext_path.string())) {
      path = ext_path;
      phys_src = "external-override";
    }
  }
  if (!file_util::file_exists(path.string())) {
    lg::info("[hd-phys] PARAMSRC=none path={} (physics inert)", path.string());
    return 0;
  }
  lg::info("[hd-phys] PARAMSRC={} path={}", phys_src, path.string());

  std::string text;
  try {
    text = file_util::read_text_file(path);
  } catch (...) {
    lg::warn("[hd-phys] could not read {}", path.string());
    return 0;
  }

  PhysModel* cur_model = nullptr;
  PhysChain* cur_chain = nullptr;
  bool in_levels = false;
  // physics_chains.txt is the shared HD tuning file: sections we do not own (Grecharged-hd-eye-scale
  // parses [eyescale] in EyeRenderer.cpp) are skipped whole instead of warning line by line.
  bool skip_section = false;
  bool warned_unknown = false;
  int n_chains = 0;
  int n_sections = 0;
  // One entry per parsed [model ...] section: the full list of names it declared. Resolved into
  // s_phys_models after the loop, once each section's contents are complete.
  std::vector<std::vector<std::string>> alias_groups;

  size_t pos = 0;
  while (pos <= text.size()) {
    size_t eol = text.find('\n', pos);
    std::string raw = text.substr(pos, eol == std::string::npos ? std::string::npos : eol - pos);
    pos = (eol == std::string::npos) ? text.size() + 1 : eol + 1;

    // strip CR + trailing comment
    if (!raw.empty() && raw.back() == '\r') {
      raw.pop_back();
    }
    auto hash = raw.find('#');
    if (hash != std::string::npos) {
      raw = raw.substr(0, hash);
    }
    auto toks = phys_tokens(raw);
    if (toks.empty()) {
      continue;
    }

    // A foreign section header ends whatever we were parsing and mutes us until the next one we
    // own; a header we DO own always clears the mute, so section order in the file is free.
    if (!toks[0].empty() && toks[0][0] == '[' && toks[0] != "[levels]" && toks[0] != "[model") {
      in_levels = false;
      cur_model = nullptr;
      cur_chain = nullptr;
      skip_section = true;
      lg::info("[hd-phys] section {} is not ours (skipped)", toks[0]);
      continue;
    }
    if (!toks[0].empty() && toks[0][0] == '[') {
      skip_section = false;
    }
    if (skip_section) {
      continue;
    }

    if (toks[0] == "[levels]") {
      in_levels = true;
      cur_model = nullptr;
      cur_chain = nullptr;
      continue;
    }
    // A section header may declare SEVERAL names: `[model a b c]`. jak1 ships the same rig under
    // many art-group names (assistant, assistant-village2, assistant-firecanyon, ...), and
    // duplicating the whole block once per name is unmaintainable, so every listed name aliases
    // ONE PhysModel. The contents only exist once the section has been fully parsed, so the copy
    // to the extra names is deferred to after the parse loop (see alias_groups).
    if (toks[0] == "[model" && toks.size() >= 2) {
      std::vector<std::string> names;
      for (size_t t = 1; t < toks.size(); t++) {
        std::string name = toks[t];
        if (!name.empty() && name.back() == ']') {
          name.pop_back();
        }
        if (!name.empty()) {
          names.push_back(name);
        }
      }
      in_levels = false;
      cur_chain = nullptr;
      if (names.empty()) {
        lg::warn("[hd-phys] [model] section with no name (skipped)");
        cur_model = nullptr;
        continue;
      }
      cur_model = &s_phys_models[names[0]];
      n_sections++;
      if (names.size() > 1) {
        lg::info("[hd-phys] model {} aliased to {} more name(s)", names[0], names.size() - 1);
      }
      alias_groups.push_back(std::move(names));
      continue;
    }

    if (in_levels && toks[0] == "level" && toks.size() >= 2) {
      int idx = 0;
      try {
        idx = std::stoi(toks[1]);
      } catch (...) {
        idx = -1;
      }
      if (idx < 0 || idx >= kPhysMaxLevels) {
        lg::warn("[hd-phys] level index out of range: {}", raw);
        continue;
      }
      for (size_t t = 2; t < toks.size(); t++) {
        std::string k, v;
        if (!phys_kv(toks[t], k, v)) {
          continue;
        }
        if (k == "substeps") {
          s_phys_levels[idx][0] = phys_to_float(v);
        } else if (k == "iters") {
          s_phys_levels[idx][1] = phys_to_float(v);
        } else if (k == "collide") {
          s_phys_levels[idx][2] = phys_to_float(v);
        } else if (k == "classmask") {
          s_phys_levels[idx][3] = phys_to_float(v);
        } else if (k == "fixedhz") {
          s_phys_levels[idx][4] = phys_to_float(v);
        } else if (!warned_unknown) {
          warned_unknown = true;
          lg::warn("[hd-phys] unknown key '{}' in physics_chains.txt (skipped)", k);
        }
      }
      if (idx + 1 > s_phys_level_count) {
        s_phys_level_count = idx + 1;
      }
      continue;
    }

    if (toks[0] == "chain" && toks.size() >= 2) {
      if (!cur_model) {
        lg::warn("[hd-phys] 'chain' outside a [model ...] section (skipped): {}", raw);
        continue;
      }
      PhysChain ch;
      ch.name = toks[1];
      for (size_t t = 2; t < toks.size(); t++) {
        std::string k, v;
        if (!phys_kv(toks[t], k, v)) {
          continue;
        }
        if (k == "class") {
          if (v == "primary") {
            ch.class_bits = kPhysClassPrimary;
          } else if (v == "secondary") {
            ch.class_bits = kPhysClassSecondary;
          } else if (v == "accessory") {
            ch.class_bits = kPhysClassAccessory;
          } else {
            lg::warn("[hd-phys] unknown chain class '{}' (0 bits)", v);
          }
        } else if (k == "stiffness") {
          ch.params[0] = phys_to_float(v);
        } else if (k == "damping") {
          ch.params[1] = phys_to_float(v);
        } else if (k == "gravity") {
          ch.params[2] = phys_to_float(v);
        } else if (k == "maxangle") {
          ch.params[3] = phys_to_float(v);
        } else if (k == "inertia") {
          ch.params[4] = phys_to_float(v);
        } else if (k == "stretch") {
          ch.params[5] = phys_to_float(v);
        } else if (k == "radius") {
          ch.params[6] = phys_to_float(v);
        } else if (k == "rootlock") {
          ch.params[7] = phys_to_float(v);
        } else if (k == "gradient") {
          ch.params[8] = phys_to_float(v);
        } else if (k == "anim") {
          if (v == "keep") {
            ch.params[9] = 0.f;
          } else if (v == "replace") {
            ch.params[9] = 1.f;
          } else if (v == "excite") {
            ch.params[9] = 2.f;
          } else {
            lg::warn("[hd-phys] unknown chain anim mode '{}' (keeping replace)", v);
          }
        } else if (k == "excite") {
          ch.params[10] = phys_to_float(v);
        } else if (k == "friction") {
          ch.params[11] = phys_to_float(v);
        } else if (k == "authored") {
          ch.params[12] = phys_to_float(v);
        } else if (k == "authrise") {
          ch.params[13] = phys_to_float(v);
        } else if (k == "authfall") {
          ch.params[14] = phys_to_float(v);
        } else if (k == "authstiff") {
          ch.params[15] = phys_to_float(v);
        } else if (k == "rootfree") {
          ch.params[16] = phys_to_float(v);
        } else if (k == "nodesc") {
          ch.params[17] = phys_to_float(v);
        } else if (k == "colskip") {
          ch.params[18] = phys_to_float(v);
        } else if (k == "mass") {
          ch.params[19] = phys_to_float(v);
        } else if (k == "hang") {
          ch.params[20] = phys_to_float(v);
        } else if (k == "swing") {
          ch.params[21] = phys_to_float(v);
        } else if (k == "family") {
          // A LETTER, not a number, and case-insensitive: the data reads as a classification.
          if (v == "A" || v == "a") {
            ch.params[22] = 1.f;  // body: hair / chest / ears — returns to the model pose
          } else if (v == "B" || v == "b") {
            ch.params[22] = 2.f;  // hangs: straps / accessories / cloth — gravity rules its rest
          } else {
            // Its OWN warning, deliberately NOT gated by warned_unknown: a mistyped family is a
            // chain silently left UNCLASSIFIED, which is exactly what cycle 5 exists to catch.
            lg::warn("[hd-phys] chain '{}': family must be A or B, got '{}'", ch.name, v);
          }
        } else if (k == "side") {
          if (v == "L" || v == "l") {
            ch.params[23] = 1.f;
          } else if (v == "R" || v == "r") {
            ch.params[23] = 2.f;
          } else {
            lg::warn("[hd-phys] chain '{}': side must be L or R, got '{}'", ch.name, v);
          }
        } else if (k == "extent") {
          ch.params[24] = phys_to_float(v);
        } else if (k == "radii") {
          // Comma-separated, ONE PER LINK, root -> tip. A single whole-chain radius= is the same
          // number at a shoulder and at a fingertip, which is precisely how a mesh vertex ends up
          // outside its own collision volume; these come measured off the skinned geometry.
          // Cleared first so a repeated radii= on one line replaces rather than appends.
          ch.link_radius.clear();
          size_t p = 0;
          while (p <= v.size()) {
            size_t comma = v.find(',', p);
            std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
            if (!one.empty()) {
              ch.link_radius.push_back(phys_to_float(one));
            }
            if (comma == std::string::npos) {
              break;
            }
            p = comma + 1;
          }
        } else if (k == "comw") {
          // Same shape as radii= : comma-separated, ONE PER LINK, root -> tip. Measured on the
          // SHIPPED mesh (.autoport/probe_c48_com_identity.py), never hand-tuned.
          ch.link_comw.clear();
          size_t p = 0;
          while (p <= v.size()) {
            size_t comma = v.find(',', p);
            std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
            if (!one.empty()) {
              ch.link_comw.push_back(phys_to_float(one));
            }
            if (comma == std::string::npos) {
              break;
            }
            p = comma + 1;
          }
        } else if (k == "spr") {
          // Meme forme que comw= : liste separee par des virgules, UNE PAR MAILLON, root -> tip.
          ch.link_spr.clear();
          size_t p = 0;
          while (p <= v.size()) {
            size_t comma = v.find(',', p);
            std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
            if (!one.empty()) {
              ch.link_spr.push_back(phys_to_float(one));
            }
            if (comma == std::string::npos) {
              break;
            }
            p = comma + 1;
          }
        } else if (k == "anp") {
          // (C132) SPEC 31 — meme forme que comw= : liste separee par des virgules, root -> tip,
          // mais TROIS flottants par maillon (x,y,z) en espace os LOCAL de ce maillon, en unites,
          // pose de bind. C'est le point que la section appelle « r = 0 at chest attachment »,
          // mesure sur le maillage LIVRE — une donnee derivee, jamais un reglage. Un reliquat
          // incomplet (taille non multiple de 3) est IGNORE plutot que complete par des zeros :
          // un maillon a moitie declare n'est pas un maillon ancre a l'origine, et le completer
          // fabriquerait une donnee que personne n'a mesuree.
          ch.link_anp.clear();
          std::vector<float> anp_flat;
          size_t p = 0;
          while (p <= v.size()) {
            size_t comma = v.find(',', p);
            std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
            if (!one.empty()) {
              anp_flat.push_back(phys_to_float(one));
            }
            if (comma == std::string::npos) {
              break;
            }
            p = comma + 1;
          }
          for (size_t i = 0; i + 2 < anp_flat.size(); i += 3) {
            ch.link_anp.push_back({anp_flat[i], anp_flat[i + 1], anp_flat[i + 2]});
          }
        } else if (k == "xchain") {
          // Comma-separated chain NAMES of this same model. Two chains have never been able to see
          // each other — which is why Jak's back buckle swings through his own strap — and naming
          // the partner here is what makes the pair collide.
          ch.xchains.clear();
          size_t p = 0;
          while (p <= v.size()) {
            size_t comma = v.find(',', p);
            std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
            if (!one.empty()) {
              ch.xchains.push_back(one);
            }
            if (comma == std::string::npos) {
              break;
            }
            p = comma + 1;
          }
        } else if (k == "inject") {
          ch.params[26] = phys_to_float(v);
        } else if (k == "couple") {
          ch.params[27] = phys_to_float(v);
        } else if (k == "shell") {
          // Inner radius of the sleeve this link wraps around a limb, in units. Written by the
          // generator only for links measured to be closed shells around a FOREIGN volume; a chain
          // that is not a sleeve carries no `shell=` at all, not `shell=0`.
          ch.params[28] = phys_to_float(v);
        } else if (k == "anch") {
          // (C132) gain applique a `anp=` : 0 = tenseur ancre au JOINT (comportement d'avant ce
          // cycle, identite par algebre) ; 1 = ancre au point r=0 que sa SPEC 31 nomme. C'est le
          // BOUTON declare, distinct de la donnee mesuree `anp=` — pour qu'un balayage ne
          // reecrive jamais une valeur mesuree sur le maillage.
          // NOTE DE COLLISION DE NOM : le bloc de documentation des ids ci-dessus nomme encore
          // l'id 25 `compress` (cycle 5). Ce `compress` n'a JAMAIS ete parse ni lu par le moteur
          // — l'id 25 etait un slot documente et vide. Il porte `anch` a partir de ce cycle.
          ch.params[25] = phys_to_float(v);
        } else if (k == "medw") {
          // (C137) SPEC 10 — distance du joint racine au MUR MEDIAN (le plan sagittal que le bord
          // medial de la chair touche au repos), en unites, mesuree sur le maillage LIVRE.
          // 0 = mur ABSENT, terme exactement nul, identite par algebre. Voir l'id 31 ci-dessus.
          ch.params[31] = phys_to_float(v);
        } else if (k == "rbrot") {
          // (C140) SPEC 37 — angle IN DEGREES above which one frame of ANCHOR rotation is declared
          // an implausible transform change and the state is rebased instead of kicked. Stored as
          // `1000 * (1 - cos(theta))` (a chord measure, monotone on [0, 180]) so the engine
          // compares it against a quantity built from dot products alone. The factor 1000 is NOT
          // cosmetic: the store crosses into GOAL in MILLI-units, and a bare `1 - cos` would round
          // 1 degree (1.52e-4) to ZERO milli — i.e. a threshold set for a positive control would
          // silently read as DISARMED. With the factor, one milli is 1e-6 of chord, or 1.7e-4
          // degree at 20 degrees.
          // THE SIGN CARRIES THE ARMING, and it is what makes ONE run both the measurement and its
          // own negative control. A NEGATIVE angle means MEASURE ONLY: the engine counts the frames
          // that would cross |theta| and does NOT rebase, so the run stays bit-identical to the
          // build before this cycle while still answering "how many frames per window would this
          // threshold touch?". A POSITIVE angle measures AND rebases. 0 leaves the whole term
          // unreachable, and that is the default of every chain that does not declare the key.
          // Without this, a disarmed run cannot tell a SCALPEL (a frame or two per window) from a
          // GAG (every frame, the chain riding the anchor rigidly) — and only the second is a
          // reason not to ship.
          float deg = phys_to_float(v);
          float mag = (float)(1000.0 * (1.0 - std::cos(std::fabs(deg) * 3.14159265358979 / 180.0)));
          ch.params[32] = (deg == 0.f) ? 0.f : ((deg > 0.f) ? mag : -mag);
        } else if (k == "lyield") {
          // (C135) gain de la correction de DOUBLE COMPTE de sa SPEC 11 — voir l'id 30 ci-dessus.
          // 0 = identite PAR ALGEBRE (diviseur exactement 1), donc defaut sur toute chaine muette.
          ch.params[30] = phys_to_float(v);
        } else if (k == "b0") {
          // SPEC 6's characteristic root-to-apex length of the FLESH, in units, measured on the
          // mesh — the yardstick SPEC 22 expresses its apex ceiling in. See the default above.
          ch.params[29] = phys_to_float(v);
        } else if (!warned_unknown) {
          warned_unknown = true;
          lg::warn("[hd-phys] unknown key '{}' in physics_chains.txt (skipped)", k);
        }
      }
      cur_model->chains.push_back(ch);
      cur_chain = &cur_model->chains.back();
      n_chains++;
      continue;
    }

    // `pk <Key> <value>` — one preset line of SPEC-breast-softbody section 38, verbatim.
    // Kept as a NAME->value pair rather than a positional list: a positional list makes the key
    // order a convention living in two files at once, and it cannot express "this key has no
    // reader" — which is exactly the state the audit has to publish.
    if (toks[0] == "pk" && toks.size() >= 3) {
      if (!cur_chain) {
        lg::warn("[hd-phys] 'pk' with no current chain (skipped): {}", raw);
        continue;
      }
      cur_chain->pkey.push_back(toks[1]);
      cur_chain->pval.push_back(phys_to_float(toks[2]));
      continue;
    }

    if (toks[0] == "j" && toks.size() >= 2) {
      if (!cur_chain) {
        lg::warn("[hd-phys] 'j' with no current chain (skipped): {}", raw);
        continue;
      }
      cur_chain->joints.push_back(toks[1]);
      continue;
    }

    if (toks[0] == "collider" && toks.size() >= 2) {
      if (!cur_model) {
        lg::warn("[hd-phys] 'collider' outside a [model ...] section (skipped): {}", raw);
        continue;
      }
      PhysCollider col;
      col.joint = toks[1];
      for (size_t t = 2; t < toks.size(); t++) {
        std::string k, v;
        if (!phys_kv(toks[t], k, v)) {
          continue;
        }
        if (!phys_collider_kv(col, k, v) && !warned_unknown) {
          warned_unknown = true;
          lg::warn("[hd-phys] unknown key '{}' in physics_chains.txt (skipped)", k);
        }
      }
      cur_model->colliders.push_back(col);
      continue;
    }

    // `capsule <jointA> <jointB> radius=R [chains=a,b] [tier=N]` — a swept-sphere body volume that
    // follows two animated bones. Same filter/tier semantics as `collider`.
    if (toks[0] == "capsule" && toks.size() >= 3) {
      if (!cur_model) {
        lg::warn("[hd-phys] 'capsule' outside a [model ...] section (skipped): {}", raw);
        continue;
      }
      PhysCollider col;
      col.joint = toks[1];
      col.joint2 = toks[2];
      for (size_t t = 3; t < toks.size(); t++) {
        std::string k, v;
        if (!phys_kv(toks[t], k, v)) {
          continue;
        }
        if (!phys_collider_kv(col, k, v) && !warned_unknown) {
          warned_unknown = true;
          lg::warn("[hd-phys] unknown key '{}' in physics_chains.txt (skipped)", k);
        }
      }
      cur_model->colliders.push_back(col);
      continue;
    }

    if (!warned_unknown) {
      warned_unknown = true;
      lg::warn("[hd-phys] unknown line in physics_chains.txt (skipped): {}", raw);
    }
  }

  // Publish the variant aliases: every extra name of a section gets a copy of the first name's
  // fully-parsed PhysModel. std::map references are stable, but the source is copied out first so
  // the inserts below cannot be read as self-assignment.
  for (const auto& group : alias_groups) {
    if (group.size() < 2) {
      continue;
    }
    const PhysModel src = s_phys_models[group[0]];
    for (size_t i = 1; i < group.size(); i++) {
      s_phys_models[group[i]] = src;
    }
  }

  // ---- (C14) physics_mesh.txt: per-link extremal skinned-vertex offsets ------------------------
  // Parsed AFTER the alias publication so a `model` line can name any alias and still land, and
  // applied to EVERY name it lists (aliases are value copies by then, not references). Derived
  // data, same external-override precedence as the tuning file: a re-derivation the owner pulls
  // down is a few hundred KB, never an APK.
  {
    const char* mesh_src = "package";
    auto mesh_path = file_util::get_recharged_assets_dir() / "physics_mesh.txt";
    if (ext_dir) {
      auto ext_mesh = *ext_dir / "physics_mesh.txt";
      if (file_util::file_exists(ext_mesh.string())) {
        mesh_path = ext_mesh;
        mesh_src = "external-override";
      }
    }
    if (!file_util::file_exists(mesh_path.string())) {
      // Not an error: without samples the mesh audit reports meshtested=0, which the device gate
      // reads as "not measured" — never as a clean zero. That is the honest failure mode.
      lg::info("[hd-phys] MESHSRC=none path={} (mesh audit unarmed)", mesh_path.string());
    } else {
      std::string mtext;
      try {
        mtext = file_util::read_text_file(mesh_path);
      } catch (...) {
        mtext.clear();
        lg::warn("[hd-phys] could not read {}", mesh_path.string());
      }
      std::vector<std::string> cur_names;
      int n_ms = 0, n_ms_dropped = 0;
      int n_ax = 0, n_ax_dropped = 0;
      int n_rg = 0;
      int n_bs = 0, n_bs_dropped = 0;
      size_t mpos = 0;
      while (mpos <= mtext.size()) {
        size_t eol = mtext.find('\n', mpos);
        std::string raw =
            mtext.substr(mpos, eol == std::string::npos ? std::string::npos : eol - mpos);
        mpos = (eol == std::string::npos) ? mtext.size() + 1 : eol + 1;
        if (!raw.empty() && raw.back() == '\r') {
          raw.pop_back();
        }
        auto hash = raw.find('#');
        if (hash != std::string::npos) {
          raw = raw.substr(0, hash);
        }
        auto toks = phys_tokens(raw);
        if (toks.empty()) {
          continue;
        }
        if (toks[0] == "model") {
          cur_names.assign(toks.begin() + 1, toks.end());
          continue;
        }
        // ms <chainName> <linkIdx> <n> x y z [* n]
        if (toks[0] == "ms" && toks.size() >= 4) {
          const std::string& cname = toks[1];
          int link = atoi(toks[2].c_str());
          int n = atoi(toks[3].c_str());
          if (n < 0 || n > 5 || (int)toks.size() < 4 + 3 * n) {
            n_ms_dropped++;
            continue;
          }
          for (const auto& mn : cur_names) {
            auto mit = s_phys_models.find(mn);
            if (mit == s_phys_models.end()) {
              continue;
            }
            for (auto& ch : mit->second.chains) {
              if (ch.name != cname) {
                continue;
              }
              if (link < 0 || link >= (int)ch.joints.size()) {
                n_ms_dropped++;
                break;
              }
              if (ch.mesh_samples.size() < ch.joints.size()) {
                ch.mesh_samples.resize(ch.joints.size());
              }
              auto& dst = ch.mesh_samples[link];
              dst.clear();
              for (int s = 0; s < n; s++) {
                dst.push_back({(float)atof(toks[4 + 3 * s].c_str()),
                               (float)atof(toks[5 + 3 * s].c_str()),
                               (float)atof(toks[6 + 3 * s].c_str())});
              }
              n_ms++;
              break;
            }
          }
          continue;
        }
        // (C51) ax <chainName> <linkIdx> <w> <x> <y> <z> — the APEX region representative for
        // this link. One record per link; a link with no record keeps w = 0 and contributes
        // nothing, which is the same "missing weight never reads as zero motion" rule comw= uses.
        if (toks[0] == "ax" && toks.size() >= 7) {
          const std::string& cname = toks[1];
          int link = atoi(toks[2].c_str());
          for (const auto& mn : cur_names) {
            auto mit = s_phys_models.find(mn);
            if (mit == s_phys_models.end()) {
              continue;
            }
            for (auto& ch : mit->second.chains) {
              if (ch.name != cname) {
                continue;
              }
              if (link < 0 || link >= (int)ch.joints.size()) {
                n_ax_dropped++;
                break;
              }
              if (ch.link_apexw.size() < ch.joints.size()) {
                ch.link_apexw.resize(ch.joints.size(), 0.f);
                ch.link_apexp.resize(ch.joints.size(), {0.f, 0.f, 0.f});
              }
              ch.link_apexw[link] = (float)atof(toks[3].c_str());
              ch.link_apexp[link] = {(float)atof(toks[4].c_str()),
                                     (float)atof(toks[5].c_str()),
                                     (float)atof(toks[6].c_str())};
              n_ax++;
              break;
            }
          }
          continue;
        }
        // (C128) rg <chainName> <sax> <say> <saz> <s0x> <s0y> <s0z> <m0k> <s1x> <s1y> <s1z> <m1k>
        // — les 12 constantes de l'ETAGE RIGIDE de SPEC 11, une ligne par chaine. Meme section
        // `model` et meme moule de cle que ms/ax ci-dessus. Voir .autoport/c128_bake_rigid.py,
        // qui les cuit ET valide l'estimateur contre le nuage RIGID mesure AVANT de les ecrire.
        if (toks[0] == "rg" && toks.size() >= 13) {
          const std::string& cname = toks[1];
          for (const auto& mn : cur_names) {
            auto mit = s_phys_models.find(mn);
            if (mit == s_phys_models.end()) {
              continue;
            }
            for (auto& ch : mit->second.chains) {
              if (ch.name != cname) {
                continue;
              }
              for (int b = 0; b < 3; b++) {
                for (int q = 0; q < 4; q++) {
                  // l'ancre ne porte que 3 valeurs (son dm est nul par construction) : les
                  // maillons commencent donc au token 5, pas au token 6.
                  int t = (b == 0) ? (2 + q) : (5 + (b - 1) * 4 + q);
                  ch.rigid_stage[b][q] = (b == 0 && q == 3) ? 0.f : (float)atof(toks[t].c_str());
                }
              }
              ch.rigid_stage_set = true;
              n_rg++;
              break;
            }
          }
          continue;
        }
        // (SPEC 18) bs <boneName> <n> x y z nx ny nz [* n] — per BODY bone, the skinned SURFACE
        // the chains are collided against, bone-local bind space, game units. Sits inside the same
        // `model` sections as the ms lines above, after them, and lands on every name that section
        // declares (aliases are value copies by now, exactly as for ms).
        if (toks[0] == "bs" && toks.size() >= 3) {
          const std::string& bname = toks[1];
          int n = atoi(toks[2].c_str());
          // Same malformed-line tolerance as the ms parser: a negative count or a line too short
          // for the count it declares is DROPPED and counted, never warned per line. Widened to
          // 64-bit only so a garbage count in a file the owner can edit on device cannot overflow
          // the comparison itself; there is no invented upper cap on n — the token count is the
          // cap, so the allocation below is bounded by the length of the line.
          if (n < 0 || (s64)toks.size() < (s64)3 + 6ll * (s64)n) {
            n_bs_dropped++;
            continue;
          }
          for (const auto& mn : cur_names) {
            auto mit = s_phys_models.find(mn);
            if (mit == s_phys_models.end()) {
              continue;
            }
            auto& pm = mit->second;
            std::vector<std::array<float, 6>> set;
            set.reserve((size_t)n);
            for (int s = 0; s < n; s++) {
              set.push_back({(float)atof(toks[3 + 6 * s].c_str()),
                             (float)atof(toks[4 + 6 * s].c_str()),
                             (float)atof(toks[5 + 6 * s].c_str()),
                             (float)atof(toks[6 + 6 * s].c_str()),
                             (float)atof(toks[7 + 6 * s].c_str()),
                             (float)atof(toks[8 + 6 * s].c_str())});
            }
            // Pushed in lockstep so bsurf_joint[i] always describes bsurf[i].
            pm.bsurf_joint.push_back(bname);
            pm.bsurf.push_back(std::move(set));
            n_bs++;
          }
          continue;
        }
      }
      lg::info("[hd-phys] MESHSRC={} path={} links-with-samples={} dropped={}"
               " apex-links={} apex-dropped={}",
               mesh_src, mesh_path.string(), n_ms, n_ms_dropped, n_ax, n_ax_dropped);
      lg::info("[hd-phys] rigid-stage records (SPEC 11): rg={}", n_rg);
      // Separate line, once per parse, and INFO even at zero: a pack predating the `bs` records
      // is a legacy pack, not an error, and it must not warn-spam. sets=0 is the honest report
      // that the body surface was never delivered — the GOAL side counts that as "not measured".
      lg::info("[hd-phys] BSURFSRC={} bsets={} dropped={}", mesh_src, n_bs, n_bs_dropped);
    }
  }

  lg::info("[hd-phys] params loaded: {} models, {} chains", (int)s_phys_models.size(), n_chains);
  return n_sections;
}

// Lazy first-parse so there is no init-order dependency on the assets dir being resolved.
static void pc_physics_ensure_loaded() {
  if (!s_phys_loaded_once) {
    s_phys_loaded_once = true;
    pc_physics_parse_file();
  }
}

static const PhysModel* pc_physics_find_model(u32 ag_name) {
  std::string name = Ptr<String>(ag_name).c()->data();
  auto it = s_phys_models.find(name);
  return (it == s_phys_models.end()) ? nullptr : &it->second;
}

static s64 phys_mi(float v) {
  return (s64)llround((double)v * 1000.0);
}

// (Re)parse the params file. Hot-editable: adb push a new physics_chains.txt + call this.
s64 pc_physics_reload() {
  s_phys_loaded_once = true;
  return (s64)pc_physics_parse_file();
}

s64 pc_physics_generation() {
  pc_physics_ensure_loaded();
  return s_phys_generation;
}

// (chain_index << 8) | link_index for a joint's place in its model's chains; -1 if not a chain joint.
s64 pc_physics_joint_role(u32 ag_name, u32 joint_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model) {
    return -1;
  }
  std::string joint = Ptr<String>(joint_name).c()->data();
  for (size_t ci = 0; ci < model->chains.size(); ci++) {
    const auto& ch = model->chains[ci];
    for (size_t li = 0; li < ch.joints.size(); li++) {
      if (ch.joints[li] == joint) {
        return (s64)((ci << 8) | li);
      }
    }
  }
  return -1;
}

// milli chain param. unknown model/chain/param -> 0.
s64 pc_physics_chain_param_mi(u32 ag_name, s64 chain_index, s64 param_id) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain_index < 0 || chain_index >= (s64)model->chains.size()) {
    return 0;
  }
  if (param_id < 0 || param_id >= kPhysNumChainParams) {
    return 0;
  }
  return phys_mi(model->chains[chain_index].params[param_id]);
}

// per-LINK collision radius in milli; 0 when this chain declares no radii= (GOAL then falls back
// to the whole-chain radius=), so a data file without the key behaves exactly as before.
s64 pc_physics_chain_link_radius_mi(u32 ag_name, s64 chain, s64 link) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& radii = model->chains[chain].link_radius;
  if (link < 0 || link >= (s64)radii.size()) {
    return 0;
  }
  return phys_mi(radii[link]);
}

// per-LINK share of the organ's skin mass in milli; 0 when this chain declares no comw= (GOAL then
// publishes no COM excursion at all — a missing weight can never read as a COM of zero).
s64 pc_physics_chain_link_comw_mi(u32 ag_name, s64 chain, s64 link) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& comw = model->chains[chain].link_comw;
  if (link < 0 || link >= (s64)comw.size()) {
    return 0;
  }
  return phys_mi(comw[link]);
}

// SPEC 31 — `r` de la CHAIR pilotee par ce maillon, en milli. Rend 0 quand la chaine ne declare
// pas `spr=`, et 0 est ici la bonne lecture : `r=0` donne un poids de gradient nul avant
// normalisation, donc GOAL retombe sur le tenseur UNIFORME. Un canal absent ne fabrique rien.
s64 pc_physics_chain_link_spr_mi(u32 ag_name, s64 chain, s64 link) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& spr = model->chains[chain].link_spr;
  if (link < 0 || link >= (s64)spr.size()) {
    return 0;
  }
  return phys_mi(spr[link]);
}

// ---- the character PRESET, read as a CHANNEL (2026-08-22) -------------------------------------
// These are the preset keys the engine actually CONSUMES, in the order GOAL indexes them. The
// table lives here and not in GOAL so that "wired" is a property of one list: a key absent from
// this array has NO channel, and `pc_physics_chain_preset_absent` counts exactly those keys the
// delivered file carries and this list does not name. That count is what the report publishes as
// CANAL ABSENT — a named implementation gap, never a section reported as "not held".
static const char* kPhysPresetKeys[] = {
    "SupineProjectionScale",   // 0  section 10 — projection lost against the thorax, lying face-up
    "SupineWidthScale",        // 1  section 10
    "SupineHeightScale",       // 2  section 10
    "HangingLengthScale",      // 3  section 11 — torso horizontal, breast hanging free
    "HangingWidthScale",       // 4  section 11
    "HangingThicknessScale",   // 5  section 11
    "LowerBreastCompression",  // 6  section 12 — side gravity, lower breast squashed
    "SecondaryFrequency",      // 7  section 36 — secondary soft-tissue mode
    "SecondaryDampingRatio",   // 8  section 36
    "SecondaryJiggleHardMax",  // 9  section 36
    "APCompliance",            // 10 section 29 — anisotropie avant/arriere
    "LateralCompliance",       // 11 section 29
    "TorsionalCompliance",     // 12 section 29
    "AbsoluteStretchClamp",    // 13 section 22 — plafond dur d'elongation locale
    "BreastBreastRestitution", // 14 section 33
    "BreastChestRestitution",  // 15 section 34
    "NormalMaxApexDisplacement",  // 16 section 22 — le GENOU de la borne d'apex
    "DerivedApexSoftBand",        // 17 = HardMaxApex - NormalMaxApex, calcule par preset_apply.py
    "NormalMaxCOMDisplacement",   // 18 section 22 — le genou de la borne de COM
    "DerivedCOMSoftBand",         // 19 = HardMaxCOM - NormalMaxCOM, calcule par preset_apply.py
    "HardMaxCOMDisplacement",     // 20 section 22 — le plafond du canal radial
    "DerivedSupineProjectionYield",  // 21 = 1 - SupineProjectionScale ; la SECONDE copie de la
                                     //    cle 0, celle de `phys-vol-floor`. Une cle lue a un
                                     //    endroit et gardee en dur a l'autre rend une reponse
                                     //    partielle qu'on lit comme complete.
    "HardMaxApexDisplacement",       // 22 section 22 — le PLAFOND DUR de l'apex. Le cycle 109b
                                     //    l'a classee « CANAL ABSENT, aucun lecteur » alors que
                                     //    DEUX sites du moteur la portaient en dur (0.50 B0 dans
                                     //    `phys-apex-scale` et dans le plafond de torsion de la
                                     //    38), et que la NOTE-160 le DISAIT. L'audit cherchait le
                                     //    SITE au lieu de la VALEUR : il ne pouvait pas la voir.
    "VerticalCompliance",            // 23 section 29 — la TROISIEME ligne du tenseur d'anisotropie.
                                     //    Ses deux soeurs (10, 11) lisaient le fichier et elle
                                     //    restait le litteral `1.0`, entre les deux. Inerte sur
                                     //    les deux presets (1.00 partout) : c'est un bouton, pas
                                     //    un changement de comportement.
    "HardImpactSubstepsHi",          // 24 section 37 — sous-pas sur impact (4)
    "MinimumSubstepsAt60FPS",        // 25 section 37 — sous-pas nominal (2). `HardImpactSubstepsLo`
                                     //    (3) n'a AUCUN site : le moteur ne choisit qu'entre 4 et
                                     //    2, donc ce barreau de sa spec reste CANAL ABSENT et on
                                     //    le dit au lieu de l'arrondir.
    "NormalDynamicStretch",          // 26 section 22 — le NUMERATEUR du gain d'etirement dynamique.
                                     //    `PHYS-DYN-K = 0.43` etait la valeur 0.15/0.35 RECOPIEE
                                     //    dans le moteur : un litteral ajuste sur un RAPPORT de
                                     //    deux cles n'egale aucune valeur du preset, donc le
                                     //    balayage par valeur du cycle 114 ne pouvait pas le voir.
                                     //    Le denominateur (18) etait deja cable ; il manquait
                                     //    celle-ci. ATTENTION : la regle d'element neutre de
                                     //    `jak-hd-physics.gc` rendait 1.0 pour tout indice >= 22,
                                     //    ce qui aurait donne un gain de 1/0.35 = 2.857, soit 6.7x
                                     //    trop grand — elle est bornee a < 26 dans le meme lot.
    // (C138) SPEC 31 l.390 — « a useful deformation weighting is `w(r) = r^1.6...2.0` ». Les deux
    // bornes sont DANS le preset livre (`RootDeformationExponentLo/Hi`, SPEC:525) et n'avaient
    // AUCUN canal : le moteur appliquait UNE matrice par chaine, litteralement la transformation
    // affine unique que SPEC 8 l.143 interdit en gras. Le moteur en prend le MILIEU. Absentes,
    // la regle d'element neutre rend 0.0 pour ces deux indices, donc un exposant nul, donc un
    // poids de gradient 1 partout : le tenseur UNIFORME d'avant, identite par algebre.
    "RootDeformationExponentLo",     // 27 section 31
    "RootDeformationExponentHi",     // 28 section 31
};
static const int kPhysNumPresetKeys = (int)(sizeof(kPhysPresetKeys) / sizeof(kPhysPresetKeys[0]));

// milli value of wired preset key `key_id` for this chain, or -1 when the delivered file does not
// carry that key. -1 and not 0: `AdditionalStandingSag = 0.00` is a legitimate preset value, so a
// zero can never be allowed to mean "absent". GOAL turns -1 into the neutral element AND counts
// it, so a missing channel shows up in the trace instead of quietly restoring an old constant.
s64 pc_physics_chain_preset_mi(u32 ag_name, s64 chain, s64 key_id) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return -1;
  }
  if (key_id < 0 || key_id >= (s64)kPhysNumPresetKeys) {
    return -1;
  }
  const auto& ch = model->chains[chain];
  for (size_t i = 0; i < ch.pkey.size(); i++) {
    if (ch.pkey[i] == kPhysPresetKeys[key_id]) {
      return phys_mi(ch.pval[i]);
    }
  }
  return -1;
}

// how many `pk` keys this chain carries in the delivered file (the preset's own size).
s64 pc_physics_chain_preset_count(u32 ag_name, s64 chain) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  return (s64)model->chains[chain].pkey.size();
}

// how many of those keys have NO reader in this engine — the CANAL ABSENT count, measured on the
// delivered file rather than asserted in a report.
s64 pc_physics_chain_preset_absent(u32 ag_name, s64 chain) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& ch = model->chains[chain];
  s64 n = 0;
  for (size_t i = 0; i < ch.pkey.size(); i++) {
    bool wired = false;
    for (int k = 0; k < kPhysNumPresetKeys; k++) {
      if (ch.pkey[i] == kPhysPresetKeys[k]) {
        wired = true;
        break;
      }
    }
    if (!wired) {
      n++;
    }
  }
  return n;
}

// (C51) the APEX region representative for one link, in milli. `axis` selects: 0 = w, the share
// of the distal region's skin mass this link carries; 1/2/3 = x/y/z of that region's centroid in
// this link's bone-local bind space, game units. 0 when this chain declares no ax= record — GOAL
// then publishes no apex at all, exactly as comw= does for the COM.
s64 pc_physics_chain_link_apex_mi(u32 ag_name, s64 chain, s64 link, s64 axis) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& aw = model->chains[chain].link_apexw;
  if (link < 0 || link >= (s64)aw.size()) {
    return 0;
  }
  if (axis == 0) {
    return phys_mi(aw[link]);
  }
  if (axis < 1 || axis > 3) {
    return 0;
  }
  return phys_mi(model->chains[chain].link_apexp[link][axis - 1]);
}

// (C132) SPEC 31 — composante `axis` (0=x, 1=y, 2=z) du point r=0 de ce maillon, en milli, espace
// os local, pose de bind. Rend 0 quand la chaine ne declare pas `anp=` — et 0 est ici la bonne
// valeur neutre, parce qu'un offset nul EST le comportement d'avant ce cycle (contrairement a
// `preset_mi` qui doit rendre -1 pour distinguer « absente » de « vaut zero »).
s64 pc_physics_chain_link_anp_mi(u32 ag_name, s64 chain, s64 link, s64 axis) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& ap = model->chains[chain].link_anp;
  if (link < 0 || link >= (s64)ap.size()) {
    return 0;
  }
  if (axis < 0 || axis > 2) {
    return 0;
  }
  return phys_mi(ap[link][axis]);
}

// (C128) SPEC 11 — une des 12 constantes de l'ETAGE RIGIDE, en milli. `idx` = b * 4 + q, avec
// b 0..2 = {ancre, maillon 0, maillon 1} et q 0..3 = {ds.x, ds.y, ds.z, dm*1000}. Rend 0 quand la
// chaine ne declare pas de `rg` : GOAL lit alors un vecteur nul, la garde de non-vacuite ne tire
// pas, et la cible de forme de SPEC 11 reste celle d'avant le cycle 128. Un manque de donnee ne
// doit jamais se lire comme une correction de zero.
s64 pc_physics_chain_rigid_mi(u32 ag_name, s64 chain, s64 idx) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size() || idx < 0 || idx > 11) {
    return 0;
  }
  const auto& ch = model->chains[chain];
  if (!ch.rigid_stage_set) {
    return 0;
  }
  return phys_mi(ch.rigid_stage[idx / 4][idx % 4]);
}

// (C14) how many mesh samples this link carries (0..5). 0 = the mesh never reaches beyond the
// link's own radius test, or physics_mesh.txt is absent — either way the GOAL side counts that
// link out of meshtested=, so a missing file can never read as a clean mesh audit.
s64 pc_physics_chain_msample_count(u32 ag_name, s64 chain, s64 link) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& ms = model->chains[chain].mesh_samples;
  if (link < 0 || link >= (s64)ms.size()) {
    return 0;
  }
  return (s64)ms[link].size();
}

// (C14) one coordinate of one mesh sample, milli game units, bone-local bind space.
// link_si packs (link << 3) | sample_index; coord 0/1/2 = x/y/z. Packed because the GOAL FFI here
// carries at most four parameters, same convention as pc-physics-joint-role's (chain<<8)|link.
s64 pc_physics_chain_msample_mi(u32 ag_name, s64 chain, s64 link_si, s64 coord) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& ms = model->chains[chain].mesh_samples;
  s64 link = link_si >> 3;
  s64 si = link_si & 7;
  if (link < 0 || link >= (s64)ms.size() || si >= (s64)ms[link].size() || coord < 0 || coord > 2) {
    return 0;
  }
  return phys_mi(ms[link][si][(size_t)coord]);
}

// bitmask of the chain indices named by xchain=, resolved in this same model — the identical
// lookup pc_physics_collider_param_mi field 1 does for chains=. 0 = no chain-vs-chain partner,
// which is every pre-cycle-6 line, so silence in the data keeps the old behaviour.
s64 pc_physics_chain_xmask(u32 ag_name, s64 chain) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  s64 mask = 0;
  for (const auto& want : model->chains[chain].xchains) {
    bool found = false;
    for (size_t ci = 0; ci < model->chains.size(); ci++) {
      if (model->chains[ci].name == want) {
        mask |= ((s64)1 << (s64)ci);
        found = true;
      }
    }
    if (!found) {
      // Once per (art-group, unresolved name): the sim reads this every frame, and an xchain= that
      // resolves to nothing is a PAIR THAT NEVER COLLIDES — a data typo the owner must see, but
      // once per typo, not once per frame.
      static std::set<std::string> s_warned_xchain;
      std::string ag = Ptr<String>(ag_name).c()->data();
      if (s_warned_xchain.insert(ag + "|" + want).second) {
        lg::warn("[hd-phys] {}: chain xchain= references unknown chain '{}' (ignored)", ag, want);
      }
    }
  }
  return mask;
}

// class bits (primary=1 secondary=2 accessory=4); 0 if unknown.
s64 pc_physics_chain_flags(u32 ag_name, s64 chain_index) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain_index < 0 || chain_index >= (s64)model->chains.size()) {
    return 0;
  }
  return (s64)model->chains[chain_index].class_bits;
}

s64 pc_physics_num_chains(u32 ag_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  return model ? (s64)model->chains.size() : 0;
}

// Level params, EVERYTHING milli (substeps/iters/collide/classmask included — the caller divides by
// 1000 uniformly). Level is clamped to the configured range.
s64 pc_physics_level_param_mi(s64 level, s64 param_id) {
  pc_physics_ensure_loaded();
  if (s_phys_level_count <= 0) {
    return 0;
  }
  if (param_id < 0 || param_id >= kPhysNumLevelParams) {
    return 0;
  }
  s64 lv = level;
  if (lv < 0) {
    lv = 0;
  }
  if (lv > s_phys_level_count - 1) {
    lv = s_phys_level_count - 1;
  }
  return phys_mi(s_phys_levels[lv][param_id]);
}

// milli collider radius attached to a named joint; 0 = no collider there.
// LEGACY accessor: only sees filterless (applies-to-all) colliders, first match wins.
s64 pc_physics_joint_collider_mi(u32 ag_name, u32 joint_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model) {
    return 0;
  }
  std::string joint = Ptr<String>(joint_name).c()->data();
  for (const auto& col : model->colliders) {
    if (col.joint == joint && col.chains.empty()) {
      return phys_mi(col.radius);
    }
  }
  return 0;
}

// number of colliders declared for the model; 0 if the model is unknown.
s64 pc_physics_num_colliders(u32 ag_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  return model ? (s64)model->colliders.size() : 0;
}

// field 0 = radius in milli. field 1 = chain-applicability bitmask, RAW (not milli): bit c set if
// this collider applies to chain index c. An empty chains= filter -> -1 (all chains).
// field 2 = tier, RAW (1 = core, 2 = extended). field 3 = shape, RAW: 1 if this is a CAPSULE
// (joint2 set), 0 if it is a plain sphere. field 4 = FAR-END radius in milli for a TAPERED capsule
// (cycle 3, owner C: flared trousers / shoulders); falls back to `radius` when radius2 is unset, so
// every existing line keeps its cylinder shape.
// field 5 = side=, RAW (0 none, 1 L, 2 R) — cross-side penetration accounting.
// field 6 = the at= chain, RESOLVED to a 0-based chain index of this same model (the identical
// lookup field 1 does for chains=): the sphere is then centred on that chain's SIMULATED TIP rather
// than on a bone. -1 when no at= was declared, and -1 (plus a one-shot warning naming the
// art-group and the unresolved name) when at= names a chain this model does not have.
s64 pc_physics_collider_param_mi(u32 ag_name, s64 idx, s64 field) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->colliders.size()) {
    return 0;
  }
  const auto& col = model->colliders[idx];
  if (field == 0) {
    return phys_mi(col.radius);
  }
  if (field == 1) {
    if (col.chains.empty()) {
      return -1;
    }
    s64 mask = 0;
    for (const auto& want : col.chains) {
      bool found = false;
      for (size_t ci = 0; ci < model->chains.size(); ci++) {
        if (model->chains[ci].name == want) {
          mask |= ((s64)1 << (s64)ci);
          found = true;
        }
      }
      if (!found) {
        lg::warn("[hd-phys] collider {} chains= references unknown chain '{}' (ignored)", col.joint,
                 want);
      }
    }
    if (mask == 0) {
      lg::warn("[hd-phys] collider {} chains= resolved to zero chains (collider inert)", col.joint);
    }
    return mask;
  }
  if (field == 2) {
    return (s64)col.tier;
  }
  if (field == 4) {
    return phys_mi(col.radius2 > 0.f ? col.radius2 : col.radius);
  }
  if (field == 3) {
    return col.joint2.empty() ? 0 : 1;
  }
  if (field == 5) {
    return (s64)col.side;
  }
  if (field == 6) {
    if (col.chainref.empty()) {
      return -1;
    }
    for (size_t ci = 0; ci < model->chains.size(); ci++) {
      if (model->chains[ci].name == col.chainref) {
        return (s64)ci;
      }
    }
    // Once per (art-group, unresolved name): this is read every frame by the sim, and an
    // unresolvable at= is a data typo the owner must SEE — but only once per typo, not per frame.
    static std::set<std::string> s_warned_chainref;
    std::string ag = Ptr<String>(ag_name).c()->data();
    if (s_warned_chainref.insert(ag + "|" + col.chainref).second) {
      lg::warn("[hd-phys] {}: collider at= references unknown chain '{}' (no attach)", ag,
               col.chainref);
    }
    return -1;
  }
  // 7/8/9 — le CENTRE de la sphere dans l'espace bind de son joint (offset=), en milli-unites
  // comme tout ce qui traverse la frontiere. Zero = centre sur le joint, l'ancien comportement.
  if (field == 7) {
    return phys_mi(col.ox);
  }
  if (field == 8) {
    return phys_mi(col.oy);
  }
  if (field == 9) {
    return phys_mi(col.oz);
  }
  return 0;
}

// 1 if collider idx of the model sits on joint_name (exact match), else 0.
s64 pc_physics_collider_is_joint(u32 ag_name, s64 idx, u32 joint_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->colliders.size()) {
    return 0;
  }
  std::string joint = Ptr<String>(joint_name).c()->data();
  return model->colliders[idx].joint == joint ? 1 : 0;
}

// 1 if collider idx of the model is a CAPSULE whose second joint is joint_name (exact match),
// else 0 (a plain sphere has no joint2 and always answers 0).
s64 pc_physics_collider_is_joint2(u32 ag_name, s64 idx, u32 joint_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->colliders.size()) {
    return 0;
  }
  if (model->colliders[idx].joint2.empty()) {
    return 0;
  }
  std::string joint = Ptr<String>(joint_name).c()->data();
  return model->colliders[idx].joint2 == joint ? 1 : 0;
}

// ---- (SPEC 18) body SURFACE sets: the real skinned surface, not a proxy volume ----------------
// Same milli convention as everything else on this boundary: no float ever crosses it (the
// float-return-register trap on this port), so positions AND normals come back as x1000 ints.
// Every index is bounds-checked and answers 0 out of range: these are read from a hot GOAL loop
// with indices derived from a file the owner can edit on device.

// number of body-surface sets for this art-group; 0 if none/unknown (a legacy physics_mesh.txt
// with no `bs` records answers 0 here, and the audit reads that as "not measured").
s64 pc_physics_num_bsurf(u32 ag_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  return model ? (s64)model->bsurf.size() : 0;
}

// 1 if body-surface set idx sits on joint_name (exact match, same comparison
// pc_physics_collider_is_joint makes), else 0.
s64 pc_physics_bsurf_is_joint(u32 ag_name, s64 idx, u32 joint_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->bsurf_joint.size()) {
    return 0;
  }
  std::string joint = Ptr<String>(joint_name).c()->data();
  return model->bsurf_joint[idx] == joint ? 1 : 0;
}

// how many surface samples set idx carries; 0 if the set index is out of range.
s64 pc_physics_bsurf_count(u32 ag_name, s64 idx) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->bsurf.size()) {
    return 0;
  }
  return (s64)model->bsurf[idx].size();
}

// component `comp` of sample `s` of set `idx`, MILLI-units: comp 0..2 = position xyz,
// comp 3..5 = outward normal xyz. 0 if any index is out of range.
s64 pc_physics_bsurf_mi(u32 ag_name, s64 idx, s64 s, s64 comp) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->bsurf.size()) {
    return 0;
  }
  const auto& set = model->bsurf[idx];
  if (s < 0 || s >= (s64)set.size() || comp < 0 || comp > 5) {
    return 0;
  }
  return phys_mi(set[s][(size_t)comp]);
}

// 0 = off (toggle off, or no params loaded); else level + 1.
s64 pc_physics_enabled() {
  pc_physics_ensure_loaded();
  if (!s_physics_on || s_phys_models.empty()) {
    return 0;
  }
  return (s64)(s_physics_level + 1);
}
#endif

// Gpbrf owner workflow (2026-07-24): POSITION DUMP for deterministic weld-ON/OFF daytime A/B.
// The owner stands on a seam; the supervisor must read his EXACT world position to warp there for
// A/B captures. The Honor obscures logcat (HKS encryption), so lg::info is unreadable there =>
// write to a FILE instead. On debug.opengoal.dump.pos = "1" (Android) / env OG_DUMP_POS (desktop),
// write Jak's CURRENT world position as "X Y Z" IN METERS (÷4096 — the exact units
// debug.opengoal.level.warp.pos consumes, so the string is directly pasteable) to
// files/pos_dump.txt in the app files dir. Pull it with:
//   run-as org.opengoal.gk.jak1 cat files/pos_dump.txt
// pc_set_jak_pos runs every logic frame while *target* exists, so throttle the disk write to ~4 Hz.
static void maybe_dump_jak_pos(float gx, float gy, float gz) {
  bool enabled = false;
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.dump.pos", buf) > 0 && buf[0] && buf[0] != '0') {
    enabled = true;
  }
#else
  if (const char* e = std::getenv("OG_DUMP_POS")) {
    enabled = (e[0] && e[0] != '0');
  }
#endif
  if (!enabled) {
    return;
  }
  static std::chrono::steady_clock::time_point s_last{};
  auto now = std::chrono::steady_clock::now();
  if (s_last.time_since_epoch().count() != 0 &&
      std::chrono::duration_cast<std::chrono::milliseconds>(now - s_last).count() < 250) {
    return;
  }
  s_last = now;
  const float mx = gx / 4096.f, my = gy / 4096.f, mz = gz / 4096.f;
  try {
    // Line 1 = the bare "X Y Z" meters (directly pasteable into debug.opengoal.level.warp.pos).
    // Line 2 = a human comment (level.warp.pos' sscanf reads only the first %f %f %f, so the
    // comment is harmless). Raw GOAL units kept for cross-checking against the warp patch.
    std::string body = fmt::format("{:.2f} {:.2f} {:.2f}\n; jak world pos (meters, level.warp.pos units); raw goal=({:.0f} {:.0f} {:.0f})\n",
                                   mx, my, mz, gx, gy, gz);
    file_util::write_text_file(file_util::get_jak_project_dir() / "pos_dump.txt", body);
  } catch (...) {
    // best-effort debug channel; never let a file error affect the game loop
  }
}

// Grecharged-grass-poc: push Jak's world position (a GOAL vector, xyzw) each frame
// so the grass renderer can flatten blades where the player walks. w := 1.0 marks
// the value valid (GOAL only calls this while *target* exists).
void pc_set_jak_pos(u32 vec) {
  if (!vec) {
    return;
  }
  float* p = Ptr<float>(vec).c();
  Gfx::g_global_settings.recharged_jak_pos[0] = p[0];
  Gfx::g_global_settings.recharged_jak_pos[1] = p[1];
  Gfx::g_global_settings.recharged_jak_pos[2] = p[2];
  Gfx::g_global_settings.recharged_jak_pos[3] = 1.0f;
  maybe_dump_jak_pos(p[0], p[1], p[2]);  // Gpbrf owner workflow: gated pos_dump.txt for A/B warps
}

// Grecharged-grass-poc POLISH#4/#5: push the adjustable grass view distances + density (a GOAL
// vector, x = near-blade fade-out (m), y = grass-card fade-out (m)).
// Ggrass-density-presets (owner 2026-08-30) : z ne porte PLUS un pourcentage mais l'INDICE DE PALIER
// (0..4). GOAL y ecrit `recharged-grass-density-preset`, un entier converti en flottant pour tenir
// dans le vecteur ; on le borne ici, du cote qui l'utilise, plutot que de faire confiance a l'appelant.
void pc_set_grass_dists(u32 vec) {
  if (!vec) {
    return;
  }
  float* p = Ptr<float>(vec).c();
  recharged_gating::set(recharged_gating::kGrassNearDist, p[0]);
  recharged_gating::set(recharged_gating::kGrassCardDist, p[1]);
  recharged_gating::set(recharged_gating::kGrassDensity,
                        grass_bake::clamp_density_preset((int)(p[2] + 0.5f)));
  // Grecharged-grass-precompute-mode: w channel = GRASS MODE toggle (1.0 = PRECOMPUTED baked
  // day-cycle tables / 0.0 = LIVE full at-load scan). GOAL now writes w in the scratch vector.
  recharged_gating::set(recharged_gating::kGrassPrecomputed, p[3] > 0.5f);
}

// Grecharged-grass-precompute-mode verification aid: fixed time-of-day for A/B captures.
// Android: prop debug.opengoal.tod.hour ("9.5" = 09:30). Desktop: env GRASS_TOD. Returns
// hour*100 as int (950), or -1 when unset/invalid. Read at most once per second.
// ── lighting-hdr essai 6 : les deux gestes du jeu d'images (contrat : refset.h) ──────────────
// Ils passent par GOAL parce que les deux grandeurs a toucher vivent dans le tas GOAL : la
// phase des lanceurs (`sparticle-launch-control`) et `*sp-frame-time*`. Les deux fonctions
// rendent 0 hors du mode `refset` : appelees a chaque image, elles sont alors un simple test de
// booleen, et le joueur ne rencontre jamais ce chemin.
u64 pc_refset_repin_parts() {
  return refset::wants_particle_repin() ? 1 : 0;
}

u64 pc_refset_part_step() {
  return (u64)(s64)refset::particle_step_mode();
}

// L'AUTRE HORLOGE DU FEU. Voir `refset::mood_flame_pin()`. Rend -1 hors du mode refset, et
// `update-mood-flames` garde alors exactement son chemin d'origine.
u64 pc_refset_mood_flame() {
  return (u64)(s64)refset::mood_flame_pin();
}

// LE SILENCE DES INCRUSTATIONS DE TEXTE. Voir `refset::text_mute()`. Rend 0 hors du mode refset,
// et `print-game-text` garde alors exactement son chemin d'origine.
u64 pc_refset_text_mute() {
  return (u64)(s64)refset::text_mute();
}

// LE SILENCE DES INCRUSTATIONS DE DEBUG PENDANT UNE MESURE. Le compteur FPS est dessine DANS le
// tampon que le jeu d'images relit : mesure du 2026-09-06, ses chiffres a eux seuls font 57 a
// 112 pixels d'ecart entre la reference et le rejeu (maxdiff 225 a 228), et c'est du temps
// MURAL — il ne peut pas etre reproductible. Un texte qui change parce que la machine a ete
// plus rapide n'a rien a faire dans une comparaison bit a bit.
u64 pc_refset_active() {
  return refset::enabled() ? 1 : 0;
}

// QUELS NIVEAUX ONT UN CIEL. `level-load-info.sky` vit dans le tas GOAL et n'a aucun equivalent
// cote C++ : le fr3 charge par `Loader` ne porte que la geometrie. C'est pourtant CE champ que
// le jeu teste lui-meme avant d'emettre le DMA du ciel (`sky-tng.gc:901`), donc c'est la seule
// definition non devinee de « ce niveau a un ciel ». Le fil GOAL l'annonce pour chaque niveau
// ACTIF, une fois par image ; hors du mode refset `note_level_sky` sort immediatement.
void pc_refset_note_level(u32 name, s32 has_sky) {
  refset::note_level_sky(name ? Ptr<String>(name).c()->data() : nullptr, has_sky);
}

// LA CAMERA EPINGLEE DU JEU DE REFERENCES. Rend 1 et remplit les deux vecteurs GOAL (position
// en METRES, avant unitaire) quand la pose est calculee ; 0 = la camera du jeu garde la main.
// Les vecteurs GOAL sont quatre flottants ; on n'ecrit que les trois premiers et on laisse `w`.
// Contrat et raison d'etre : game/graphics/refset.h, section « LA CAMERA EPINGLEE ».
u64 pc_refset_camera(u32 trans_vec, u32 fwd_vec) {
  if (!trans_vec || !fwd_vec) {
    return 0;
  }
  float t[3] = {0.f, 0.f, 0.f}, f[3] = {0.f, 0.f, 1.f};
  if (!refset::camera_pin(t, f)) {
    return 0;
  }
  float* gt = (float*)(g_ee_main_mem + trans_vec);
  float* gf = (float*)(g_ee_main_mem + fwd_vec);
  // METER_LENGTH : la memoire GOAL porte les longueurs en metres x 4096.
  gt[0] = t[0] * 4096.f;
  gt[1] = t[1] * 4096.f;
  gt[2] = t[2] * 4096.f;
  gf[0] = f[0];
  gf[1] = f[1];
  gf[2] = f[2];
  return 1;
}

u64 pc_get_tod_hour() {
  // lighting-census : quand un jeu d'images de reference est en cours, c'est LUI qui impose
  // l'heure, et il la change entre deux etapes. Le cache d'une seconde ci-dessous serait alors
  // une source de non-determinisme (l'heure appliquee dependrait de la montre), donc la
  // surcharge est lue AVANT lui, a chaque image. Hors de ce mode, rien ne change.
  {
    const int ov = refset::tod_override_x100();
    if (ov >= 0) {
      return (u64)(s64)ov;
    }
  }
  static s64 s_cached = -1;
  static std::chrono::steady_clock::time_point s_last{};
  auto now = std::chrono::steady_clock::now();
  if (s_last.time_since_epoch().count() != 0 &&
      std::chrono::duration_cast<std::chrono::milliseconds>(now - s_last).count() < 1000) {
    return (u64)s_cached;
  }
  s_last = now;
  const char* val = nullptr;
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.tod.hour", buf) > 0 && buf[0]) {
    val = buf;
  }
#else
  val = std::getenv("GRASS_TOD");
#endif
  if (val && val[0]) {
    double h = std::atof(val);
    if (h >= 0.0 && h < 24.0) {
      s_cached = (s64)(h * 100.0);
    } else {
      s_cached = -1;
    }
  } else {
    s_cached = -1;
  }
  return (u64)s_cached;
}

// Grecharged-hd-models: 1 if the build carries the enhanced HD-model FR3 set (fr3/enhanced/GAME.fr3
// present), else 0. Drives the ENHANCED MODELS menu-row visibility so the toggle only appears when
// jak2 assets were available at build time. Works on x86 and Android (get_fr3_dir already resolves the
// unpacked external asset root on device).
#ifdef OG_FEAT_HD_MODELS
u64 pc_get_enhanced_models_available() {
  auto p = file_util::get_fr3_dir(GameVersion::Jak1) / "enhanced" / "GAME.fr3";
  return file_util::file_exists(p.string()) ? 1 : 0;
}
#endif

// Grecharged-grass-poc ROUND#21d: ground-actor positions from GOAL (the pc-set-jak-pos! pattern —
// exact world coords from each actor's root trans; the Merc2 camera-space recovery is dead). The pc
// glue calls clear!, then add! per actor, then publish! every ~30 frames. kind: 0 = CULL (static
// unbreakable: warp-gate button, eco vent, speaker), 1 = TRAMPLE (breakable: crates, scarecrows — a
// broken crate stops being pushed, so the renderer's eased spring-back plays). The radius arrives as
// a GOAL-units integer (meters * 4096) because GOAL passes args in GPRs (no float ABI).
void pc_grass_occ_clear() {
  grass_occ::goal_clear();
}
void pc_grass_occ_add(u32 kind, u32 vec, u32 r_units) {
  if (!vec) {
    return;
  }
  float* p = Ptr<float>(vec).c();
  grass_occ::goal_add((int)kind, p[0], p[1], p[2], (float)r_units);
}
void pc_grass_occ_add_moving(u32 actor_id, u32 vec, u32 r_units) {
  if (!vec) {
    return;
  }
  float* p = Ptr<float>(vec).c();
  grass_occ::goal_add_moving(actor_id, p[0], p[1], p[2], (float)r_units);
}
void pc_grass_occ_publish() {
  grass_occ::goal_publish();
}

// R28: called from the scarecrow break path at the exact clear-collide frame — instantly cancels the
// trample at that spot (ghost erased + 8 s tombstone). No-op when grass is off (empty ghost lists).
void pc_grass_tramp_break(u32 vec) {
  if (!vec) {
    return;
  }
  float* p = Ptr<float>(vec).c();
  grass_occ::goal_break_at(p[0], p[1], p[2]);
}

// Grecharged-grass-poc POLISH#4: push Jak's ledge-grab point (a GOAL vector, xyz) while he hangs on
// a ledge, so the grass on that ledge parts around his hands. GOAL passes a null vector (0) to clear
// it the moment he lets go, so a stale grab point never keeps parting the grass.
void pc_set_jak_ledge(u32 vec) {
  if (!vec) {
    Gfx::g_global_settings.recharged_jak_ledge[3] = 0.0f;
    return;
  }
  float* p = Ptr<float>(vec).c();
  Gfx::g_global_settings.recharged_jak_ledge[0] = p[0];
  Gfx::g_global_settings.recharged_jak_ledge[1] = p[1];
  Gfx::g_global_settings.recharged_jak_ledge[2] = p[2];
  Gfx::g_global_settings.recharged_jak_ledge[3] = 1.0f;
}

// lighting-legacy-purge (2026-09-11) : `pc_set_modern_materials` est SUPPRIME avec la pile
// « Materiaux avances ». La rangee livrait OFF : la pile n'a jamais touche un pixel.

#ifdef OG_FEAT_PBR
// lighting-legacy-purge (2026-09-11) : `pc_set_pbr` est SUPPRIME. Le rendu PBR n'est plus une
// option : il est INCONDITIONNEL sous « lighting ».

// Grecharged-directional-ambient ITEM B (owner playtest #2, 2026-07-20): the mood COLOR values the
// realtime-lighting path consumes — current-sun sun-color/env-color, light-group 0 colors, and
// current-shadow — are the OUTPUT of a 2-snapshot lerp (update-mood-sky-texture / update-mood-palette
// over *default-interp-table*) that HARD-SWITCHES which two of the 8 moods it lerps between at the
// hour boundaries ~04:00 / 07:00 / 08-09:00 (snapshot1 defaults to 0). Each basis switch is a 1-frame
// DISCONTINUITY in the value => the owner's "2 brutal light steps at night + 1 at sunrise". The stock
// BAKED path is smooth because it crossfades all 8 palette slots per-vertex; there is no single
// continuous sun/ambient COLOR to read instead. So we TEMPORALLY LOW-PASS the stepped color inputs
// here (translation-layer fix, once per frame at the FFI push): a 1-frame step becomes a smooth ~0.7s
// ramp => continuous like the baked path. Smoothing runs UNCONDITIONALLY (seeded on the first frame):
// OFF==stock is preserved by the SHADER gate — with realtime-lighting AND pbr-materials off the world
// shaders take the stock baked path and never read these fields, so a smoothed value is invisible
// (byte-identical). Running it always also means a later menu-enable sees an already-tracked value (no
// enable ramp). It is NOT gated on the pc-setting because the on-device A/B forces the realtime path via
// the debug.opengoal.rt.light PROP, which the FFI push cannot see. Tunable / A-B-defeatable via
// debug.opengoal.rt.todsmooth ("0" => raw stepped = the before; a float in (0,1] => that per-frame EMA
// weight; empty => the shipped default below).
static float rt_tod_smooth_alpha() {
  float a = 0.10f;  // per-frame EMA weight toward the new raw value (~0.7 s ramp @30 fps)
#ifdef __ANDROID__
  char b[PROP_VALUE_MAX];
  if (__system_property_get("debug.opengoal.rt.todsmooth", b) > 0 && b[0]) {
    a = (float)atof(b);
  }
#else
  if (const char* e = std::getenv("OG_RT_TODSMOOTH")) {
    a = (float)atof(e);
  }
#endif
  if (!(a >= 0.0f && a <= 1.0f)) {
    a = 0.10f;
  }
  return a;
}
// Exponential moving average of an n-float array in place toward `raw`. When `seed` (first frame,
// realtime lighting off, or smoothing disabled) it SNAPS to raw so a later enable starts from the
// true value (no boot ramp / stale-value flash).
static void rt_ema(float* dst, const float* raw, int n, float alpha, bool seed) {
  if (seed || alpha <= 0.0f) {
    for (int i = 0; i < n; i++) {
      dst[i] = raw[i];
    }
    return;
  }
  for (int i = 0; i < n; i++) {
    dst[i] += alpha * (raw[i] - dst[i]);
  }
}

// Grecharged-pbr-materials: per-frame mood/TOD sun state (three GOAL vectors, xyz each):
// shadow = current-shadow light-travel dir, sun_color = mood-sun sun-color, env = env-color.
// ITEM B: the three colors are EMA-smoothed (see rt_ema above) so the day/night snapshot steps ramp
// smoothly. The visible-sun DIRECTION is taken elsewhere from the already-continuous *sky-parms* sun
// position, so current-shadow is smoothed only for the night-time azimuthal ambient key.
void pc_set_pbr_sun(u32 shadow_vec, u32 sun_color_vec, u32 env_color_vec) {
  auto& gs = Gfx::g_global_settings;
  float* s = Ptr<float>(shadow_vec).c();
  float* c = Ptr<float>(sun_color_vec).c();
  float* e = Ptr<float>(env_color_vec).c();
  float raw_s[3] = {s[0], s[1], s[2]};
  float raw_c[3] = {c[0], c[1], c[2]};
  float raw_e[3] = {e[0], e[1], e[2]};
  static bool s_seed_sun = true;
  float alpha = rt_tod_smooth_alpha();
  bool seed = s_seed_sun || alpha <= 0.0f;
  rt_ema(gs.recharged_pbr_shadow, raw_s, 3, alpha, seed);
  rt_ema(gs.recharged_pbr_sun_color, raw_c, 3, alpha, seed);
  rt_ema(gs.recharged_pbr_ambient, raw_e, 3, alpha, seed);
  s_seed_sun = false;
}

// Round-5 addendum suspect (c): the VISIBLE sun's dome direction — *sky-parms* upload-data
// sun 0 pos, the exact vector the sun sprite is placed with (sparticle-track-sun:
// sun_world = camera + pos*4096). Camera->sun; magnitude ~ orbit dist (not unit).
void pc_set_pbr_sky_sun(u32 pos_vec) {
  float* p = Ptr<float>(pos_vec).c();
  Gfx::g_global_settings.recharged_pbr_sky_sun[0] = p[0];
  Gfx::g_global_settings.recharged_pbr_sky_sun[1] = p[1];
  Gfx::g_global_settings.recharged_pbr_sky_sun[2] = p[2];
}

// Grecharged-directional-ambient (owner playtest #3): the GREEN SUN's REAL sky position —
// *sky-parms* upload-data sun 1 pos (sun index 1 = the precursor green sun, computed every
// frame by sky-make-sun-data 1). Same camera->sun convention as the yellow sun above. Feeds
// the realtime green directional light (day AND night when it is above the horizon) + the
// night cast-shadow direction.
void pc_set_pbr_green_sun(u32 pos_vec) {
  float* p = Ptr<float>(pos_vec).c();
  Gfx::g_global_settings.recharged_pbr_green_sun[0] = p[0];
  Gfx::g_global_settings.recharged_pbr_green_sun[1] = p[1];
  Gfx::g_global_settings.recharged_pbr_green_sun[2] = p[2];
}

// Round-4 multi-light: GOAL passes (-> *time-of-day-context* light-group 0) — a light-group,
// four inline `light`s (dir0/dir1/dir2/ambi), each 48 bytes: direction vec16 @+0, color rgbaf16
// @+16, levels vec16 @+32 (levels.x = morph weight). Raw 0..255 colors; scaled at the GL boundary.
void pc_set_pbr_lights(u32 lg) {
  auto* base = Ptr<float>(lg).c();
  auto& gs = Gfx::g_global_settings;
  // Gather the raw light-group into flat arrays first, then EMA-smooth the DIRECTIONS + COLORS + ambi
  // (ITEM B: the light-group colors snapshot-step across TOD exactly like current-sun). The morph
  // LEVEL is a per-light blend weight, left raw.
  float raw_dir[9], raw_col[9], raw_ambi[3], raw_lvl[3];
  for (int i = 0; i < 3; i++) {
    const float* l = base + i * 12;  // 48 bytes = 12 floats
    for (int j = 0; j < 3; j++) {
      raw_dir[i * 3 + j] = l[j];
      raw_col[i * 3 + j] = l[4 + j];
    }
    raw_lvl[i] = l[8];
  }
  const float* ambi = base + 3 * 12;
  for (int j = 0; j < 3; j++) raw_ambi[j] = ambi[4 + j];
  static bool s_seed_lights = true;
  float alpha = rt_tod_smooth_alpha();
  bool seed = s_seed_lights || alpha <= 0.0f;
  rt_ema(&gs.recharged_pbr_lg_dir[0][0], raw_dir, 9, alpha, seed);
  rt_ema(&gs.recharged_pbr_lg_color[0][0], raw_col, 9, alpha, seed);
  rt_ema(gs.recharged_pbr_lg_ambi, raw_ambi, 3, alpha, seed);
  for (int i = 0; i < 3; i++) gs.recharged_pbr_lg_level[i] = raw_lvl[i];
  gs.recharged_pbr_lg_valid = true;
  s_seed_lights = false;
}

// Grecharged-realtime-lighting (2026-07-19 REWRITE): SUN-ONLY realtime lighting toggles,
// pushed from GOAL each frame. rt-light! = master.
void pc_set_rt_light(u32 sym) {
  recharged_gating::set(recharged_gating::kRtLight, (sym != 0));
  // lighting-legacy-purge (2026-09-11) : le NETTOYAGE SAIN du sentinel de la garde anti-boucle
  // vivait dans `pc_set_pbr_displacement`, supprime par cet item. Sans lui la garde ne s'effacerait
  // plus jamais et un bootage rugueux la ferait mordre a chaque lancement suivant — un changement
  // de comportement que cet item n'a pas le droit de faire. Il est donc DEPLACE ici : meme pousse
  // par image depuis `update-to-os` (hud-classes-pc.gc:1823), meme condition, meme effet.
  static bool did_clear = false;
  if (!did_clear && s_recharged_boot_t >= 0.0) {
    double now =
        std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
    if (now - s_recharged_boot_t > kRechargedGuardHealthySecs) {
      std::error_code ec;
      fs::remove(recharged_boot_guard_path(), ec);
      did_clear = true;
      lg::info("[recharged] crash-loop guard: healthy boot, sentinel cleared");
    }
  }
}
// lighting-legacy-purge (2026-09-11) : `pc_set_rt_ambient`, `pc_set_rt_ambient_strength`,
// `pc_set_pbr_texture_relief` et `pc_set_pbr_specular_intensity` sont SUPPRIMES. L'ambiante est
// desormais inconditionnelle sous l'eclairage ; sa force, le RELIEF et la SPECULAIRE sont figes
// dans RechargedFixed (gfx.h) sur leurs valeurs livrees.
// lighting-legacy-purge (2026-09-11) : `pc_set_pbr_displacement`, `pc_set_pbr_isolate`,
// `pc_set_rt_ambient_contrast`, `pc_set_rt_ambient_model`, `pc_set_rt_shadow_res`,
// `pc_set_rt_shadow_dist` et `pc_set_rt_shadow_strength` sont SUPPRIMES. DISPLACEMENT vaut
// desormais RechargedFixed::kPbrDisplacement (PARALLAX), PBR ISOLATE valait 0 = chemin complet,
// le CONTRASTE d'ambiante n'avait aucun lecteur GLSL, et le modele / la resolution / la portee /
// la force de l'ombre sont figes dans RechargedFixed.
// AVEC eux part le seul ecrivain de `pbr_tan_diag.txt` et `pbr_reach.txt` : ces deux fichiers de
// diagnostic vivaient DANS `pc_set_pbr_isolate` (sections POM / couverture / reach). Ils ne sont
// plus ecrits ; les sections elles-memes restent disponibles dans custom_tex.
#endif

void InitMachine_PCPort() {
  // PC Port added functions
  init_common_pc_port_functions(
      make_function_symbol_from_c,
      [](const char* name) {
        auto result = intern_from_c(name);  // non-const : Ptr<T>::operator-> ne l'est pas
        InternFromCInfo info{};
        info.offset = result.offset;
        // anim-interp-low-fps : `value` n'etait JAMAIS rempli — le champ existe dans
        // `InternFromCInfo` (game/kernel/common/kmachine.h) et les trois jeux rendaient un zero
        // silencieux. Tout code commun qui LIT un symbole GOAL par ce chemin recevait donc 0
        // sans que rien ne le signale : c'est ce qui faisait sortir le compteur de retimage
        // `*anim-interp-n*` a zero alors que le moteur en comptait 91 204 sur 5 903 images.
        info.value = result->value;
        return info;
      },
      make_string_from_c);

  // Game specific functions
  // Called from the game thread at each frame to tell the PC rendering code which levels to start
  // loading. The loader internally handles locking.
  make_function_symbol_from_c("__pc-set-levels", (void*)pc_set_levels);
  make_function_symbol_from_c("__pc-scene-ready?", (void*)pc_scene_ready);
  make_function_symbol_from_c("__pc-scene-release", (void*)pc_scene_release);
  make_function_symbol_from_c("__pc-npc-census-begin", (void*)pc_npc_census_begin);
  make_function_symbol_from_c("__pc-npc-census-actor", (void*)pc_npc_census_actor);
  make_function_symbol_from_c("__pc-npc-census-end", (void*)pc_npc_census_end);
  make_function_symbol_from_c("__pc-npc-census-live", (void*)pc_npc_census_live);
  make_function_symbol_from_c("__pc-npc-clone-fail", (void*)pc_npc_clone_fail);
  make_function_symbol_from_c("__pc-npcf-clone-hold?", (void*)pc_npcf_clone_hold);
  make_function_symbol_from_c("__pc-autoport-frame", (void*)pc_autoport_frame);
  // title-tap-prompt-regression : le fait tactile et le juge de l'invite du titre. HORS de tout
  // `#ifdef` : la famille `__pc-autoport-*` vit sous OG_FEAT_HD_MODELS, et un pont manquant n'est
  // pas un zero, c'est un SIGILL a l'appel depuis GOAL.
  make_function_symbol_from_c("__pc-touch-screen?", (void*)pc_touch_screen_present);
  make_function_symbol_from_c("__pc-title-prompt-drawn", (void*)pc_title_prompt_drawn);
  // recharged-gating-real : le grisage du menu et son recensement, meme table que la porte.
  make_function_symbol_from_c("__pc-gating-disabled?", (void*)pc_gating_disabled);
  make_function_symbol_from_c("__pc-gating-menu-begin", (void*)pc_gating_menu_begin);
  make_function_symbol_from_c("__pc-gating-menu-row", (void*)pc_gating_menu_row);
  make_function_symbol_from_c("__pc-gating-menu-end", (void*)pc_gating_menu_end);
  make_function_symbol_from_c("__pc-gating-wanted?", (void*)pc_gating_wanted);
  make_function_symbol_from_c("__pc-gating-page", (void*)pc_gating_page);
  make_function_symbol_from_c("__pc-gating-row-value", (void*)pc_gating_row_value);
  make_function_symbol_from_c("__pc-gating-mask-counts", (void*)pc_gating_mask_counts);
  make_function_symbol_from_c("__pc-gating-census-due?", (void*)pc_gating_census_due);
  make_function_symbol_from_c("__pc-wind-note-rate!", (void*)pc_wind_note_rate);
  make_function_symbol_from_c("__pc-npcf-fix-armed?", (void*)pc_npcf_fix_armed);
  make_function_symbol_from_c("__pc-npcf-note-cover", (void*)pc_npcf_note_cover);
  // Gloading-screen : instrument de cadence + tranches de travail GOAL
  make_function_symbol_from_c("__pc-loading-screen-tick", (void*)pc_loading_screen_tick);
  make_function_symbol_from_c("__pc-loading-screen-end", (void*)pc_loading_screen_end);
  make_function_symbol_from_c("__pc-slice-begin!", (void*)pc_goal_slice_begin);
  make_function_symbol_from_c("__pc-slice-expired?", (void*)pc_goal_slice_expired);
  // Gloading-screen-window : les quatre instants de la fenetre, sur horloge murale C++
  make_function_symbol_from_c("__pc-lswin-open", (void*)pc_lswin_open);
  make_function_symbol_from_c("__pc-lswin-level", (void*)pc_lswin_level);
  make_function_symbol_from_c("__pc-lswin-frame", (void*)pc_lswin_frame);
  make_function_symbol_from_c("__pc-lswin-actors", (void*)pc_lswin_actors);
  make_function_symbol_from_c("__pc-lswin-note", (void*)pc_lswin_note);
  make_function_symbol_from_c("__pc-lswin-close", (void*)pc_lswin_close);

  // Grecharged-grass-poc bridges (jak1 only)
  make_function_symbol_from_c("pc-set-recharged-grass!", (void*)pc_set_recharged_grass);
  // Grecharged-master-toggle: GLOBAL Recharged ON/OFF master (single effective-flag helper
  // Gfx::recharged_active composes it at every feature gate)
  make_function_symbol_from_c("pc-set-recharged-master!", (void*)pc_set_recharged_master);
  // Glighting-hdr: ECLAIRAGE RECHARGE master (root of the lighting overhaul; Gfx::lighting_active
  // composes it with the project master at every lighting gate)
  make_function_symbol_from_c("pc-set-recharged-lighting!", (void*)pc_set_recharged_lighting);
  // water-ocean-mesh : EAU RECHARGEE master (racine de la refonte eau ; Gfx::water_active le
  // compose avec le master projet a chaque porte d'eau)
  make_function_symbol_from_c("pc-set-recharged-water!", (void*)pc_set_recharged_water);
  // hdr-display-output : sortie HDR vers l'ecran (modes annonces, interrupteur, rapports)
  make_function_symbol_from_c("pc-get-hdr-output-modes", (void*)pc_get_hdr_output_modes);
  make_function_symbol_from_c("pc-set-hdr-output!", (void*)pc_set_hdr_output);
  make_function_symbol_from_c("pc-hdr-output-note!", (void*)pc_hdr_output_note);
  // hdr-output-regime : le transport et le regime, et le rapport de ce que le menu a formate
  make_function_symbol_from_c("pc-get-hdr-output-state", (void*)pc_get_hdr_output_state);
  make_function_symbol_from_c("pc-hdr-output-label-note!", (void*)pc_hdr_output_label_note);
  // External-asset-root: runtime custom texture replacements toggle
  make_function_symbol_from_c("pc-set-load-custom-assets!", (void*)pc_set_load_custom_assets);
  make_function_symbol_from_c("pc-set-recharged-textures!", (void*)pc_set_recharged_textures);
  make_function_symbol_from_c("pc-set-managed-assets!", (void*)pc_set_managed_assets);
#ifdef OG_FEAT_GRASS_OVERHANG
  // Grecharged-grass-overhang: 3D drooping edge-grass toggle
  make_function_symbol_from_c("pc-set-grass-overhang!", (void*)pc_set_grass_overhang);
#endif
#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: mood/TOD sun push. lighting-legacy-purge (2026-09-11) :
  // `pc-set-pbr!` et `pc-set-modern-materials!` sont SUPPRIMES — le PBR est inconditionnel
  // sous « lighting » et la pile moderne n'existe plus.
  make_function_symbol_from_c("pc-set-pbr-sun!", (void*)pc_set_pbr_sun);
  make_function_symbol_from_c("pc-set-pbr-sky-sun!", (void*)pc_set_pbr_sky_sun);
  make_function_symbol_from_c("pc-set-pbr-green-sun!", (void*)pc_set_pbr_green_sun);
  make_function_symbol_from_c("pc-set-pbr-lights!", (void*)pc_set_pbr_lights);
  // Grecharged-realtime-lighting: SUN-ONLY realtime lighting master
  make_function_symbol_from_c("pc-set-rt-light!", (void*)pc_set_rt_light);
  // lighting-legacy-purge (2026-09-11) : les ponts de l'ombre portee (res/dist/force), de
  // l'ambiante (interrupteur/force/modele/contraste), du RELIEF, de la SPECULAIRE, du
  // DISPLACEMENT et de PBR ISOLATE sont SUPPRIMES. Leurs valeurs livrees vivent dans
  // RechargedFixed (gfx.h).
#endif
  // Grecharged-foliage-wind: light-wind sway toggle (palms via TIE + shrubs)
  make_function_symbol_from_c("pc-set-foliage-wind!", (void*)pc_set_foliage_wind);
  // Grecharged-title-logo-fullres: CRISP TITLE LOGO toggle (native-res title/boot logo draw)
  make_function_symbol_from_c("pc-set-crisp-title-logo!", (void*)pc_set_crisp_title_logo);
  // lighting-legacy-purge (2026-09-11) : `pc-set-mesh-subdiv-rounds!` est SUPPRIME avec la
  // pre-subdivision, qui n'etait atteignable que sous le mode TESSELLATION jamais livre.
  // Grecharged-ambient-occlusion: AO algorithm (off/SSAO/HBAO/GTAO) + quality selector
  make_function_symbol_from_c("pc-set-ambient-occlusion!", (void*)pc_set_ambient_occlusion);
#ifdef OG_FEAT_HD_MODELS
  // Grecharged-hd-models: enhanced (jak2 HD) character-models toggle + availability query
  make_function_symbol_from_c("pc-set-recharged-enhanced-models!", (void*)pc_set_recharged_enhanced_models);
  make_function_symbol_from_c("pc-enhanced-models-available?", (void*)pc_get_enhanced_models_available);
  // Grecharged-hd-models4: per-actor coverage — companion pid -> driver pid registry in Merc2
  // Ghd-skin-origin-stretch : l'armement PAR ITEM et le compte de la porte
  make_function_symbol_from_c("__pc-autoport-armed-for", (void*)pc_autoport_armed_for);
  make_function_symbol_from_c("__pc-autoport-publish", (void*)pc_autoport_publish);
  make_function_symbol_from_c("__pc-autoport-disarmed-for", (void*)pc_autoport_disarmed_for);
  make_function_symbol_from_c("__pc-autoport-hit", (void*)pc_autoport_hit);
  // Grecharged-settings-case-l10n : le recensement du menu Recharged (casse + traduction)
  make_function_symbol_from_c("__pc-scl10n-begin", (void*)pc_scl10n_begin);
  make_function_symbol_from_c("__pc-scl10n-label", (void*)pc_scl10n_label);
  make_function_symbol_from_c("__pc-scl10n-uncovered", (void*)pc_scl10n_uncovered);
  make_function_symbol_from_c("__pc-scl10n-end", (void*)pc_scl10n_end);
  make_function_symbol_from_c("__pc-scl10n-wanted?", (void*)pc_scl10n_wanted);
  make_function_symbol_from_c("__pc-hd-proof", (void*)pc_hd_proof);
  make_function_symbol_from_c("pc-hd-cover!", (void*)pc_hd_cover);
  make_function_symbol_from_c("pc-hd-uncover!", (void*)pc_hd_uncover);
  // Ghd-skin-origin-stretch: rig du compagnon HD (parent, pilote, mode, bind par joint) ->
  // sondes HDSKINLEN / HDCMD. 8 arguments -> rampe a tableau (voir pc_hd_skel_joint).
  make_stack_arg_function_symbol_from_c("pc-hd-skel-joint!", (void*)pc_hd_skel_joint);
  // Ghd-skin-origin-stretch: l'anneau GOAL (ecrit par le squelette) + emplacement par compagnon
  // -> sonde HDRING (ce que GOAL a ecrit contre ce que le GPU consomme)
  make_function_symbol_from_c("pc-hd-ring!", (void*)pc_hd_ring);
  make_function_symbol_from_c("pc-hd-ring-slot!", (void*)pc_hd_ring_slot);
  // recharged-secondary-motion: le maillon que le solveur vient d'ecrire -> sonde d'etirement
  // de la chair au point de consommation GPU + la grandeur de la porte.
  make_function_symbol_from_c("pc-hd-phys-joint!", (void*)pc_hd_phys_joint);
#endif
#ifdef OG_FEAT_PHYSICS
  // Grecharged-secondary-motion: chain-physics toggle + the data-driven parameter queries.
  // Every value query returns MILLI-units (x1000) as an s64 — no floats cross this boundary.
  make_function_symbol_from_c("pc-set-physics!", (void*)pc_set_physics);
  make_function_symbol_from_c("pc-physics-reload", (void*)pc_physics_reload);
  make_function_symbol_from_c("pc-physics-generation", (void*)pc_physics_generation);
  make_function_symbol_from_c("pc-physics-joint-role", (void*)pc_physics_joint_role);
  make_function_symbol_from_c("pc-physics-chain-param-mi", (void*)pc_physics_chain_param_mi);
  make_function_symbol_from_c("pc-physics-chain-link-radius-mi",
                              (void*)pc_physics_chain_link_radius_mi);
  make_function_symbol_from_c("pc-physics-chain-link-comw-mi",
                              (void*)pc_physics_chain_link_comw_mi);
  make_function_symbol_from_c("pc-physics-chain-link-spr-mi",
                              (void*)pc_physics_chain_link_spr_mi);
  make_function_symbol_from_c("pc-physics-chain-link-apex-mi",
                              (void*)pc_physics_chain_link_apex_mi);
  make_function_symbol_from_c("pc-physics-chain-link-anp-mi",
                              (void*)pc_physics_chain_link_anp_mi);
  make_function_symbol_from_c("pc-physics-chain-rigid-mi",
                              (void*)pc_physics_chain_rigid_mi);
  make_function_symbol_from_c("pc-physics-chain-preset-mi",
                              (void*)pc_physics_chain_preset_mi);
  make_function_symbol_from_c("pc-physics-chain-preset-count",
                              (void*)pc_physics_chain_preset_count);
  make_function_symbol_from_c("pc-physics-chain-preset-absent",
                              (void*)pc_physics_chain_preset_absent);
  // (C14) mesh-surface audit inputs: per-link extremal skinned-vertex offsets
  make_function_symbol_from_c("pc-physics-chain-msample-count",
                              (void*)pc_physics_chain_msample_count);
  make_function_symbol_from_c("pc-physics-chain-msample-mi", (void*)pc_physics_chain_msample_mi);
  make_function_symbol_from_c("pc-physics-chain-xmask", (void*)pc_physics_chain_xmask);
  make_function_symbol_from_c("pc-physics-chain-flags", (void*)pc_physics_chain_flags);
  make_function_symbol_from_c("pc-physics-num-chains", (void*)pc_physics_num_chains);
  make_function_symbol_from_c("pc-physics-level-param-mi", (void*)pc_physics_level_param_mi);
  make_function_symbol_from_c("pc-physics-joint-collider-mi", (void*)pc_physics_joint_collider_mi);
  make_function_symbol_from_c("pc-physics-num-colliders", (void*)pc_physics_num_colliders);
  make_function_symbol_from_c("pc-physics-collider-param-mi", (void*)pc_physics_collider_param_mi);
  make_function_symbol_from_c("pc-physics-collider-is-joint", (void*)pc_physics_collider_is_joint);
  make_function_symbol_from_c("pc-physics-collider-is-joint2", (void*)pc_physics_collider_is_joint2);
  // (SPEC 18) body SURFACE sets — the real skinned surface the chains are tested against
  make_function_symbol_from_c("pc-physics-num-bsurf", (void*)pc_physics_num_bsurf);
  make_function_symbol_from_c("pc-physics-bsurf-is-joint", (void*)pc_physics_bsurf_is_joint);
  make_function_symbol_from_c("pc-physics-bsurf-count", (void*)pc_physics_bsurf_count);
  make_function_symbol_from_c("pc-physics-bsurf-mi", (void*)pc_physics_bsurf_mi);
  make_function_symbol_from_c("pc-physics-enabled", (void*)pc_physics_enabled);
#endif
  make_function_symbol_from_c("pc-set-jak-pos!", (void*)pc_set_jak_pos);
  // POLISH#4: adjustable grass view-distances + ledge-grab trample point
  make_function_symbol_from_c("pc-set-grass-dists!", (void*)pc_set_grass_dists);
  make_function_symbol_from_c("pc-get-tod-hour", (void*)pc_get_tod_hour);
  make_function_symbol_from_c("pc-refset-repin-parts?", (void*)pc_refset_repin_parts);
  make_function_symbol_from_c("pc-refset-part-step", (void*)pc_refset_part_step);
  make_function_symbol_from_c("pc-refset-mood-flame", (void*)pc_refset_mood_flame);
  make_function_symbol_from_c("pc-refset-text-mute?", (void*)pc_refset_text_mute);
  make_function_symbol_from_c("pc-refset-active?", (void*)pc_refset_active);
  make_function_symbol_from_c("pc-refset-note-level", (void*)pc_refset_note_level);
  make_function_symbol_from_c("pc-refset-camera", (void*)pc_refset_camera);
  make_function_symbol_from_c("pc-set-jak-ledge!", (void*)pc_set_jak_ledge);
  // ROUND#21d: exact ground-actor world positions for the grass object-clip/trample
  make_function_symbol_from_c("pc-grass-occ-clear!", (void*)pc_grass_occ_clear);
  make_function_symbol_from_c("pc-grass-occ-add!", (void*)pc_grass_occ_add);
  make_function_symbol_from_c("pc-grass-occ-add-moving!", (void*)pc_grass_occ_add_moving);
  make_function_symbol_from_c("pc-grass-occ-publish!", (void*)pc_grass_occ_publish);
  make_function_symbol_from_c("pc-grass-tramp-break!", (void*)pc_grass_tramp_break);

  make_function_symbol_from_c("pc-discord-rpc-update", (void*)update_discord_rpc);

  // setup string constants
  // TODO - these may be able to be moved into `init_common_pc_port_functions` but it's trickier
  // since they are accessing the Ptr's value
  auto user_dir_path = file_util::get_user_config_dir();
  intern_from_c("*pc-user-dir-base-path*")->value =
      make_string_from_c(user_dir_path.string().c_str());
  auto settings_path = file_util::get_user_settings_dir(g_game_version);
  intern_from_c("*pc-settings-folder*")->value = make_string_from_c(settings_path.string().c_str());
  // Gcutscene-npc-flicker-2 (cycle 3) : le recensement des PNJ ecrit AUSSI ses lignes dans le
  // dossier de reglages — sur Android c'est /storage/emulated/0/OpenGOAL/jak1/npc_flicker.txt,
  // le seul endroit du telephone de l'owner qu'il peut nous envoyer (son logcat est invisible).
  npc_flicker::set_log_path((settings_path / "npc_flicker.txt").string().c_str());
  intern_from_c("*pc-settings-built-sha*")->value = make_string_from_c(build_revision().c_str());
}

// ─── Ginput-replay-determinism (autoport): jak1 providers for the deterministic
//     record/replay harness ────────────────────────────────────────────────────
// The harness indexes records by the game-LOGIC frame (*display*
// actual-frame-counter) RELATIVE to a gameplay ANCHOR (*target* spawned), and
// forces every RNG stream to a fixed seed at the anchor. These reads use the same
// intern_from_c + g_ee_main_mem + s7 #f-guard pattern as the F1 warp / Merc2
// probes; field offsets are the deftype :offset-assert MINUS 4 (the GOAL basic
// type-tag adjustment) — e.g. *display* actual-frame-counter :offset-assert 816 ->
// C++ raw 812 (matches the A38-verified display on-screen 560 -> 556).

// Forward decls: the F1 warp (defined later in this TU) is the deterministic
// gameplay entry for the determinism proof / collision diff. When it is armed, the
// gameplay anchor defers until the warp has actually spawned Jak at Geyser (post
// title + post level-load), so the variable boot/title/load is fully absorbed and
// no title-phase input pollutes the recorded clip.
static bool f1_warp_requested();
static bool s_pad_replay_warp_gameplay = false;  // set true by f1_warp_run after spawn
// lighting-census : le pendant du precedent pour le warp de niveau GENERIQUE. Le menu-titre
// a lui aussi un *target* vivant : sans ce drapeau, toute ancre « Jak existe » se pose au
// titre et le chargement de niveau, de duree variable en frames de logique, entre dans la
// mesure.
static bool s_level_warp_gameplay = false;

// Deterministic game-logic frame = *display* actual-frame-counter (int64): +1 per
// UNPAUSED simulated frame, pacing-independent — NOT the render/read counter.
static int64_t pad_replay_logic_frame() {
  u32 disp = intern_from_c("*display*")->value;
  if (disp == 0 || disp == (u32)s7.offset || disp >= (u32)(EE_MAIN_MEM_SIZE - 820)) {
    return 0;
  }
  int64_t fc = 0;
  std::memcpy(&fc, g_ee_main_mem + disp + 812, 8);  // actual-frame-counter (816 - 4)
  return fc;
}

// Gameplay anchor = *target* (Jak) is a live process (non-#f, in EE memory). When
// the F1 warp is the gameplay entry, defer until the warp has spawned Jak at
// Geyser (post title + level-load): *target* is ALSO valid during the title
// (the title-state Jak), so anchoring on bare validity would latch at the title,
// leaving the variable level-load between the anchor and gameplay un-absorbed.
static bool pad_replay_anchor_reached() {
  u32 tgt = intern_from_c("*target*")->value;
  bool tgt_valid = (tgt != 0 && tgt != (u32)s7.offset && tgt < (u32)(EE_MAIN_MEM_SIZE - 4));
  if (!tgt_valid) {
    return false;
  }
  if (f1_warp_requested() && !s_pad_replay_warp_gameplay) {
    return false;
  }
  return true;
}

// Force the GOAL-side RNG to a fixed, known state at the anchor (record & replay):
//   *_vu-reg-R_*       — rand-vu's R register (a symbol holding an int); set to a
//                        valid [1.0,2.0) float bit pattern exactly as rand-vu-init.
//   *random-generator* — basic with a uint32 `seed` at obj+0 (:offset-assert 4 -4).
static void pad_replay_force_goal_rng(u32 seed) {
  intern_from_c("*_vu-reg-R_*")->value = (u32)(0x3F800000u | (seed & 0x007FFFFFu));
  u32 rg = intern_from_c("*random-generator*")->value;
  if (rg != 0 && rg != (u32)s7.offset && rg < (u32)(EE_MAIN_MEM_SIZE - 4)) {
    u32 derived = seed ^ 0x9E3779B9u;
    std::memcpy(g_ee_main_mem + rg, &derived, 4);  // seed @ obj+0 (4 - 4)
  }
}

// Force a FIXED game-logic timestep while the harness is armed. *ticks-per-frame*
// (the symbol's int value) only feeds the engine's time-ratio (drawable.gc:979,982)
// and the cosmetic perf bar. Setting it very high makes float-time-ratio
// (= timer-count / *ticks-per-frame*) ~0 < 1.3, so the PC-port clamp pins
// time-ratio to 1.0 EVERY frame: each drawn frame is exactly one 1/60s logic step,
// so the simulation no longer depends on the (variable) real frame duration. Set
// every frame so a mid-run video-mode reset (video.gc) cannot undo it. Default OFF
// — only ever called while the input-replay harness is recording/replaying.
// Gcamera-interp diagnostic: allow replaying recorded INPUT at the REAL device
// timestep (skip the forced constant timestep) so an injected pan plays out under
// the device's actual variable frame pacing (k dithers). This lets us capture the
// per-RENDER-frame camera yaw DURING an active injected pan and show it juders in
// lockstep with the integer time-ratio k (the owner's "jitter only while rotating").
// Enabled by env OG_PAD_REPLAY_REALTIME (x86) or android prop
// debug.opengoal.pad_replay_realtime=1. Default OFF => normal deterministic replay.
static bool pad_replay_realtime_requested() {
  static int cached = -1;
  if (cached < 0) {
    cached = 0;
    const char* e = getenv("OG_PAD_REPLAY_REALTIME");
    if (e && e[0] && e[0] != '0') {
      cached = 1;
    }
#ifdef __ANDROID__
    char pv[8] = {0};
    if (__system_property_get("debug.opengoal.pad_replay_realtime", pv) > 0 && pv[0] != '0') {
      cached = 1;
    }
#endif
  }
  return cached != 0;
}

static void pad_replay_force_timestep() {
  if (pad_replay_realtime_requested()) {
    // Gfixed-tick-interpolation : diagnostic a cadence REELLE — l'accumulateur lit la
    // montre, donc le rattrapage (plusieurs ticks de 1/60 s par image) s'exerce.
    fixed_tick::set_deterministic(false);
    return;  // real-timestep diagnostic: let the device's variable pacing drive the clock
  }
  // Gfixed-tick-interpolation : en rejeu deterministe, l'horloge a pas fixe rend
  // exactement 1 tick par image sans lire la montre — sinon la gigue reelle de la
  // machine entrerait dans une course qui doit etre reproductible. Le pas vaut alors
  // 1/60 s a TOUS les framerates cibles, ce qui isole la taille du pas comme seule
  // variable entre deux legs de mesure.
  fixed_tick::set_deterministic(true);
  intern_from_c("*ticks-per-frame*")->value = 0x40000000;
  // lighting-hdr essai 4 : LE SEUL POINT DU MOTEUR QUI TOURNE EXACTEMENT UNE FOIS PAR IMAGE
  // SIMULEE, sur le fil GOAL, et deja filtre sur la manette 0 (`pad_replay::on_cpad_read`).
  // C'est lui qui cadence desormais le plan du jeu de references — voir `refset_pump`.
  refset_pump(true);
}

// Gfixed-tick-interpolation : publication de l'horloge vers GOAL. Trois symboles
// suffisent, et AUCUN nouveau symbole-FONCTION n'est cree — c'est deliberé. Sur
// Android la table des symboles est batie par un chemin separe
// (android/android_runtime_compat.cpp n'enregistre AUCUN des pc-*), et un symbole
// fonction oublie la-bas ne se manifeste pas par une erreur de lien : GOAL saute a 0
// et le processus meurt en SIGILL. Une VALEUR de symbole non ecrite, elle, laisse
// simplement `*fixed-tick-armed*` a 0, c'est-a-dire le comportement d'avant.
// Gfixed-tick-interpolation : l'interrupteur du JOUEUR (Recharged Settings), pousse a
// chaque image depuis GOAL par `pc-set-fixed-tick!`, sur le meme patron que
// `pc-set-physics!` et le basculement HD-MODELS. Pousser a chaque image plutot qu'au
// changement rend le reglage robuste a un chargement de sauvegarde ou a une remise a
// zero des reglages : l'etat du moteur ne peut pas diverger de la case cochee.
//
// L'appel est enregistre SANS `#ifdef` : un symbole-fonction que le CGO appelle et que
// le .so ne fournit pas fait sauter GOAL a l'adresse 0 et tue le processus en SIGILL —
// c'est le mode de defaillance « FEATURE-STALE libgk » que deploy_verify traque. Ce
// binding n'a donc pas de drapeau de build, et le cout d'un booleen est nul.
void pc_set_fixed_tick(u32 on) {
  fixed_tick::set_enabled(on != 0);
}

static void fixed_tick_publish(int armed, int catchup, s32 alpha_micro, int skip) {
  intern_from_c("*fixed-tick-armed*")->value = (u32)armed;
  intern_from_c("*fixed-tick-catchup*")->value = (u32)catchup;
  intern_from_c("*fixed-tick-alpha*")->value = (u32)alpha_micro;
  // Gfixed-tick-anim-interp : trois VALEURS de symbole de plus, et toujours aucun
  // symbole-FONCTION (une fonction oubliee cote Android fait sauter GOAL a l'adresse 0
  // et tue le processus en SIGILL ; une valeur non ecrite laisse simplement le moteur
  // sur son chemin d'origine).
  //   `*fixed-tick-skip*`   1 quand cette image DESSINEE ne porte aucun tick de logique.
  //   `*anim-interp-on*`    interrupteur d'ablation de l'interpolation de pose.
  //   `*anim-interp-probe*` sonde par image dessinee, opt-in au PRODUCTEUR.
  intern_from_c("*fixed-tick-skip*")->value = (u32)skip;
  intern_from_c("*anim-interp-on*")->value = fixed_tick::anim_interp_enabled() ? 1 : 0;
  intern_from_c("*anim-interp-probe*")->value = fixed_tick::anim_probe_enabled() ? 1 : 0;
  // Grecharged-foliage-wind3 : `*wind-native-rate*` — 1 = la brise de ND avance a 60 Hz quelle
  // que soit la cadence d'affichage, 0 = chemin « high fps » d'avant cette phase. Valeur de
  // symbole, pas symbole-fonction (cf. le commentaire ci-dessus).
  intern_from_c("*wind-native-rate*")->value = fixed_tick::wind_native_rate_enabled() ? 1 : 0;
  // anim-interp-low-fps : `*render-pace-skip*` — 1 quand l'image DESSINEE qu'on vient de
  // preparer ne porte aucun tick de logique (l'affichage va plus vite que la cadence cible).
  // `display-frame-start` y met `time-ratio` a 0. Valeur de symbole, pas symbole-fonction, pour
  // la meme raison que les six lignes du dessus.
  intern_from_c("*render-pace-skip*")->value = render_pace::skip() ? 1 : 0;

  // SONDE DE CADENCE, une ligne par image DESSINEE (env OG_FIXED_TICK_PROBE=1, sinon
  // muette). Elle est posee ICI et pas ailleurs parce que ce point est atteint APRES
  // que `cam-render-interp!` a retime *math-camera* et APRES que la chaine DMA a ete
  // construite : le lacet publie est donc celui que le RENDU a reellement consomme,
  // pas un etat interne du processus camera. C'est la grandeur dont le judder est la
  // derivee seconde (game/kernel/jak1/kmachine.cpp, note « the gameplay camera
  // juders while the world/Jak stay smooth »).
  //
  // Publie aussi la position de Jak : le meme fichier porte alors la trajectoire de
  // saut ET la cadence, donc on ne peut pas les apparier de travers.
  // Gate lue par le module lui-meme : env sur bureau, propriete Android sur telephone
  // (l'environnement d'un processus Android n'est pas reglable depuis adb, et une sonde
  // qu'on ne peut pas armer sur l'appareil ne prouve rien de l'appareil).
  if (!fixed_tick::probe_enabled()) {
    return;
  }
  static Timer s_probe_timer;
  static bool s_probe_have = false;
  static u64 s_probe_n = 0;
  double dt_ms = 0.0;
  if (s_probe_have) {
    dt_ms = s_probe_timer.getSeconds() * 1000.0;
  }
  s_probe_timer.start();
  s_probe_have = true;

  float cx = 0.f, cy = 0.f, cz = 0.f, yaw = 0.f;
  float jx = 0.f, jy = 0.f, jz = 0.f;
  const u32 mc = intern_from_c("*math-camera*")->value;
  if (mc != 0 && mc != (u32)s7.offset && mc < (u32)(EE_MAIN_MEM_SIZE - 0x424)) {
    const float* trans = (const float*)(g_ee_main_mem + mc + 844);
    const float* fwd = (const float*)(g_ee_main_mem + mc + 364 + 32);  // camera-rot ligne 2
    cx = trans[0];
    cy = trans[1];
    cz = trans[2];
    yaw = (float)(atan2((double)fwd[0], (double)fwd[2]) * 57.29577951308232);
  }
  const u32 tgt = intern_from_c("*target*")->value;
  if (tgt != 0 && tgt != (u32)s7.offset && tgt < (u32)(EE_MAIN_MEM_SIZE - 4)) {
    u32 ctrl = 0;
    std::memcpy(&ctrl, g_ee_main_mem + tgt + 108, 4);
    if (ctrl != 0 && ctrl != (u32)s7.offset && ctrl < (u32)(EE_MAIN_MEM_SIZE - 24)) {
      const float* jt = (const float*)(g_ee_main_mem + ctrl + 12);
      jx = jt[0];
      jy = jt[1];
      jz = jt[2];
    }
  }
  const s64 lf = pad_replay_logic_frame();
  // Gfixed-tick-anim-interp-2 — L'ETAT DU VERROU DE CADENCE EST PUBLIE SUR LA MEME
  // LIGNE QUE LA MESURE. Sans lui, « pas d'amelioration a 30 images/s » et « la
  // condition ne se represente pas parce que la cadence est verrouillee » rendent le
  // meme chiffre : c'est exactement l'erreur du cycle 1, qui a publie un rapport de
  // 0,846 comme un resultat alors que l'horloge etait verrouillee des deux cotes.
  //   lock  1 = cadence verrouillee sur un multiple entier de ticks (alpha force a 1,0)
  //   dev   |dt/tick - entier le plus proche| de CETTE image, en ticks
  //   cl    cumul des images dont la duree a ete ecretee au plafond de rattrapage
  //   cc    cumul des images ou le plafond a JETE du temps de jeu
  fprintf(stderr,
          "GFT n=%llu lf=%lld armed=%d skip=%d k=%d alpha=%d dt_ms=%.3f yaw=%.5f "
          "cam=%.3f,%.3f,%.3f jak=%.3f,%.3f,%.3f lock=%d dev=%.4f cl=%llu cc=%llu ticklock=%d\n",
          (unsigned long long)s_probe_n++, (long long)lf, armed, skip,
          skip ? 0 : (catchup + 1), alpha_micro, dt_ms, yaw, cx, cy, cz, jx, jy, jz,
          fixed_tick::lock_state(), fixed_tick::last_dev_ticks(),
          (unsigned long long)fixed_tick::ceiling_clamps(),
          (unsigned long long)fixed_tick::catchup_clamps(),
          fixed_tick::tick_lock_enabled() ? 1 : 0);
}

// Gcamera-interp (autoport, owner 2026-07-01): per-logic-frame CAMERA-MATRIX dump
// for the x86-vs-arm64 numerical-divergence localizer. Owner evidence: at a STABLE
// framerate the gameplay camera juders while the world/Jak stay smooth — a suspected
// arm64-specific per-frame numerical divergence in the camera pose. Under the replay
// harness the timestep is forced to 1.0 (one 1/60s logic step per drawn frame), so
// ALL frame-pacing variance is removed and any x86-vs-device delta in this dump is a
// PURE numerical divergence. Dumps *math-camera*'s render pose (trans + camera-rot,
// the exact view matrix the renderer consumes) AND *target*'s control trans as the
// SMOOTH-object reference, so a camera-only divergence is visible in one trace.
// Layout (little-endian floats, backend-agnostic, byte-comparable across x86/arm64):
//   [ 0..15] *math-camera* trans      (4 floats @ mc+844,  deftype offset 848)
//   [16..79] *math-camera* camera-rot (4x4 matrix @ mc+364, deftype offset 368)
//   [80..91] *target* control trans   (3 floats @ ctrl+12), zero if no live target
static void replay_camera_checkpoint(void (*sink)(const char*, const void*, size_t)) {
  u8 buf[92];
  std::memset(buf, 0, sizeof(buf));
  u32 mc = intern_from_c("*math-camera*")->value;
  if (mc != 0 && mc != (u32)s7.offset && mc < (u32)(EE_MAIN_MEM_SIZE - 0x424)) {
    std::memcpy(buf + 0, g_ee_main_mem + mc + 844, 16);   // trans (position)
    std::memcpy(buf + 16, g_ee_main_mem + mc + 364, 64);  // camera-rot (view rotation)
  }
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt != 0 && tgt != (u32)s7.offset && tgt < (u32)(EE_MAIN_MEM_SIZE - 4)) {
    u32 ctrl = 0;
    std::memcpy(&ctrl, g_ee_main_mem + tgt + 108, 4);  // control (offset 108)
    if (ctrl != 0 && ctrl != (u32)s7.offset && ctrl < (u32)(EE_MAIN_MEM_SIZE - 24)) {
      std::memcpy(buf + 80, g_ee_main_mem + ctrl + 12, 12);  // Jak trans (control offset 12)
    }
  }
  sink("CAM", buf, sizeof(buf));
}

static void pad_replay_dump_camera() {
  replay_camera_checkpoint(pad_replay::dump_state);
}


/*!
 * Final initialization of the system after the kernel is loaded.
 * This is called from InitHeapAndSymbol at the very end.
 * Exports the last of the functions written in C to the GOAL symbol table
 * If DiskBooting, will load the GAME CGO, containing the engine, and calls "play", the function
 * which should prepare the game engine.
 */
static bool s_boot_replay_first_dispatch = false;
static bool s_boot_replay_listener_ran = false;
static bool s_boot_replay_actors_sweep = false;
static u32 s_boot_replay_dispatches = 0;
static u32 s_boot_replay_spawn_dispatch = 0;
static u32 s_boot_replay_target_pid = 0;
static bool s_boot_replay_spawn_disabled = false;
static s64 s_boot_replay_spawn_frame = -1;
static u64 boot_replay_start_run();
Ptr<Function> make_function_from_c(void* func, bool arg3_is_pp);

static void boot_replay_object_checkpoint(
    const char* name, u32 offset, size_t size,
    void (*sink)(const char*, const void*, size_t) = boot_replay::checkpoint) {
  const u32 object = intern_from_c(name)->value;
  if (!object || object == s7.offset || object >= EE_MAIN_MEM_SIZE ||
      offset + size > EE_MAIN_MEM_SIZE - object) {
    std::fprintf(stderr, "BOOTREPLAY missing checkpoint object=%s\n", name);
    std::exit(EXIT_FAILURE);
  }
  sink(name, g_ee_main_mem + object + offset, size);
}

// These readers only inspect GOAL memory on the host stack after dispatch.
// No native/GOAL pointers or user-object unions enter the portable checkpoint.
static void boot_replay_range(u32 address, size_t size) {
  if (!address || address == s7.offset || address >= EE_MAIN_MEM_SIZE ||
      size > EE_MAIN_MEM_SIZE - address) {
    std::fprintf(stderr, "BOOTREPLAY invalid state address=%08x size=%zu\n", address, size);
    std::exit(EXIT_FAILURE);
  }
}

template <typename T>
static T boot_replay_read(u32 address) {
  boot_replay_range(address, sizeof(T));
  T value;
  std::memcpy(&value, g_ee_main_mem + address, sizeof(T));
  return value;
}

static void boot_replay_symbol_checkpoint(
    const char* tag, u32 symbol,
    void (*sink)(const char*, const void*, size_t) = boot_replay::checkpoint) {
  if (!symbol) {
    sink(tag, "<null>", 6);
    return;
  }
  if (symbol == s7.offset) {
    sink(tag, "#f", 2);
    return;
  }
  // Symbol metadata stores a GOAL string pointer, not the string inline.
  boot_replay_range(symbol, 4);
  const u32 string = boot_replay_read<u32>(symbol + jak1::SYM_INFO_OFFSET + 4);
  const u32 length = boot_replay_read<u32>(string);
  if (length > 255) {
    std::fprintf(stderr, "BOOTREPLAY overlong symbol tag=%s length=%u\n", tag, length);
    std::exit(EXIT_FAILURE);
  }
  boot_replay_range(string, 4 + length + 1);
  sink(tag, g_ee_main_mem + string + 4, length);
}

static void boot_replay_process_checkpoint(
    u32 process,
    void (*sink)(const char*, const void*, size_t) = boot_replay::checkpoint) {
  const u8 present = process && process != s7.offset;
  sink("actor-present", &present, sizeof(present));
  if (!present) {
    return;
  }
  boot_replay_range(process, 76);
  const u32 type = boot_replay_read<u32>(process - 4);
  boot_replay_symbol_checkpoint("actor-type", boot_replay_read<u32>(type), sink);
  sink("actor-pid", g_ee_main_mem + process + 36, 4);
  boot_replay_symbol_checkpoint("actor-status", boot_replay_read<u32>(process + 32), sink);
  for (u32 offset : {52u, 72u}) {
    const u32 state = boot_replay_read<u32>(process + offset);
    boot_replay_symbol_checkpoint(offset == 52 ? "actor-state" : "actor-next-state",
                                 !state || state == s7.offset ? state : boot_replay_read<u32>(state),
                                 sink);
  }
}

static void boot_replay_array_checkpoint(
    u32 array, bool links,
    void (*sink)(const char*, const void*, size_t) = boot_replay::checkpoint) {
  const s32 length = boot_replay_read<s32>(array);
  const s32 allocated = boot_replay_read<s32>(array + 4);
  const u32 stride = links ? 64 : 16;
  if (length < 0 || allocated < length || u64(allocated) * stride > EE_MAIN_MEM_SIZE) {
    std::fprintf(stderr, "BOOTREPLAY invalid actor array length=%d allocated=%d\n", length,
                 allocated);
    std::exit(EXIT_FAILURE);
  }
  boot_replay_range(array, 12 + size_t(allocated) * stride);
  sink(links ? "entity-count" : "perm-count", &length, sizeof(length));
  for (s32 i = 0; i < length; ++i) {
    const u32 entry = array + 12 + i * stride;
    const u32 perm = entry + (links ? 48 : 0);
    sink("perm-status", g_ee_main_mem + perm + 8, 2);
    sink("perm-task", g_ee_main_mem + perm + 11, 1);
    sink("perm-aid", g_ee_main_mem + perm + 12, 4);
    if (links) {
      sink("entity-trans", g_ee_main_mem + entry + 32, 16);
      boot_replay_process_checkpoint(boot_replay_read<u32>(entry + 12), sink);
    }
  }
}

static void boot_replay_actors_checkpoint(
    void (*sink)(const char*, const void*, size_t) = boot_replay::checkpoint) {
  const u32 gi = intern_from_c("*game-info*")->value;
  boot_replay_symbol_checkpoint("game-mode", boot_replay_read<u32>(gi), sink);
  boot_replay_array_checkpoint(boot_replay_read<u32>(gi + 96), false, sink);
  boot_replay_array_checkpoint(boot_replay_read<u32>(gi + 100), false, sink);
  const u32 group = intern_from_c("*level*")->value;
  const s32 count = boot_replay_read<s32>(group);
  if (count < 1 || count > 3) {
    std::fprintf(stderr, "BOOTREPLAY invalid level count=%d\n", count);
    std::exit(EXIT_FAILURE);
  }
  boot_replay_range(group, 96 + size_t(count) * 2608);
  sink("level-count", &count, sizeof(count));
  for (s32 i = 0; i < count; ++i) {
    const u32 level = group + 96 + i * 2608;
    boot_replay_symbol_checkpoint("level-name", boot_replay_read<u32>(level), sink);
    boot_replay_symbol_checkpoint("level-status", boot_replay_read<u32>(level + 16), sink);
    const u32 entities = boot_replay_read<u32>(level + 280);
    const u8 present = entities && entities != s7.offset;
    sink("level-entities", &present, sizeof(present));
    if (present) {
      boot_replay_array_checkpoint(entities, true, sink);
    }
  }
  boot_replay_process_checkpoint(intern_from_c("*target*")->value, sink);
}

static void boot_replay_state_checkpoint(
    void (*sink)(const char*, const void*, size_t) = boot_replay::checkpoint) {
  // Compare scalar state produced by GAME, never restore pointers between binaries.
  // In particular knuth-rand is seeded by DecodeTime during linking, before play.
  const u32 vu_r = intern_from_c("*_vu-reg-R_*")->value;
  sink("goal-vu-R", &vu_r, sizeof(vu_r));
  boot_replay_object_checkpoint("*knuth-rand-state*", 0, 8, sink);  // structure: int64 seed
  boot_replay_object_checkpoint("*random-generator*", 0, 4, sink);  // basic: uint32 seed
  // display-h.gc / all-types.gc: 16 time-frame fields at 776, then 5 floats at 904.
  // Basic pointers start after their four-byte type tag. This range has no pointers.
  boot_replay_object_checkpoint("*display*", 776 - 4, 16 * 8 + 5 * 4, sink);
  boot_replay_native_rng(false, sink);
}

static void boot_replay_seal(const char* boundary) {
  boot_replay::finish();
  refset_state::bootstrap(boot_replay::fingerprint(), boot_replay::replay_verified(), boundary);
  refset::set_bootstrap_fingerprint(boot_replay::fingerprint());
  autoport_proof::publish("refset_bootstrap_records", boot_replay::records());
  char fp[17];
  std::snprintf(fp, sizeof(fp), "%016llx", (unsigned long long)boot_replay::fingerprint());
  autoport_proof::publish_text("refset_bootstrap_fingerprint", fp);
  autoport_proof::publish_text("refset_bootstrap_boundary", boundary);
}

static void boot_replay_pre_play() {
  if (!boot_replay::active()) {
    return;
  }
  const char* boundary = std::getenv("OG_BOOT_REPLAY_BOUNDARY");
  if (boundary && std::strcmp(boundary, "before-play") &&
      std::strcmp(boundary, "first-dispatch") && std::strcmp(boundary, "actors-sweep")) {
    std::fprintf(stderr, "BOOTREPLAY invalid OG_BOOT_REPLAY_BOUNDARY\n");
    std::exit(EXIT_FAILURE);
  }
  s_boot_replay_actors_sweep = boundary && !std::strcmp(boundary, "actors-sweep");
  s_boot_replay_first_dispatch = s_boot_replay_actors_sweep ||
                                 (boundary && !std::strcmp(boundary, "first-dispatch"));
  boot_replay_state_checkpoint();
  if (s_boot_replay_first_dispatch) {
    // The extended stream cannot be confused with a historical pre-play stream.
    // Keep collecting the real RTC/EE/unix inputs through play and the dispatcher.
    boot_replay::checkpoint("boundary", boundary, std::strlen(boundary));
  } else {
    boot_replay_seal("before-play-actors-not-restored");
  }
}

// Independent of the sealed bootstrap stream: observe live state on the host stack.
// Never append checkpoints here, including after the before-play boundary.
static std::string refset_loaded_symbol(u32 symbol) {
  if (!symbol) return "<null>";
  if (symbol == s7.offset) return "#f";
  boot_replay_range(symbol, 4);
  const u32 string = boot_replay_read<u32>(symbol + jak1::SYM_INFO_OFFSET + 4);
  const u32 length = boot_replay_read<u32>(string);
  if (length > 255) {
    std::fprintf(stderr, "REFSET loaded-state invalid symbol length=%u\n", length);
    std::exit(EXIT_FAILURE);
  }
  boot_replay_range(string, 4 + length + 1);
  return std::string(reinterpret_cast<const char*>(g_ee_main_mem + string + 4), length);
}

static void refset_load_restore_after_dispatch();

static void postload_pc_settings_trace(void (*sink)(const char*, const void*, size_t)) {
  // Offsets from the pc-settings deftype in goal_src/jak1/pc/pckernel-h.gc,
  // relative to the basic pointer (type-tag adjustment already applied).
  // These observations require the matching ISO layout on both compared runs.
  const u32 settings = intern_from_c("*pc-settings*")->value;
  if (!settings || settings == s7.offset) {
    std::fprintf(stderr, "REFSET missing postload object=*pc-settings*\n");
    std::exit(EXIT_FAILURE);
  }
  boot_replay_range(settings, 348);
  const auto scalar = [sink](const char* tag, auto value) {
    sink(tag, &value, sizeof(value));
  };
  boot_replay_symbol_checkpoint("pc-settings-aspect-ratio-auto?",
                                boot_replay_read<u32>(settings + 92), sink);
  scalar("pc-settings-aspect-ratio", boot_replay_read<float>(settings + 96));
  scalar("pc-settings-aspect-ratio-scale", boot_replay_read<float>(settings + 100));
  scalar("pc-settings-aspect-ratio-reciprocal", boot_replay_read<float>(settings + 104));
  scalar("pc-settings-aspect-custom-x", boot_replay_read<int64_t>(settings + 108));
  scalar("pc-settings-aspect-custom-y", boot_replay_read<int64_t>(settings + 116));
  boot_replay_symbol_checkpoint("pc-settings-letterbox?", boot_replay_read<u32>(settings + 124),
                                sink);
  scalar("pc-settings-lod-dist-mod", boot_replay_read<float>(settings + 332));
  // offset 338 (et non 339) : lod-force-ocean a ete retire du type pc-settings (item water-census)
  scalar("pc-settings-lod-force-actor", boot_replay_read<int8_t>(settings + 338));
  boot_replay_symbol_checkpoint("pc-settings-ps2-actor-vis?", boot_replay_read<u32>(settings + 340),
                                sink);
  boot_replay_symbol_checkpoint("pc-settings-use-vis?", boot_replay_read<u32>(settings + 344),
                                sink);
}

static void refset_loaded_after_dispatch() {
  // Do not intern symbols or initialize refset during the recorded bootstrap.
  // fingerprint() is passive and remains zero until the stream has been sealed.
  if (!refset::requires_loaded_state() || !boot_replay::fingerprint()) return;
  std::vector<refset::LoadedLevelState> levels;
  const u32 group = intern_from_c("*level*")->value;
  if (group && group != s7.offset) {
    const s32 count = boot_replay_read<s32>(group);
    if (count < 0 || count > 3) {
      std::fprintf(stderr, "REFSET loaded-state invalid level count=%d\n", count);
      std::exit(EXIT_FAILURE);
    }
    boot_replay_range(group, 96 + size_t(count) * 2608);
    for (s32 i = 0; i < count; ++i) {
      const u32 level = group + 96 + i * 2608;
      levels.push_back({refset_loaded_symbol(boot_replay_read<u32>(level)),
                        refset_loaded_symbol(boot_replay_read<u32>(level + 16))});
    }
  }
  const u32 target = intern_from_c("*target*")->value;
  const bool present = target && target != s7.offset;
  if (present) boot_replay_range(target, 4);
  const u32 goal_true = intern_from_c("#t").offset;
  const int64_t frame = refset::current_logic_frame();
  refset::note_loaded_state(frame, present,
                           intern_from_c("*spawn-actors*")->value == goal_true,
                           intern_from_c("*actors-sweep-complete*")->value == goal_true, levels);
  static int64_t last_observed_frame = -1;
  const bool qualify_state = refset_state::enabled();
  if ((pad_replay::trace_active() || qualify_state) && refset::wants_postload_trace(frame) &&
      frame != last_observed_frame) {
    // One traversal supplies both observers, after the bootstrap was sealed.
    // Without qualification the existing pad trace retains its exact record layout.
    const auto sink = +[](const char* tag, const void* data, size_t size) {
      refset_state::record(tag, data, size);
      if (pad_replay::trace_active()) pad_replay::dump_state(tag, data, size);
    };
    if (qualify_state) refset_state::begin(frame);
    sink("POSTLOAD-BEGIN", &frame, sizeof(frame));
    boot_replay_state_checkpoint(sink);
    boot_replay_object_checkpoint("*kernel-context*", 16 - 4, 4, sink);
    boot_replay_actors_checkpoint(sink);
    postload_pc_settings_trace(sink);
    if (qualify_state) replay_camera_checkpoint(sink);
    sink("POSTLOAD-END", &frame, sizeof(frame));
    if (qualify_state) refset_state::end();
    last_observed_frame = frame;
  }
  refset_load_restore_after_dispatch();
}

void boot_replay_after_dispatch() {
  refset_loaded_after_dispatch();
  if (!s_boot_replay_first_dispatch || !boot_replay::active()) {
    return;
  }
  if (!s_boot_replay_listener_ran) {
    std::fprintf(stderr, "BOOTREPLAY first listener was displaced\n");
    std::exit(EXIT_FAILURE);
  }
  if (s_boot_replay_actors_sweep) {
    ++s_boot_replay_dispatches;
    const u32 target = intern_from_c("*target*")->value;
    const bool present = target && target != s7.offset;
    const u32 pid = present ? boot_replay_read<u32>(target + 36) : 0;
    const bool spawn = intern_from_c("*spawn-actors*")->value == intern_from_c("#t").offset;
    const bool sweep = intern_from_c("*actors-sweep-complete*")->value == intern_from_c("#t").offset;
    bool active_level = false;
    if (present) {
      const u32 level = boot_replay_read<u32>(target + 472);
      active_level = level && level != s7.offset &&
                     boot_replay_read<u32>(level + 16) == intern_from_c("active").offset;
    }
    s_boot_replay_spawn_disabled |= !spawn;
    if (!spawn || !present || pid != s_boot_replay_target_pid) {
      s_boot_replay_spawn_dispatch = 0;
    }
    s_boot_replay_target_pid = pid;
    if (spawn && present && !s_boot_replay_spawn_dispatch) {
      s_boot_replay_spawn_dispatch = s_boot_replay_dispatches;
      s_boot_replay_spawn_frame = pad_replay_logic_frame();
    }
    const u32 progress[] = {s_boot_replay_dispatches, pid, u32(spawn), u32(sweep),
                            u32(active_level)};
    // Observe readiness; never replay it as an input or wait for a recorded success.
    boot_replay::checkpoint("actors-progress", progress, sizeof(progress));
    if (!s_boot_replay_spawn_disabled || !s_boot_replay_spawn_dispatch ||
        s_boot_replay_dispatches <= s_boot_replay_spawn_dispatch ||
        pad_replay_logic_frame() <= s_boot_replay_spawn_frame || !sweep || !active_level) {
      if (s_boot_replay_dispatches >= 600) {
        std::fprintf(stderr, "BOOTREPLAY actors-sweep not reached after 600 dispatches\n");
        std::exit(EXIT_FAILURE);
      }
      return;
    }
    boot_replay_state_checkpoint();
    boot_replay_object_checkpoint("*kernel-context*", 16 - 4, 4);
    boot_replay_actors_checkpoint();
    boot_replay::checkpoint("after-actors-sweep", nullptr, 0);
    std::fprintf(stderr, "BOOTREPLAY actors-sweep dispatch=%u target-pid=%u\n",
                 s_boot_replay_dispatches, pid);
    boot_replay_seal("actors-sweep-identities-compared");
    return;
  }
  // Host stack, after the first tree traversal. This verifies scalar state but
  // does not restore or certify actors: restart can still be suspended before start.
  boot_replay::checkpoint("after-first-dispatch", nullptr, 0);
  boot_replay_state_checkpoint();
  boot_replay_object_checkpoint("*kernel-context*", 16 - 4, 4);  // next-pid
  boot_replay_seal("first-dispatch-actors-not-restored");
}

// perf-instruments : les deux attentes du process display, chronometrees AUTOUR de l'appel
// reel, sur les deux plateformes (ce fichier est compile dans libgk.so aussi). `frame_boundary`
// a l'ENTREE de syncv : c'est la frontiere d'image du fil GOAL.
static u32 perf_syncv(u32 mode) {
  perf_instruments::frame_boundary();
  Timer t;
  const u32 r = sceGsSyncV(mode);
  perf_instruments::note_vsync_wait_ns((uint64_t)t.getNs());
  return r;
}
static u32 perf_sync_path(u32 mode, u32 timeout) {
  Timer t;
  const u32 r = sceGsSyncPath(mode, timeout);
  perf_instruments::note_syncpath_wait_ns((uint64_t)t.getNs());
  return r;
}

void InitMachineScheme() {
  boot_replay_native_rng(true);
  make_function_symbol_from_c("put-display-env", (void*)PutDisplayEnv);       // used in drawable
  make_function_symbol_from_c("syncv", (void*)perf_syncv);                    // used in drawable
  make_function_symbol_from_c("sync-path", (void*)perf_sync_path);            // used
  make_function_symbol_from_c("reset-path", (void*)sceGsResetPath);           // used in dma
  make_function_symbol_from_c("reset-graph", (void*)sceGsResetGraph);         // used
  make_function_symbol_from_c("dma-sync", (void*)sceDmaSync);                 // used
  make_function_symbol_from_c("gs-put-imr", (void*)sceGsPutIMR);              // unused
  make_function_symbol_from_c("gs-get-imr", (void*)sceGsGetIMR);              // unused
  make_function_symbol_from_c("gs-store-image", (void*)sceGsExecStoreImage);  // used
  make_function_symbol_from_c("flush-cache", (void*)FlushCache);              // used
  make_function_symbol_from_c("cpad-open", (void*)CPadOpen);                  // used
  make_function_symbol_from_c("cpad-get-data", (void*)CPadGetData);           // used
  // Ginput-replay-determinism (autoport): wire the deterministic record/replay
  // harness to jak1 game state — index by the game-logic frame (*display*
  // actual-frame-counter), anchor on *target* spawn, and force the GOAL RNG
  // (*_vu-reg-R_*, *random-generator*) at the anchor. Backend-agnostic: this runs
  // on x86 and on the arm64 device. No-op unless the harness is armed.
  pad_replay::set_logic_frame_provider(&pad_replay_logic_frame);
  // lighting-census : la MEME horloge pour le jeu d'images de reference — *display*
  // actual-frame-counter, +1 par image de logique simulee.
  refset::set_logic_frame_provider(&pad_replay_logic_frame);
  pad_replay::set_anchor_provider(&pad_replay_anchor_reached);
  pad_replay::add_rng_reseed_callback(&pad_replay_force_goal_rng);
  pad_replay::set_timestep_force_callback(&pad_replay_force_timestep);
  // Gcamera-interp (autoport): dump *math-camera* pose per logic frame so a state
  // trace localizes any x86-vs-arm64 camera numerical divergence (no-op unless a
  // trace file is open via OG_PAD_REPLAY_TRACE / debug.opengoal.pad_trace).
  pad_replay::set_state_dump_callback(&pad_replay_dump_camera);
  // Gfixed-tick-interpolation (autoport, owner 2026-08-26) : brancher l'horloge a pas
  // fixe sur la table des symboles jak1. InitMachineScheme est atteint sur les DEUX
  // plateformes (bureau via kboot, Android via android_runtime_full.cpp
  // InitHeapAndSymbol -> InitMachineScheme), donc ce rappel est le meme des deux cotes.
  fixed_tick::set_publisher(&fixed_tick_publish);
  // Gfixed-tick-interpolation : interrupteur du joueur. Enregistre ICI (InitMachineScheme
  // de jak1), le seul chemin d'enregistrement des pc-* qui soit atteint sur les DEUX
  // plateformes — `init_common_pc_port_functions` ne tourne pas sur Android.
  make_function_symbol_from_c("pc-set-fixed-tick!", (void*)pc_set_fixed_tick);
  make_function_symbol_from_c("install-handler", (void*)InstallHandler);      // used
  make_function_symbol_from_c("install-debug-handler", (void*)InstallDebugHandler);       // used
  make_function_symbol_from_c("file-stream-open", (void*)kopen);                          // used
  make_function_symbol_from_c("file-stream-close", (void*)kclose);                        // used
  make_function_symbol_from_c("file-stream-length", (void*)klength);                      // used
  make_function_symbol_from_c("file-stream-seek", (void*)kseek);                          // unused
  make_function_symbol_from_c("file-stream-read", (void*)kread);                          // used
  make_function_symbol_from_c("file-stream-write", (void*)kwrite);                        // used
  make_function_symbol_from_c("scf-get-language", (void*)DecodeLanguage);                 // used
  make_function_symbol_from_c("scf-get-time", (void*)DecodeTime);                         // used
  make_function_symbol_from_c("scf-get-aspect", (void*)DecodeAspect);                     // used
  make_function_symbol_from_c("scf-get-volume", (void*)DecodeVolume);                     // used
  make_function_symbol_from_c("scf-get-territory", (void*)DecodeTerritory);               // used
  make_function_symbol_from_c("scf-get-timeout", (void*)DecodeTimeout);                   // used
  make_function_symbol_from_c("scf-get-inactive-timeout", (void*)DecodeInactiveTimeout);  // used
  make_function_symbol_from_c("dma-to-iop", (void*)dma_to_iop);                           // unused
  make_function_symbol_from_c("kernel-shutdown", (void*)jak1::KernelShutdown);  // used TODO jak1
  make_function_symbol_from_c("aybabtu", (void*)sceCdMmode);                    // used

  InitMachine_PCPort();
  InitSoundScheme();
  intern_from_c("*stack-top*")->value = 0x07ffc000;
  intern_from_c("*stack-base*")->value = 0x07ffffff;
  intern_from_c("*stack-size*")->value = 0x4000;

  if (DiskBoot) {
    intern_from_c("*kernel-boot-message*")->value = intern_from_c(DebugBootMessage).offset;
    intern_from_c("*kernel-boot-mode*")->value = intern_from_c("boot").offset;  // or debug-boot
    intern_from_c("*kernel-boot-level*")->value = intern_from_c(DebugBootLevel).offset;
  }

  // todo remove MasterUseKernel
  if (DiskBoot && MasterUseKernel) {
    *EnableMethodSet = (*EnableMethodSet) + 1;
    load_and_link_dgo_from_c("game", kglobalheap,
                             LINK_FLAG_OUTPUT_LOAD | LINK_FLAG_EXECUTE | LINK_FLAG_PRINT_LOGIN,
                             0x400000, true);
    *EnableMethodSet = (*EnableMethodSet) - 1;
    using namespace jak1_symbols;
    kernel_packages->value =
        new_pair(s7.offset + FIX_SYM_GLOBAL_HEAP, *((s7 + FIX_SYM_PAIR_TYPE).cast<u32>()),
                 make_string_from_c("engine"), kernel_packages->value);
    kernel_packages->value =
        new_pair(s7.offset + FIX_SYM_GLOBAL_HEAP, *((s7 + FIX_SYM_PAIR_TYPE).cast<u32>()),
                 make_string_from_c("art"), kernel_packages->value);
    kernel_packages->value =
        new_pair(s7.offset + FIX_SYM_GLOBAL_HEAP, *((s7 + FIX_SYM_PAIR_TYPE).cast<u32>()),
                 make_string_from_c("common"), kernel_packages->value);

    boot_replay_pre_play();
    if (s_boot_replay_first_dispatch) {
      if (ListenerFunction->value != s7.offset) {
        std::fprintf(stderr, "BOOTREPLAY listener occupied before first dispatch\n");
        std::exit(EXIT_FAILURE);
      }
      ListenerFunction->value = make_function_from_c((void*)boot_replay_start_run, false).offset;
    } else {
      lg::info("calling play");
      call_goal_function_by_name("play");
    }
  }
}

// ─── F1 (Geyser Rock gameplay) deterministic warp ──────────────────────────────
// Env OG_F1_WARP / Android prop debug.opengoal.f1.warp — OFF by default.
//
// Replicates, ONCE on the GOAL kernel thread, the desktop F1 oracle's listener
// command  (start 'play (get-continue-by-name *game-info* "game-start")) .
// The Android build registers Deci2Server with NO socket (android_runtime_full.cpp),
// so the device cannot be driven by the goalc listener the way f1_x86_dump.sh
// drives the desktop oracle. This hook lets the device reach the SAME Geyser Rock
// ('training) "game-start" spawn the x86 oracle measures, so the F1 device-vs-desktop
// position match is a true apples-to-apples physics-settle determinism test — both
// sides bypass the intro cinematic (whose arm64 control-transfer is a separate,
// independently-tracked blocker). Verified on desktop x86 FIRST: with OG_F1_WARP=1
// it must reproduce the listener oracle's settle (-5393129 / 28317 / 4362849).
//
// The explicit-pp C->GOAL trampoline (same one mips2c's jalr uses): runs a GOAL
// function with a caller-chosen process pointer (GOAL reg R13). Needed because
// the plain call_goal hardcodes pp = symbol-table base, which makes `start`'s
// process-spawn deref a garbage parent and SIGSEGV. On arm64 the systemv name is
// a thin wrapper to _call_goal8_asm_arm64 (linux_arm64_runtime_compat.cpp).
extern "C" u64 _call_goal8_asm_systemv(void* func, u64* arg_array, u64 zero, u64 pp, u64 st,
                                       void* off);
#if defined(__APPLE__) && defined(__aarch64__)
// macOS has no linux_arm64_runtime_compat.cpp; bind the wrapper here. The
// asm-name declaration matches the .s label exactly (Mach-O would otherwise
// prepend an extra underscore to the C reference).
extern "C" u64 _call_goal8_asm_arm64(void* func,
                                     u64* arg_array,
                                     u64 zero,
                                     u64 pp,
                                     u64 st,
                                     void* off) asm("_call_goal8_asm_arm64");
extern "C" u64 _call_goal8_asm_systemv(void* func, u64* arg_array, u64 zero, u64 pp, u64 st,
                                       void* off) {
  return _call_goal8_asm_arm64(func, arg_array, zero, pp, st, off);
}
#endif

static u64 boot_replay_start_run() {
  const u32 lp = intern_from_c("*listener-process*")->value;
  const u32 play = intern_from_c("play")->value;
  u64 args[8] = {intern_from_c("#t").offset, s7.offset, 0, 0, 0, 0, 0, 0};
  _call_goal8_asm_systemv(g_ee_main_mem + play, args, 0, lp, s7.offset, g_ee_main_mem);
  boot_replay::checkpoint("play-returned", nullptr, 0);

  const u32 gi = intern_from_c("*game-info*")->value;
  if (!gi || gi == s7.offset || (gi & OFFSET_MASK) != 4 || gi >= EE_MAIN_MEM_SIZE) {
    std::fprintf(stderr, "BOOTREPLAY game-info missing after play\n");
    std::exit(EXIT_FAILURE);
  }
  Ptr<Type> type(*Ptr<u32>(gi - 4));
  const u32 init = type->get_method(9).offset;
  // Same default continue selection as normal play. This queues the original
  // restart process; no manual start, actor reset, or late RNG reseed is added.
  args[0] = gi;
  args[1] = intern_from_c("game").offset;
  args[2] = s7.offset;
  args[3] = s7.offset;
  if (s_boot_replay_actors_sweep) {
    const char* cont = std::getenv("OG_BOOT_REPLAY_CONTINUE");
    // Choose the initial continue before restart/start and every actor birth.
    // A later warp is not a substitute for recording the initial scene's actors.
    const size_t length = cont ? std::strlen(cont) : 0;
    if (length > 255) {
      std::fprintf(stderr, "BOOTREPLAY initial continue name too long\n");
      std::exit(EXIT_FAILURE);
    }
    boot_replay::checkpoint("initial-continue", cont ? cont : "", length);
    if (length) {
      args[3] = make_string_from_c(cont);
    }
  }
  _call_goal8_asm_systemv(g_ee_main_mem + init, args, 0, lp, s7.offset, g_ee_main_mem);
  boot_replay::checkpoint("initialize-returned", nullptr, 0);
  s_boot_replay_listener_ran = true;
  return 0;
}

static bool f1_warp_requested() {
  if (std::getenv("OG_F1_WARP")) {
    return true;
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.f1.warp", buf) > 0 && buf[0] == '1') {
    return true;
  }
#endif
  return false;
}

// The warp body — invoked BY THE KERNEL (kernel-dispatcher -> reset-and-call) as
// *listener-function*, so it runs with a live current process (pp) on a real
// process stack: the context `start`/`process-spawn` require. GOAL registers are
// NOT preserved across the make_function_from_c trampoline, so re-read everything
// and pass pp explicitly to the _call_goal8 trampoline (plain call_goal would
// reset pp to the symbol-table base, which crashes process-spawn).
static u64 f1_warp_run() {
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    lg::warn("[F1-WARP] run: *game-info* not ready");
    return 0;
  }
  // Gwarp-dpad (autoport): the continue-point name is overridable (env
  // OG_F1_WARP_CONT / prop debug.opengoal.f1.warp.cont) so device validators
  // can spawn at other continue points — e.g. "training-warp" puts Jak right
  // at the Geyser Rock warp gate to exercise the warp selection UI. Default
  // stays "game-start" (the F1 oracle-match spawn).
  const char* cont_name = "game-start";
  char cont_buf[128] = {0};
#if defined(__ANDROID__)
  // A blank/whitespace prop value (props can't be set truly empty) means
  // "unset" — keep the default.
  if (__system_property_get("debug.opengoal.f1.warp.cont", cont_buf) > 0 &&
      cont_buf[strspn(cont_buf, " \t")] != '\0') {
    cont_name = cont_buf + strspn(cont_buf, " \t");
  }
#endif
  if (const char* e = std::getenv("OG_F1_WARP_CONT")) {
    cont_name = e;
  }
  u64 name = make_string_from_c(cont_name);
  Ptr<Type> gi_type(*Ptr<u32>(gi - 4));  // basic: type tag is the word before field-0
  u64 cont = call_method_of_type_arg2(gi, gi_type, 18 /*get-continue-by-name*/, (u32)name, 0);
  lg::info("[F1-WARP] get-continue-by-name(\"{}\") -> #x{:x}", cont_name, (u32)cont);
  if (cont == 0 || cont == (u32)s7.offset) {
    lg::warn("[F1-WARP] continue '{}' not found; warp aborted", cont_name);
    return 0;
  }
  u32 start_fn = intern_from_c("start")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  u64 args[8] = {intern_from_c("play").offset, cont, 0, 0, 0, 0, 0, 0};
  u64 tgt = _call_goal8_asm_systemv((void*)(g_ee_main_mem + start_fn), args, 0, (u64)lp,
                                    (u64)s7.offset, g_ee_main_mem);
  lg::info("[F1-WARP] (start 'play game-start) -> *target* #x{:x}", (u32)tgt);

  // Deterministic spawn datum. `start`->init-target ran synchronously and set
  // *target*'s position to the game-start continue point; the slide-to-rest that
  // follows over the next ~20 kernel frames carries an arm64 frame-timing variance
  // (the heavy training-level load jitters the game loop), so the SETTLE position
  // is NOT bit-reproducible — but the SPAWN (read here, before any physics frame)
  // is the continue datum, identical on desktop and device. Emit it the same way
  // the Merc2 F1 probe emits F1-STATE (control offset 108 -> trans offset 12), so
  // f1_run.sh can capture this deterministic game-state for the device-vs-desktop
  // match.
  u32 tgt32 = (u32)tgt;
  if (tgt32 != 0 && tgt32 != (u32)s7.offset && tgt32 < (u32)(EE_MAIN_MEM_SIZE - 4)) {
    u32 ctrl = 0;
    std::memcpy(&ctrl, g_ee_main_mem + tgt32 + 108, 4);
    if (ctrl != 0 && ctrl != (u32)s7.offset && ctrl < (u32)(EE_MAIN_MEM_SIZE - 24)) {
      float sx = 0.f, sy = 0.f, sz = 0.f;
      std::memcpy(&sx, g_ee_main_mem + ctrl + 12 + 0, 4);
      std::memcpy(&sy, g_ee_main_mem + ctrl + 12 + 4, 4);
      std::memcpy(&sz, g_ee_main_mem + ctrl + 12 + 8, 4);
      printf("F1-SPAWN tx=%f ty=%f tz=%f\n", sx, sy, sz);
      fflush(stdout);
    }
  }
  // The input-replay harness anchors its recorded clip here: Jak has spawned at
  // Geyser, the title and the variable level-load are behind us.
  s_pad_replay_warp_gameplay = true;
  return tgt;
}

void f1_maybe_warp_to_geyser() {
  static bool s_done = false;
  if (s_done) {
    return;
  }
  if (!f1_warp_requested()) {
    return;
  }
  // Readiness: *game-info* bound to a real boxed basic, and `start` bound to a fn.
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 start_fn = intern_from_c("start")->value;
  if (start_fn == 0 || start_fn == (u32)s7.offset) {
    return;
  }
  // The spawn machinery `start` -> process-spawn draws from must exist, else the
  // warp derefs uninitialized engine state and crashes. *target-dead-pool* (the
  // :from pool of `start`'s process-spawn) is bound only after engine init, so it
  // is a precise "engine ready for target spawn" gate.
  u32 dead_pool = intern_from_c("*target-dead-pool*")->value;
  if (dead_pool == 0 || dead_pool == (u32)s7.offset) {
    return;
  }
  // Settle margin: tick count AFTER the engine is ready (the checks above all
  // pass), letting the title attract fully come up before `(start 'play ...)`
  // fires — mirroring the desktop oracle's wait past `link finish: logo`. Tunable
  // via OG_F1_WARP_DELAY (kernel-dispatch ticks); default ~10s @ 60Hz.
  int delay = 600;
  if (const char* d = std::getenv("OG_F1_WARP_DELAY")) {
    delay = atoi(d);
  }
  static int s_ticks = 0;
  if (s_ticks++ < delay) {
    return;
  }
  s_done = true;

  // Hand the warp to the kernel's *listener-function* slot. kernel-dispatcher
  // runs it via `reset-and-call` INSIDE the dispatch frame, on the listener
  // process's own stack and with pp (GOAL reg R13) set to a real process — the
  // exact context `start` -> `process-spawn` requires. A raw C-side call (even
  // _call_goal8 with an explicit pp) runs `start` off the dispatch stack with no
  // live process context and SIGSEGVs in process-spawn. This mirrors the desktop
  // F1 oracle, which warps by sending `(start 'play game-start)` to the same
  // listener-function slot over the goalc socket (unavailable on Android).
  Ptr<Function> warp_fn = make_function_from_c((void*)f1_warp_run, false);
  ListenerFunction->value = warp_fn.offset;
  lg::info("[F1-WARP] armed *listener-function* = #x{:x}; kernel will run the warp in-context",
           warp_fn.offset);
}

// ─── GENERIC LEVEL WARP (debug-only zone-sweep tool) ───────────────────────────
// Env OG_LEVEL_WARP=<continue-name> / Android prop debug.opengoal.level.warp=<name>
// — OFF by default (empty/unset). A generalization of f1_maybe_warp_to_geyser: the
// F1 warp hardcodes the "game-start" continue; this reads the continue-point NAME
// from the prop/env so a device build can be warped DIRECTLY into ANY jak1 level by
// its continue name (e.g. "jungle-start", "beach-start", "village2-start", ...) to
// confirm that level LOADS + RUNS crash-free on the real arm64 + GL device — a check
// the qemu link-only sweep structurally cannot make.
//
// Mechanism is byte-for-byte the F1 warp's: on the GOAL kernel thread, via the
// kernel's *listener-function* slot (so it runs with a live process context),
//   (start 'play (get-continue-by-name *game-info* "<name>"))
// the exact listener form the desktop oracle uses. DEBUG-ONLY: the prop is never set
// in the shipped APK, so this body never runs in production. x86 is unaffected unless
// OG_LEVEL_WARP is explicitly exported. goal_src / x86 emitter / gold are untouched.
// Sized independently of PROP_VALUE_MAX (Android-only macro) so the x86 desktop build
// compiles; PROP_VALUE_MAX is 92, 128 covers it and any env value comfortably.
static char s_level_warp_name[128] = {0};

static bool level_warp_requested() {
  if (const char* e = std::getenv("OG_LEVEL_WARP")) {
    if (e[0]) {
      std::strncpy(s_level_warp_name, e, sizeof(s_level_warp_name) - 1);
      s_level_warp_name[sizeof(s_level_warp_name) - 1] = 0;
      return true;
    }
  }
#if defined(__ANDROID__)
  // lighting-hdr : le point de reprise a une PROPRIETE, comme sa position juste en dessous
  // (`debug.opengoal.level.warp.pos`, qui l'avait deja). Sans elle le jeu de references ne peut
  // pas tourner sur l'appareil : `lib/proof_run.sh` ne transmet aucune variable d'environnement
  // en mode device, il ne pose que des proprietes — le plan aurait photographie le point de
  // depart du jeu au lieu du vantage nomme, dans les trois configurations, sans rien signaler.
  {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.level.warp", pbuf) > 0 && pbuf[0]) {
      std::strncpy(s_level_warp_name, pbuf, sizeof(s_level_warp_name) - 1);
      s_level_warp_name[sizeof(s_level_warp_name) - 1] = 0;
      return true;
    }
  }
#endif
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.level.warp", buf) > 0 && buf[0]) {
    std::strncpy(s_level_warp_name, buf, sizeof(s_level_warp_name) - 1);
    s_level_warp_name[sizeof(s_level_warp_name) - 1] = 0;
    return true;
  }
#endif
  return false;
}

// The warp body — invoked BY THE KERNEL as *listener-function* (same in-context
// trampoline f1_warp_run uses). Re-reads every symbol and passes pp explicitly.
static u64 level_warp_run() {
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    lg::warn("[LEVEL-WARP] run: *game-info* not ready");
    return 0;
  }
  u64 name = make_string_from_c(s_level_warp_name);
  Ptr<Type> gi_type(*Ptr<u32>(gi - 4));  // basic: type tag is the word before field-0
  u64 cont = call_method_of_type_arg2(gi, gi_type, 18 /*get-continue-by-name*/, (u32)name, 0);
  lg::info("[LEVEL-WARP] get-continue-by-name(\"{}\") -> #x{:x}", s_level_warp_name, (u32)cont);
  if (cont == 0 || cont == (u32)s7.offset) {
    lg::warn("[LEVEL-WARP] continue '{}' not found; warp aborted", s_level_warp_name);
    printf("LEVEL-WARP-FAIL name=%s reason=continue-not-found\n", s_level_warp_name);
    fflush(stdout);
    return 0;
  }
  // Optional spawn-position override — env OG_LEVEL_WARP_POS / prop
  // debug.opengoal.level.warp.pos = "x y z" in METERS. Patches the continue point's
  // trans (and camera-trans by the same delta) in EE memory BEFORE (start 'play ...),
  // so a debug run can spawn Jak at an exact world point (e.g. next to the jungle
  // blue-eco vent) instead of a long blind cpad drive from the continue. DEBUG-ONLY:
  // never set in production; continue-point layout per all-types.gc (trans @16,
  // camera-trans @48; C++ addr = basic ptr + deftype offset - 4).
  {
    char posbuf[128] = {0};
    // perf-stock-baseline : LA CAMPAGNE PREND LE TELEPORT EN ENTIER, OU N'Y TOUCHE PAS.
    // Elle teleporte entre vantages sans passer par l'environnement (aucune variable ne peut
    // etre posee en cours de course sur l'appareil). Quand c'est SON teleport, sa position est
    // la seule consultee — et quand elle est VIDE, le continue-point garde la sienne. Le
    // reglage `OG_LEVEL_WARP_POS` / `debug.opengoal.level.warp.pos` est pose par le harnais
    // pour le PREMIER teleport seulement ; le laisser en repli ici l'a RE-APPLIQUE aux
    // vantages suivants (course x86 du 2026-09-10 : `pos override (-116 14 40)m` aux trois
    // teleports, dont `beach-start` et `jungle-start` qui n'ont aucune position — les trois
    // vantages mesures aux memes coordonnees monde).
    char campaign_pos[64] = {0};
    if (perf_baseline::warp_position(campaign_pos, sizeof(campaign_pos))) {
      if (campaign_pos[0]) {
        std::strncpy(posbuf, campaign_pos, sizeof(posbuf) - 1);
      }
    } else {
      if (const char* e = std::getenv("OG_LEVEL_WARP_POS")) {
        std::strncpy(posbuf, e, sizeof(posbuf) - 1);
      }
#if defined(__ANDROID__)
      if (!posbuf[0]) {
        char pbuf[PROP_VALUE_MAX] = {0};
        if (__system_property_get("debug.opengoal.level.warp.pos", pbuf) > 0 && pbuf[0]) {
          std::strncpy(posbuf, pbuf, sizeof(posbuf) - 1);
        }
      }
#endif
    }
    float mx, my, mz;
    if (posbuf[0] && std::sscanf(posbuf, "%f %f %f", &mx, &my, &mz) == 3) {
      float* trans = (float*)(g_ee_main_mem + (u32)cont + 16 - 4);
      float* cam = (float*)(g_ee_main_mem + (u32)cont + 48 - 4);
      float nx = mx * 4096.f, ny = my * 4096.f, nz = mz * 4096.f;
      float dx = nx - trans[0], dy = ny - trans[1], dz = nz - trans[2];
      lg::info("[LEVEL-WARP] pos override ({} {} {})m: trans ({} {} {}) -> ({} {} {})", mx, my,
               mz, trans[0], trans[1], trans[2], nx, ny, nz);
      trans[0] = nx;
      trans[1] = ny;
      trans[2] = nz;
      cam[0] += dx;
      cam[1] += dy;
      cam[2] += dz;
      printf("LEVEL-WARP-POS name=%s x=%.1f y=%.1f z=%.1f\n", s_level_warp_name, mx, my, mz);
      fflush(stdout);
    }
  }
  // lighting-census — LA POSE QUE LE JEU DE REFERENCES EPINGLE. Relevee ICI, apres l'eventuelle
  // surcharge de position et AVANT le `(start 'play ...)` : c'est exactement la pose que Jak va
  // recevoir. La camera du jeu (`cam-string`) n'entre pas dans le calcul — c'est tout l'objet du
  // geste, voir game/graphics/refset.h. Hors mode refset, `note_warp_pose` sort a sa premiere
  // ligne. Disposition du `continue-point` : game-info-h.gc:96 (trans @16, quat @32) ; adresse
  // C++ = pointeur basic + offset du deftype - 4, comme le bloc ci-dessus.
  {
    const float* trans = (const float*)(g_ee_main_mem + (u32)cont + 16 - 4);
    const float* quat = (const float*)(g_ee_main_mem + (u32)cont + 32 - 4);
    const float tm[3] = {trans[0] / 4096.f, trans[1] / 4096.f, trans[2] / 4096.f};
    refset::note_warp_pose(tm, quat);
  }
  // Ghd-skin-origin-stretch (cycle 4) — BRAS DE L'ABLATION SUR L'APPAREIL. Le filet de finitude
  // du reciblage HD (goal_src/jak1/pc/jak-hd.gc, `*hd-finite-arm*`) se desarme ici, depuis la
  // propriete `debug.opengoal.hd.finite_arm=0` (env OG_HD_FINITE_ARM sur x86), pour que les deux
  // bras tournent sur LE MEME APK : sans REPL sur le telephone, c'est le seul chemin vers un
  // symbole GOAL. Un `int` GOAL est stocke brut dans la valeur du symbole. DEBUG SEUL : la
  // propriete n'est jamais posee en production, et vide = on ne touche a rien (defaut GOAL = 1).
  {
    char armbuf[16] = {0};
    if (const char* e = std::getenv("OG_HD_FINITE_ARM")) {
      std::strncpy(armbuf, e, sizeof(armbuf) - 1);
    }
#if defined(__ANDROID__)
    if (!armbuf[0]) {
      char pbuf[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.hd.finite_arm", pbuf) > 0 && pbuf[0]) {
        std::strncpy(armbuf, pbuf, sizeof(armbuf) - 1);
      }
    }
#endif
    if (armbuf[0] == '0' || armbuf[0] == '1') {
      auto sym = intern_from_c("*hd-finite-arm*");
      sym->value = (armbuf[0] == '1') ? 1 : 0;
      printf("HDFINITEARM value=%d source=prop\n", (int)sym->value);
      fflush(stdout);
    }
  }
  // Ghd-skin-origin-stretch — CONTROLE POSITIF DE LA SONDE HDSKINLEN. Un zero d'etirement ne
  // vaut que si l'instrument a tire une fois : `*hd-stretch-inject*` (jak-hd.gc) INJECTE un
  // etirement dans le squelette HD, et la sonde doit le compter. Meme pont que ci-dessus :
  // propriete `debug.opengoal.hd.stretch_inject` (env OG_HD_STRETCH_INJECT sur x86), un `int`
  // GOAL brut dans la valeur du symbole, vide = on ne touche a rien (defaut GOAL = 0).
  {
    char injbuf[16] = {0};
    if (const char* e = std::getenv("OG_HD_STRETCH_INJECT")) {
      std::strncpy(injbuf, e, sizeof(injbuf) - 1);
    }
#if defined(__ANDROID__)
    if (!injbuf[0]) {
      char pbuf[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.hd.stretch_inject", pbuf) > 0 && pbuf[0]) {
        std::strncpy(injbuf, pbuf, sizeof(injbuf) - 1);
      }
    }
#endif
    // Cycle 8 : le pont n'acceptait que '0'/'1' — la valeur 2 (pose de bind, controle positif du
    // detecteur de t-pose, jak-hd.gc:1338) etait AVALEE en silence : Redmi dev7-inj2 a rendu
    // inject_shots=0 sans une ligne HDSTRETCHINJECT. Tout chiffre 0-9 passe tel quel.
    if (injbuf[0] >= '0' && injbuf[0] <= '9') {
      auto sym = intern_from_c("*hd-stretch-inject*");
      sym->value = (s64)(injbuf[0] - '0');
      printf("HDSTRETCHINJECT value=%d source=prop\n", (int)sym->value);
      fflush(stdout);
    }
  }
  // Ghd-skin-origin-stretch — BRAS DE L'ABLATION DE LA GARDE D'ECHELLE. Mesure Redmi dev6-nat
  // (finalboss 720-723, snow 690-694) : joints a 0,000 m de la commande, GPU consommant des os
  // de 4,5 m — la BASE de la matrice explose, pas sa translation. La garde `*hd-scale-arm*`
  // (jak-hd.gc, defaut 1) se desarme ici depuis `debug.opengoal.hd.scale_arm=0` (env
  // OG_HD_SCALE_ARM sur x86) pour que les deux bras tournent sur LE MEME APK. Meme pont que
  // les deux blocs ci-dessus : entier GOAL brut dans le symbole, vide = on ne touche a rien.
  {
    char sclbuf[16] = {0};
    if (const char* e = std::getenv("OG_HD_SCALE_ARM")) {
      std::strncpy(sclbuf, e, sizeof(sclbuf) - 1);
    }
#if defined(__ANDROID__)
    if (!sclbuf[0]) {
      char pbuf[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.hd.scale_arm", pbuf) > 0 && pbuf[0]) {
        std::strncpy(sclbuf, pbuf, sizeof(sclbuf) - 1);
      }
    }
#endif
    if (sclbuf[0] == '0' || sclbuf[0] == '1') {
      auto sym = intern_from_c("*hd-scale-arm*");
      sym->value = (sclbuf[0] == '1') ? 1 : 0;
      printf("HDSCALEARM value=%d source=prop\n", (int)sym->value);
      fflush(stdout);
    }
  }
  // Ghd-skin-origin-stretch (cycle 6e) — LE CORRECTIF : les matrices du pilote lues par le
  // reciblage HD sont rendues AFFINES (jak-hd.gc, `*hd-affine-arm*`, voir hd-mat-affine!). Mesure
  // Redmi : w3=0.9982 sur la ligne de translation d'un os HD -> deplace de (1-w3) x distance de la
  // camera a l'origine du monde (10 m a finalboss). Meme pont, `debug.opengoal.hd.affine_arm`
  // (env OG_HD_AFFINE_ARM), pour l'ablation sur le meme APK ; defaut GOAL = 2 (projectif, cycle 7).
  {
    char affbuf[16] = {0};
    if (const char* e = std::getenv("OG_HD_AFFINE_ARM")) {
      std::strncpy(affbuf, e, sizeof(affbuf) - 1);
    }
#if defined(__ANDROID__)
    if (!affbuf[0]) {
      char pbuf[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.hd.affine_arm", pbuf) > 0 && pbuf[0]) {
        std::strncpy(affbuf, pbuf, sizeof(affbuf) - 1);
      }
    }
#endif
    // cycle 7 : 0 = rien, 1 = colonne w forcee SANS division (l'ancien correctif : translation du
    // modele entier), 2 = normalisation PROJECTIVE (division par w3) + normalisation a la
    // production (joint.gc finalize-frame!, `*anim-mtx-norm-arm*` recopie par jak-hd.gc).
    if (affbuf[0] >= '0' && affbuf[0] <= '2') {
      auto sym = intern_from_c("*hd-affine-arm*");
      sym->value = (s32)(affbuf[0] - '0');
      printf("HDAFFINEARM value=%d source=prop\n", (int)sym->value);
      fflush(stdout);
    }
  }
  u32 start_fn = intern_from_c("start")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  u64 args[8] = {intern_from_c("play").offset, cont, 0, 0, 0, 0, 0, 0};
  u64 tgt = _call_goal8_asm_systemv((void*)(g_ee_main_mem + start_fn), args, 0, (u64)lp,
                                    (u64)s7.offset, g_ee_main_mem);
  lg::info("[LEVEL-WARP] (start 'play {}) -> *target* #x{:x}", s_level_warp_name, (u32)tgt);
  printf("LEVEL-WARP-SPAWN name=%s target=#x%x\n", s_level_warp_name, (u32)tgt);
  fflush(stdout);
  s_level_warp_gameplay = true;
  // lighting-census : L'ANCRE DU JEU D'IMAGES DE REFERENCE, prise ICI et pas par un sondage
  // par image. `pc_autoport_frame` tourne une fois par image RENDUE alors que le compteur de
  // frames de logique avance a chaque image SIMULEE : pendant un chargement les deux se
  // desynchronisent, et l'ancre lue par sondage valait 601 dans une course et 600 dans la
  // suivante. Une frame de logique d'ecart, c'est une autre pose de Jak et une autre position
  // de camera : mesure du 2026-09-06, maxdiff 172-215 et 276093 pixels differents sur 16 images.
  // Ici, l'instant est celui ou `(start 'play <continue>)` vient de rendre *target* — un point
  // fixe de la boucle GOAL.
  // On refixe aussi TOUTES les sources d'alea a cette ancre-la : celle de `pad_replay` s'est
  // posee au menu-titre (il a lui aussi un *target*), et entre le titre et le niveau il se
  // consomme un nombre variable de tirages.
  pad_replay::reseed_now(0x0AD12345u);
  refset::note_anchor();
  return tgt;
}

void level_warp_maybe() {
  static bool s_done = false;
  if (s_done) {
    return;
  }
  if (!level_warp_requested()) {
    return;
  }
  // Readiness: same gate as f1_maybe_warp_to_geyser — *game-info* boxed-basic,
  // `start` bound, and *target-dead-pool* (engine-ready-for-spawn) bound.
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 start_fn = intern_from_c("start")->value;
  if (start_fn == 0 || start_fn == (u32)s7.offset) {
    return;
  }
  u32 dead_pool = intern_from_c("*target-dead-pool*")->value;
  if (dead_pool == 0 || dead_pool == (u32)s7.offset) {
    return;
  }
  // SOUS `OG_REFSET`, LE PREMIER TELEPORT PART A UN INSTANT ABSOLU, PAS APRES UN DELAI.
  // Le delai ci-dessous se compte a partir de la READINESS, qui depend de la vitesse a laquelle
  // le niveau se charge. Mesure du 2026-09-06 sur eae4df44 : `REFSET warp1 lf=600` a la capture,
  // `lf=599` au rejeu. UNE frame de logique d'ecart — et c'est exactement la sensibilite que
  // refset.h chiffre : maxdiff 172-215, ~17000 pixels sur 57600. Les 24 photos du plan heritent
  // de cet ecart, donc le rejeu a rendu `refpix_maxdiff_origine=232` alors que rien de
  // l'eclairage n'avait bouge. Ancrer le teleport sur le COMPTEUR DE FRAMES DE LOGIQUE le rend
  // identique d'une course a l'autre : le compteur avance d'une unite par image SIMULEE, il ne
  // depend ni de la cadence ni du disque.
  if (refset::enabled()) {
    const int64_t lf = refset::current_logic_frame();
    if (lf < 0 || lf < refset::warp_at_frame()) {
      return;
    }
  } else {
    // Settle margin after readiness — let the title attract fully come up before the
    // warp fires. Tunable via OG_LEVEL_WARP_DELAY (kernel-dispatch ticks); default ~10s.
    int delay = 600;
    if (const char* d = std::getenv("OG_LEVEL_WARP_DELAY")) {
      delay = atoi(d);
    }
    static int s_ticks = 0;
    if (s_ticks++ < delay) {
      return;
    }
  }
  s_done = true;

  Ptr<Function> warp_fn = make_function_from_c((void*)level_warp_run, false);
  ListenerFunction->value = warp_fn.offset;
  lg::info("[LEVEL-WARP] armed *listener-function* = #x{:x} for continue '{}'",
           warp_fn.offset, s_level_warp_name);
}

// lighting-census : LE SECOND WARP. `(start 'play <continue>)` rend la main avant que le niveau
// soit entierement resident — le chargement est asynchrone — et la camera passe donc quelques
// images a se poser contre une geometrie incomplete. Son point de repos depend du CHEMIN : deux
// rejeux strictement identiques divergent a partir de l'ancre+7 et se figent a ~0,02 m d'ecart,
// ce qui suffit a rendre 27000 pixels differents sur 57600 (mesure du 2026-09-06), alors que la
// translation de Jak est bit-identique sur 900 images de logique. Re-lancer le meme warp quand le
// niveau est charge TELEPORTE la camera depuis un monde complet. Ne tourne que sous `OG_REFSET`.
static void refset_rewarp_maybe() {
  if (!refset::wants_rewarp()) {
    return;
  }
  // lighting-census (owner 2026-09-07 : « Tous les niveaux ! ») — LE VANTAGE PEUT CHANGER ENTRE
  // DEUX TELEPORTS. `level_warp_run` relit `s_level_warp_name` a chaque execution, mais ce
  // tampon n'etait rempli qu'une fois : `level_warp_requested()` n'est consulte que par
  // `level_warp_maybe`, verrouille par son `static bool s_done`. Le plan de references pose donc
  // `OG_LEVEL_WARP` (et `OG_LEVEL_WARP_POS`) a chaque etape, et cette ligne-ci est ce qui les
  // fait entrer : sans elle, les 25 vantages neufs teleporteraient tous a la hutte de Sandover
  // et la couverture annoncee serait une fiction.
  (void)level_warp_requested();
  Ptr<Function> warp_fn = make_function_from_c((void*)level_warp_run, false);
  ListenerFunction->value = warp_fn.offset;
  lg::info("[LEVEL-WARP] second warp arme pour le jeu d'images de reference");
  printf("REFSET rewarp armed\n");
  fflush(stdout);
}

// perf-stock-baseline : LE TELEPORT DE LA CAMPAGNE DE LIGNE DE BASE. Meme geste exact que le
// re-teleport du jeu de references ci-dessus — `level_warp_run` relit `s_level_warp_name` a
// CHAQUE execution, il suffit donc de remplir ce tampon puis d'armer `*listener-function*`.
// La demande est posee par le fil GL (machine a etats de perf_baseline) et consommee ICI, sur
// le fil GOAL, une seule fois par demande. La campagne ne demande que DEUX teleports (les
// vantages 1 et 2, le 0 etant celui ou le harnais a deja depose le jeu) : chaque
// `(start 'play ...)` supplementaire rapproche la course du SIGILL du 4e teleport.
static void perf_baseline_warp_maybe() {
  char nm[64] = {0}, ps[64] = {0};
  if (!perf_baseline::take_warp_request(nm, sizeof(nm), ps, sizeof(ps))) {
    return;
  }
  std::strncpy(s_level_warp_name, nm, sizeof(s_level_warp_name) - 1);
  s_level_warp_name[sizeof(s_level_warp_name) - 1] = 0;
  Ptr<Function> f = make_function_from_c((void*)level_warp_run, false);
  ListenerFunction->value = f.offset;
  printf("PERF-BASELINE warp armed name=%s pos=%s\n", nm, ps);
  fflush(stdout);
}

// ─── TASK CLOSE (Gcrash-rockvillage debug-only repro tool) ──────────────────────
// Closes specific game-task cstages at runtime so a device repro can cross
// task-gated content (e.g. village2-warrior-money=33 restores the swamp pontoons)
// without a listener connection. Gated by env OG_TASK_CLOSE / Android prop
// debug.opengoal.task.close = "<task>[:<status>][,<task>[:<status>]...]"; status
// defaults to 7 = (task-status need-resolution). Fires ONCE on the GOAL kernel
// thread via *listener-function* — same dispatch context as the level warp — with
// a shorter default delay (300 ticks, OG_TASK_CLOSE_DELAY) so a same-boot
// level.warp (default 600) spawns with the task already closed. DEBUG-ONLY:
// never armed in production; goal_src / x86 emitter / gold untouched.
static char s_task_close_spec[128];

#if defined(JAK_SWAMP_CAPTURE)
// Owner swamp-crash capture build (INSTRUMENTATION ONLY). Returns true once
// village2 is loaded AND active — the same 'active status load-boundary.gc:1275
// waits on. Calling level-status (method 25 of level-group) on *level* is safe
// here: task_close_maybe runs on the GOAL kernel thread between dispatch frames
// (kboot.cpp), the identical GOAL-call context the level-warp / task-close
// listener-function hooks already use.
static bool swamp_capture_village2_active() {
  u32 lg_sym = intern_from_c("*level*")->value;  // the level-group object
  if (lg_sym == 0 || lg_sym == (u32)s7.offset) {
    return false;  // *level* not bound yet
  }
  // Gate on close-specific-task! being bound: it is a real function symbol (unlike
  // level-status, which exists only as a level-group METHOD, not a symbol) and it
  // is defined in the same engine load band as the level system + level.gc's
  // level-status method — so its binding proves *level*'s vtable is linked and
  // method 25 is safe to call. It is also exactly the function the task-close hook
  // will invoke, so this readiness check and the runner stay consistent.
  u32 close_fn = intern_from_c("close-specific-task!")->value;
  if (close_fn == 0 || close_fn == (u32)s7.offset) {
    return false;
  }
  Ptr<Type> lg_type(*Ptr<u32>(lg_sym - 4));  // basic type-tag is the word before field-0
  u32 vi2 = intern_from_c("village2").offset;  // 'village2 symbol object
  u64 st = call_method_of_type_arg2(lg_sym, lg_type, 25 /*level-status*/, vi2, 0);
  return st == (u64)intern_from_c("active").offset;
}
#endif

static bool task_close_requested() {
  s_task_close_spec[0] = 0;
  if (const char* e = std::getenv("OG_TASK_CLOSE")) {
    std::strncpy(s_task_close_spec, e, sizeof(s_task_close_spec) - 1);
  }
#if defined(__ANDROID__)
  if (!s_task_close_spec[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.task.close", pbuf) > 0 && pbuf[0]) {
      std::strncpy(s_task_close_spec, pbuf, sizeof(s_task_close_spec) - 1);
    }
  }
#endif
#if defined(JAK_SWAMP_CAPTURE)
  // No env/prop set: auto-close task 33 (village2-warrior-money = 90-orb pontoon
  // restore) so the owner reaches the Rock Village -> Boggy Swamp transition
  // WITHOUT adb and WITHOUT 90 orbs. Only once village2 is active; task_close_maybe
  // latches on its static s_done so this fires exactly once (idempotent — no
  // spam-close every frame).
  if (!s_task_close_spec[0] && swamp_capture_village2_active()) {
    std::strncpy(s_task_close_spec, "33", sizeof(s_task_close_spec) - 1);
  }
#endif
  for (const char* p = s_task_close_spec; *p; ++p) {
    if (*p >= '1' && *p <= '9') {
      return true;  // needs at least one nonzero digit ("", "0", "''" disable)
    }
  }
  return false;
}

static u64 task_close_run() {
  u32 fn = intern_from_c("close-specific-task!")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    printf("TASK-CLOSE-FAIL reason=close-specific-task!-unbound\n");
    fflush(stdout);
    return 0;
  }
  char buf[128];
  std::strncpy(buf, s_task_close_spec, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = 0;
  char* save = nullptr;
#ifdef _WIN32
  // no strtok_r on Windows; strtok_s has the same (str, delim, ctx) contract.
#define OG_STRTOK_R strtok_s
#else
#define OG_STRTOK_R strtok_r
#endif
  for (char* tok = OG_STRTOK_R(buf, ",", &save); tok; tok = OG_STRTOK_R(nullptr, ",", &save)) {
    int task = 0;
    int status = 7;  // (task-status need-resolution)
    if (std::sscanf(tok, "%d:%d", &task, &status) < 1 || task <= 0) {
      continue;
    }
    u64 args[8] = {(u64)task, (u64)status, 0, 0, 0, 0, 0, 0};
    u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp,
                                    (u64)s7.offset, g_ee_main_mem);
    printf("TASK-CLOSE task=%d status=%d -> #x%x\n", task, status, (u32)r);
    fflush(stdout);
  }
  return 0;
}

void task_close_maybe() {
  static bool s_done = false;
  if (s_done) {
    return;
  }
  if (!task_close_requested()) {
    return;
  }
  // Readiness: same gate as level_warp_maybe, plus close-specific-task! bound.
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 fn = intern_from_c("close-specific-task!")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    return;
  }
  u32 dead_pool = intern_from_c("*target-dead-pool*")->value;
  if (dead_pool == 0 || dead_pool == (u32)s7.offset) {
    return;
  }
  int delay = 300;
  if (const char* d = std::getenv("OG_TASK_CLOSE_DELAY")) {
    delay = atoi(d);
  }
  static int s_ticks = 0;
  if (s_ticks++ < delay) {
    return;
  }
  // don't clobber a pending listener function armed by another hook this tick
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  s_done = true;
  Ptr<Function> f = make_function_from_c((void*)task_close_run, false);
  ListenerFunction->value = f.offset;
  lg::info("[TASK-CLOSE] armed *listener-function* = #x{:x} for spec '{}'", f.offset,
           s_task_close_spec);
}

// ─── CINE KICK (Gcutscene-npc-flicker-2 debug-only cutscene launcher) ──────────
// Plays an NPC cutscene WITHOUT a human at the pad. The previous cycle could only
// reach the five cutscenes a `continue-flags` fires on its own (target-death.gc
// :230-271) — all of them Sandover, none of them the MAYOR, which is the exact case
// the owner names ("le pire cas que j'ai observé c'est la cinématique avec MAIRE").
// This hook calls the GOAL `pc-cine-kick!` (engine/game/main.gc), which sends the
// game's own 'play-anim event to the taskable NPC process — the same door
// target-death.gc:239 already uses for sage-23.
//   env OG_CINE_KICK / prop debug.opengoal.cine.kick = "<type>[,<type>...]"
//     comma-separated GOAL TYPE names, in order, e.g. "mayor,farmer,explorer".
//     Empty/unset = hook off (default; production is unchanged bit-for-bit).
//   OG_CINE_KICK_DELAY (default 900 dispatch ticks) — longer than the level warp's
//     600 so the level is loaded and the player settled when the first kick fires.
//   OG_CINE_KICK_GAP   (default 60)   — minimum spacing between two arms, so the
//     single *listener-function* slot is not hammered every dispatch.
//   OG_CINE_KICK_HOLD  (default 1800) — wait after a delivered kick, so the cutscene
//     plays out ENTIRELY before the next name is attempted.
// Unlike the two hooks above it does NOT latch on a global s_done: it re-arms the
// listener once per name in the list, advancing only inside cine_kick_run and only
// according to what the GOAL side returned (2 busy = retry, 1 sent = advance + hold,
// 0 absent = retry up to 40 times then give up). Sized independently of
// PROP_VALUE_MAX (Android-only macro) so the desktop x86 build compiles.
static char s_cine_kick_spec[256] = {0};
static char s_cine_kick_cur[64] = {0};
static int s_cine_kick_idx = 0;    // which name of the list we are launching
static int s_cine_kick_tries = 0;  // consecutive "absent" retries on that name
static int s_cine_kick_wait = 0;   // dispatch ticks to burn before the next arm

static bool cine_kick_requested() {
  if (s_cine_kick_spec[0]) {
    return true;  // already read this boot; the list never changes mid-run
  }
  if (const char* e = std::getenv("OG_CINE_KICK")) {
    if (e[0]) {
      std::strncpy(s_cine_kick_spec, e, sizeof(s_cine_kick_spec) - 1);
      s_cine_kick_spec[sizeof(s_cine_kick_spec) - 1] = 0;
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.cine.kick", buf) > 0 && buf[0]) {
    std::strncpy(s_cine_kick_spec, buf, sizeof(s_cine_kick_spec) - 1);
    s_cine_kick_spec[sizeof(s_cine_kick_spec) - 1] = 0;
    return true;
  }
#endif
  return false;
}

// Copies token #idx of the comma-separated list into out (surrounding blanks
// trimmed, empty tokens skipped). Returns false once idx is past the end — that is
// the hook's stop condition.
static bool cine_kick_name_at(int idx, char* out, size_t out_sz) {
  out[0] = 0;
  int n = 0;
  const char* p = s_cine_kick_spec;
  while (*p) {
    const char* start = p;
    while (*p && *p != ',') {
      ++p;
    }
    const char* end = p;
    if (*p == ',') {
      ++p;
    }
    while (start < end && (*start == ' ' || *start == '\t')) {
      ++start;
    }
    while (end > start && (end[-1] == ' ' || end[-1] == '\t')) {
      --end;
    }
    size_t len = (size_t)(end - start);
    if (len == 0) {
      continue;  // "a,,b" / trailing comma
    }
    if (n == idx) {
      if (len > out_sz - 1) {
        len = out_sz - 1;
      }
      std::memcpy(out, start, len);
      out[len] = 0;
      return true;
    }
    ++n;
  }
  return false;
}

static int cine_kick_env_int(const char* name, int def) {
  if (const char* v = std::getenv(name)) {
    if (v[0]) {
      return atoi(v);
    }
  }
  return def;
}

// The kick body — invoked BY THE KERNEL as *listener-function*, the same in-context
// trampoline level_warp_run / task_close_run use. Returns what pc-cine-kick! returned
// (0 absent / 1 sent / 2 a cutscene is already playing) and OWNS the list index: the
// C++ side never advances anywhere else, so the index can only move on an answer that
// actually came back from GOAL.
static u64 cine_kick_run() {
  u32 fn = intern_from_c("pc-cine-kick!")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    printf("CINEKICK-FAIL reason=pc-cine-kick!-unbound\n");
    fflush(stdout);
    return 0;
  }
  u32 lp = intern_from_c("*listener-process*")->value;
  u64 s = make_string_from_c(s_cine_kick_cur);
  u64 args[8] = {s, 0, 0, 0, 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp, (u64)s7.offset,
                                  g_ee_main_mem);
  int ret = (int)(u32)r;
  printf("CINEKICK-CALL type=%s ret=%d\n", s_cine_kick_cur, ret);
  fflush(stdout);
  int gap = cine_kick_env_int("OG_CINE_KICK_GAP", 60);
  if (ret == 1) {
    // Delivered: let this cutscene play out ENTIRELY before touching the next name.
    s_cine_kick_idx++;
    s_cine_kick_tries = 0;
    s_cine_kick_wait = cine_kick_env_int("OG_CINE_KICK_HOLD", 1800);
  } else if (ret == 2) {
    // A cutscene is already running — do NOT advance, this name is still owed.
    s_cine_kick_wait = gap;
  } else {
    // Not in the active pool yet. pc-cine-kick! raises the actor birth bound on the
    // first miss, so the next tries can see an NPC that had not been born.
    s_cine_kick_tries++;
    if (s_cine_kick_tries >= 40) {
      printf("CINEKICK-GIVEUP type=%s\n", s_cine_kick_cur);
      fflush(stdout);
      s_cine_kick_idx++;
      s_cine_kick_tries = 0;
    }
    s_cine_kick_wait = gap;
  }
  return r;
}

void cine_kick_maybe() {
  if (!cine_kick_requested()) {
    return;
  }
  // Stop condition: the index walked past the last name of the list.
  if (!cine_kick_name_at(s_cine_kick_idx, s_cine_kick_cur, sizeof(s_cine_kick_cur))) {
    return;
  }
  // Readiness: same gate as task_close_maybe, with pc-cine-kick! in place of
  // close-specific-task! — the very function the runner will call.
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 fn = intern_from_c("pc-cine-kick!")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    return;
  }
  u32 dead_pool = intern_from_c("*target-dead-pool*")->value;
  if (dead_pool == 0 || dead_pool == (u32)s7.offset) {
    return;
  }
  static int s_ticks = 0;
  if (s_ticks++ < cine_kick_env_int("OG_CINE_KICK_DELAY", 900)) {
    return;
  }
  if (s_cine_kick_wait > 0) {
    s_cine_kick_wait--;
    return;
  }
  // don't clobber a pending listener function — another hook's, or our own previous
  // arm that the kernel has not dispatched yet
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  // Minimum spacing; cine_kick_run overwrites it with its own policy when it fires.
  s_cine_kick_wait = cine_kick_env_int("OG_CINE_KICK_GAP", 60);
  static Ptr<Function> s_cine_kick_fn(0);
  if (s_cine_kick_fn.offset == 0) {
    // allocated once: this hook arms many times, unlike its two neighbours
    s_cine_kick_fn = make_function_from_c((void*)cine_kick_run, false);
  }
  ListenerFunction->value = s_cine_kick_fn.offset;
  lg::info("[CINE-KICK] armed *listener-function* = #x{:x} for type '{}' (idx {}, try {})",
           s_cine_kick_fn.offset, s_cine_kick_cur, s_cine_kick_idx, s_cine_kick_tries);
}

// ─── WANT-LEVELS / WANT-DISPLAY (Gcrash-rockvillage debug-only repro tool) ──────
// Replays the exact GOAL forms a load-boundary crossing executes, without needing
// Jak to physically cross the polyline: `(load village2 swamp)` boundaries call
// load-state-want-levels, `(display swamp display)` boundaries call
// load-state-want-display-level (load-boundary.gc:1095-1102, check-boundary
// :1364-1378). This reproduces the owner's village2->swamp streaming transition
// (rolling evicted, SWA.DGO streamed mid-play, then displayed) deterministically.
//   env OG_WANT_LEVELS / prop debug.opengoal.want.levels = "lev1,lev2"
//     (fires once at OG_WANT_LEVELS_DELAY ticks, default 900)
//   env OG_WANT_DISPLAY / prop debug.opengoal.want.display = "lev[,sym]"
//     (sym default 'display'; fires once at OG_WANT_DISPLAY_DELAY, default 1800 —
//      after the streaming load has had time to finish, like the owner's walk)
// DEBUG-ONLY: never armed in production; goal_src / x86 emitter / gold untouched.
static char s_want_levels_spec[96];
static char s_want_display_spec[96];

static bool want_prop_requested(const char* env, const char* prop, char* out, size_t out_sz) {
  out[0] = 0;
  if (const char* e = std::getenv(env)) {
    std::strncpy(out, e, out_sz - 1);
    out[out_sz - 1] = 0;
  }
#if defined(__ANDROID__)
  if (!out[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get(prop, pbuf) > 0 && pbuf[0]) {
      std::strncpy(out, pbuf, out_sz - 1);
      out[out_sz - 1] = 0;
    }
  }
#endif
  for (const char* p = out; *p; ++p) {
    if ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z')) {
      return true;  // needs at least one letter ("", "0", "''" disable)
    }
  }
  return false;
}

static u64 want_levels_run() {
  u32 fn = intern_from_c("load-state-want-levels")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    printf("WANT-LEVELS-FAIL reason=load-state-want-levels-unbound\n");
    fflush(stdout);
    return 0;
  }
  char buf[96];
  std::strncpy(buf, s_want_levels_spec, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = 0;
  char* comma = std::strchr(buf, ',');
  if (!comma) {
    printf("WANT-LEVELS-FAIL reason=need-two-levels spec=%s\n", buf);
    fflush(stdout);
    return 0;
  }
  *comma = 0;
  u32 lev1 = intern_from_c(buf).offset;
  u32 lev2 = intern_from_c(comma + 1).offset;
  u64 args[8] = {lev1, lev2, 0, 0, 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp,
                                  (u64)s7.offset, g_ee_main_mem);
  printf("WANT-LEVELS lev1=%s lev2=%s -> #x%x\n", buf, comma + 1, (u32)r);
  fflush(stdout);
  return 0;
}

static u64 want_display_run() {
  u32 fn = intern_from_c("load-state-want-display-level")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    printf("WANT-DISPLAY-FAIL reason=load-state-want-display-level-unbound\n");
    fflush(stdout);
    return 0;
  }
  char buf[96];
  std::strncpy(buf, s_want_display_spec, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = 0;
  const char* sym = "display";
  char* comma = std::strchr(buf, ',');
  if (comma) {
    *comma = 0;
    sym = comma + 1;
  }
  u32 lev = intern_from_c(buf).offset;
  u32 disp = (std::strcmp(sym, "#f") == 0) ? (u32)s7.offset : intern_from_c(sym).offset;
  u64 args[8] = {lev, disp, 0, 0, 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp,
                                  (u64)s7.offset, g_ee_main_mem);
  printf("WANT-DISPLAY lev=%s sym=%s -> #x%x\n", buf, sym, (u32)r);
  fflush(stdout);
  return 0;
}

static refset::LoadRestoreRequest s_refset_load_restore;
static bool s_refset_load_restore_armed = false;
static u64 s_refset_load_restores = 0;
static int64_t s_refset_load_restore_lf = 0;

[[noreturn]] static void refset_load_restore_fail(const char* reason) {
  std::fprintf(stderr, "REFSET restore-load FAIL reason=%s case=%zu anchor_lf=%lld "
                       "due_lf=%lld observed_lf=%lld\n",
               reason, s_refset_load_restore.case_index,
               (long long)s_refset_load_restore.anchor_lf,
               (long long)s_refset_load_restore.due_lf,
               (long long)refset::current_logic_frame());
  std::fflush(nullptr);
  std::_Exit(EXIT_FAILURE);
}

static u64 refset_load_restore_run() {
  const auto& request = s_refset_load_restore;
  const int64_t lf = refset::current_logic_frame();
  if (!s_refset_load_restore_armed || lf != request.due_lf) {
    refset_load_restore_fail("execution-deadline");
  }
  const auto& levels = request.levels_spec;
  const auto& display = request.display_spec;
  // Validate BOTH commands before executing either: the existing debug helpers
  // otherwise return normally for an unbound function or a malformed command.
  if (levels.size() >= sizeof(s_want_levels_spec) ||
      display.size() >= sizeof(s_want_display_spec)) {
    refset_load_restore_fail("spec-too-long");
  }
  if (!levels.empty()) {
    const size_t comma = levels.find(',');
    if (comma == std::string::npos || comma == 0 || comma + 1 == levels.size() ||
        levels.find(',', comma + 1) != std::string::npos) {
      refset_load_restore_fail("need-two-levels");
    }
    const u32 fn = intern_from_c("load-state-want-levels")->value;
    if (!fn || fn == s7.offset) refset_load_restore_fail("levels-function-unbound");
  }
  if (!display.empty()) {
    const size_t comma = display.find(',');
    if (comma != std::string::npos &&
        (comma == 0 || comma + 1 == display.size() ||
         display.find(',', comma + 1) != std::string::npos)) {
      refset_load_restore_fail("invalid-display-spec");
    }
    const u32 fn = intern_from_c("load-state-want-display-level")->value;
    if (!fn || fn == s7.offset) refset_load_restore_fail("display-function-unbound");
  }
  char saved_levels[sizeof(s_want_levels_spec)];
  char saved_display[sizeof(s_want_display_spec)];
  std::memcpy(saved_levels, s_want_levels_spec, sizeof(saved_levels));
  std::memcpy(saved_display, s_want_display_spec, sizeof(saved_display));
  if (!levels.empty()) {
    std::memcpy(s_want_levels_spec, levels.c_str(), levels.size() + 1);
    want_levels_run();
  }
  if (!display.empty()) {
    std::memcpy(s_want_display_spec, display.c_str(), display.size() + 1);
    want_display_run();
  }
  std::memcpy(s_want_levels_spec, saved_levels, sizeof(saved_levels));
  std::memcpy(s_want_display_spec, saved_display, sizeof(saved_display));
  s_refset_load_restore_armed = false;
  ++s_refset_load_restores;
  s_refset_load_restore_lf = lf;
  autoport_proof::publish("refset_load_restores", s_refset_load_restores);
  autoport_proof::publish("refset_load_restore_lf", (u64)lf);
  std::printf("REFSET restore-load case=%zu anchor_lf=%lld due_lf=%lld executed_lf=%lld "
              "levels=%s display=%s\n",
              request.case_index, (long long)request.anchor_lf, (long long)request.due_lf,
              (long long)lf, levels.c_str(), display.c_str());
  std::fflush(stdout);
  return 0;
}

static void refset_load_restore_after_dispatch() {
  autoport_proof::publish("refset_load_restores", s_refset_load_restores);
  autoport_proof::publish("refset_load_restore_lf", (u64)s_refset_load_restore_lf);
  const int64_t lf = refset::current_logic_frame();
  if (s_refset_load_restore_armed) {
    // A displaced listener must fail even if its runner never gets called.
    if (lf > s_refset_load_restore.due_lf) refset_load_restore_fail("listener-not-executed");
    return;
  }
  if (!refset::take_load_restore(lf, s_refset_load_restore)) return;
  if (ListenerFunction->value != s7.offset && ListenerFunction->value != 0) {
    refset_load_restore_fail("listener-occupied");
  }
  s_refset_load_restore_armed = true;
  ListenerFunction->value = make_function_from_c((void*)refset_load_restore_run, false).offset;
}

static void want_hook_maybe(const char* env,
                            const char* prop,
                            char* spec,
                            size_t spec_sz,
                            const char* delay_env,
                            int default_delay,
                            u64 (*runner)(),
                            bool* done,
                            int* ticks,
                            const char* tag) {
  if (*done) {
    return;
  }
  if (!want_prop_requested(env, prop, spec, spec_sz)) {
    return;
  }
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 ls = intern_from_c("*load-state*")->value;
  if (ls == 0 || ls == (u32)s7.offset) {
    return;
  }
  int delay = default_delay;
  if (const char* d = std::getenv(delay_env)) {
    delay = atoi(d);
  }
#if defined(__ANDROID__)
  {
    // prop-settable delay: "<prop>.delay" (e.g. debug.opengoal.want.levels.delay)
    char dprop[96];
    snprintf(dprop, sizeof(dprop), "%s.delay", prop);
    char dbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get(dprop, dbuf) > 0 && dbuf[0] && atoi(dbuf) > 0) {
      delay = atoi(dbuf);
    }
  }
#endif
  if ((*ticks)++ < delay) {
    return;
  }
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  *done = true;
  Ptr<Function> f = make_function_from_c((void*)runner, false);
  ListenerFunction->value = f.offset;
  lg::info("[{}] armed *listener-function* for spec '{}'", tag, spec);
}

void want_levels_maybe() {
  static bool s_done = false;
  static int s_ticks = 0;
  want_hook_maybe("OG_WANT_LEVELS", "debug.opengoal.want.levels", s_want_levels_spec,
                  sizeof(s_want_levels_spec), "OG_WANT_LEVELS_DELAY", 900, want_levels_run,
                  &s_done, &s_ticks, "WANT-LEVELS");
}

void want_display_maybe() {
  static bool s_done = false;
  static int s_ticks = 0;
  want_hook_maybe("OG_WANT_DISPLAY", "debug.opengoal.want.display", s_want_display_spec,
                  sizeof(s_want_display_spec), "OG_WANT_DISPLAY_DELAY", 1800, want_display_run,
                  &s_done, &s_ticks, "WANT-DISPLAY");
}

// (vis <nick>) boundaries — e.g. (vis vi2 #f) then (vis swa #f) on the crate->swamp
// walk — call load-state-want-vis(nick), switching the active visibility octree.
static char s_want_vis_spec[96];

static u64 want_vis_run() {
  u32 fn = intern_from_c("load-state-want-vis")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    printf("WANT-VIS-FAIL reason=load-state-want-vis-unbound\n");
    fflush(stdout);
    return 0;
  }
  u32 nick = intern_from_c(s_want_vis_spec).offset;
  u64 args[8] = {nick, 0, 0, 0, 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp,
                                  (u64)s7.offset, g_ee_main_mem);
  printf("WANT-VIS nick=%s -> #x%x\n", s_want_vis_spec, (u32)r);
  fflush(stdout);
  return 0;
}

void want_vis_maybe() {
  static bool s_done = false;
  static int s_ticks = 0;
  want_hook_maybe("OG_WANT_VIS", "debug.opengoal.want.vis", s_want_vis_spec,
                  sizeof(s_want_vis_spec), "OG_WANT_VIS_DELAY", 2400, want_vis_run, &s_done,
                  &s_ticks, "WANT-VIS");
}

// ─── PHYS-ROOM (Grecharged-secondary-motion — SPEC §6, étape 1) ─────────────────
// Arms the GOAL entry point `phys-room-start`: the player-less physics test room in
// which the subject (Keira) is spawned alone and driven, so her secondary motion can
// be measured in a zone where Jak is NOT spawned. DEBUG-ONLY: with no env var and no
// Android prop set this code does nothing at all, so it is never armed in production.
static char s_phys_room_spec[96];

// Deliberately NOT want_prop_requested(): that helper requires at least one LETTER in
// the value, so the obvious `OG_PHYS_ROOM=1` would silently never arm (the trap that
// would cost a whole run). Here any non-empty value other than "0" arms the hook.
static bool phys_room_requested(const char* env, const char* prop, char* out, size_t out_sz) {
  out[0] = 0;
  if (const char* e = std::getenv(env)) {
    std::strncpy(out, e, out_sz - 1);
    out[out_sz - 1] = 0;
  }
#if defined(__ANDROID__)
  if (!out[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get(prop, pbuf) > 0 && pbuf[0]) {
      std::strncpy(out, pbuf, out_sz - 1);
      out[out_sz - 1] = 0;
    }
  }
#endif
  return out[0] != 0 && std::strcmp(out, "0") != 0;
}

static u64 phys_room_run() {
  u32 fn = intern_from_c("phys-room-start")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    // The GOAL side may not be linked yet: fail loudly, never crash.
    printf("PHYS-ROOM-FAIL reason=phys-room-start-unbound\n");
    fflush(stdout);
    return 0;
  }
  u64 args[8] = {0, 0, 0, 0, 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp, (u64)s7.offset,
                                  g_ee_main_mem);
  printf("PHYS-ROOM started -> #x%x\n", (u32)r);
  fflush(stdout);
  return 0;
}

void phys_room_maybe() {
  static bool s_done = false;
  static int s_ticks = 0;
  if (s_done) {
    return;
  }
  if (!phys_room_requested("OG_PHYS_ROOM", "debug.opengoal.phys.room", s_phys_room_spec,
                           sizeof(s_phys_room_spec))) {
    return;
  }
  // Same guards as want_hook_maybe() EXCEPT the *game-info* / *load-state* readiness
  // gate: the room must start from the TITLE SCREEN, with no game session running.
  int delay = 600;
  if (const char* d = std::getenv("OG_PHYS_ROOM_DELAY")) {
    delay = atoi(d);
  }
#if defined(__ANDROID__)
  {
    // prop-settable delay, like want_hook_maybe(): debug.opengoal.phys.room.delay
    char dbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.phys.room.delay", dbuf) > 0 && dbuf[0] &&
        atoi(dbuf) > 0) {
      delay = atoi(dbuf);
    }
  }
#endif
  if (s_ticks++ < delay) {
    return;
  }
  // don't clobber a pending listener function armed by another hook this tick
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  s_done = true;
  Ptr<Function> f = make_function_from_c((void*)phys_room_run, false);
  ListenerFunction->value = f.offset;
  lg::info("[PHYS-ROOM] armed *listener-function* = #x{:x} spec '{}' delay {}", f.offset,
           s_phys_room_spec, delay);
}

// ─── GRV-CANARY (Gcrash-rockvillage debug-only forensic) ────────────────────────
// Watches the TOP 64 bytes of *target*'s main-thread stack (*kernel-dram-stack*
// band) once per kernel dispatch. enter-state branch-3 (gstate.gc:373-380) resets
// SP to stack-top and pushes the return-from-thread-dead HOST address there; the
// repro12 crash RET'd into a bare GOAL offset restored from exactly this band, so
// any write that is NOT the expected trampoline push is the stomp — logged with
// the dispatch tick for frame-resolution bracketing of the writer. Enabled by
// env OG_GRV_CANARY / prop debug.opengoal.grv.canary=1. Read-only observer.
void grv_canary_maybe() {
  static int s_enabled = -1;
  if (s_enabled < 0) {
    s_enabled = 0;
    if (const char* e = std::getenv("OG_GRV_CANARY")) {
      if (e[0] && e[0] != '0') {
        s_enabled = 1;
      }
    }
#if defined(__ANDROID__)
    if (!s_enabled) {
      char pbuf[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.grv.canary", pbuf) > 0 && pbuf[0] == '1') {
        s_enabled = 1;
      }
    }
#endif
  }
  if (!s_enabled) {
    return;
  }
  static bool s_armed = false;
  static u64 s_prev[8];
  static u32 s_band = 0;
  static u64 s_tick = 0;
  static int s_scan_episode = 0;
  s_tick++;
  u32 tgt_sym = intern_from_c("*target*")->value;
  if (tgt_sym == 0 || tgt_sym == (u32)s7.offset || (tgt_sym & OFFSET_MASK) != 4) {
    s_armed = false;
    return;
  }
  u32 mt = *(u32*)(g_ee_main_mem + tgt_sym + 40);       // (-> process main-thread), C off
  if (mt < 0x1000 || mt >= EE_MAIN_MEM_SIZE) {
    s_armed = false;
    return;
  }
  u32 stack_top = *(u32*)(g_ee_main_mem + mt + 28);     // (-> thread stack-top), C off
  if (stack_top < 0x1040 || stack_top >= EE_MAIN_MEM_SIZE) {
    s_armed = false;
    return;
  }
  // Thread-field watch: (-> thread sp) is a 32-bit HEAP field restored into SP by
  // thread-resume; a heap stomp of it resumes target on top of global DATA (the
  // suspected repro12 mechanism: SP=0x1a7ed0 outside the dram arena). Flag any
  // sp/stack-top outside the dram arena band.
  {
    u32 mt_sp = *(u32*)(g_ee_main_mem + mt + 24);
    u32 tt = *(u32*)(g_ee_main_mem + tgt_sym + 44);
    static u32 s_last_bad = 0;
    if (mt_sp && (mt_sp < stack_top - 0x8000 || mt_sp > stack_top) && mt_sp != s_last_bad) {
      s_last_bad = mt_sp;
      printf("GRV-CANARY MT-SP-ANOMALY mt-sp=0x%x stack-top=0x%x tick=%llu\n", mt_sp, stack_top,
             (unsigned long long)s_tick);
      fflush(stdout);
    }
    if (tt >= 0x1000 && tt < EE_MAIN_MEM_SIZE && tt != mt) {
      u32 tt_sp = *(u32*)(g_ee_main_mem + tt + 24);
      u32 tt_top = *(u32*)(g_ee_main_mem + tt + 28);
      static u32 s_last_bad_tt = 0;
      if (tt_sp && tt_top && (tt_sp < tt_top - 0x8000 || tt_sp > tt_top) &&
          tt_sp != s_last_bad_tt) {
        s_last_bad_tt = tt_sp;
        printf("GRV-CANARY TT-SP-ANOMALY tt-sp=0x%x tt-top=0x%x tick=%llu\n", tt_sp, tt_top,
               (unsigned long long)s_tick);
        fflush(stdout);
      }
    }
  }
  u32 band = stack_top - 64;
  u64 cur[8];
  memcpy(cur, g_ee_main_mem + band, 64);
  if (!s_armed || band != s_band) {
    memcpy(s_prev, cur, 64);
    s_armed = true;
    s_band = band;
    u32 rftd = intern_from_c("return-from-thread-dead")->value;
    u32 rft = intern_from_c("return-from-thread")->value;
    printf("GRV-CANARY armed band=0x%x stack-top=0x%x rftd=0x%x rft=0x%x base=%p\n", band,
           stack_top, rftd, rft, (void*)g_ee_main_mem);
    fflush(stdout);
    return;
  }
  // Hot slots (band = stack_top - 64): the state fn's STP frame {X29@top-32=idx4,
  // X30@top-24=idx5} and the enter-state trampoline cell @top-16=idx6. Everything
  // else only matters when a BARE GOAL value (upper32==0) lands in it — host-based
  // fp/ra saves churn constantly and are legit.
  for (int i = 0; i < 8; i++) {
    if (cur[i] != s_prev[i]) {
      bool bare = (cur[i] >> 32) == 0 && cur[i] != 0;
      bool hot = (i >= 4 && i <= 6);
      // Only the host-RA -> bare transition is suspicious: the dram arena is
      // SHARED by post threads, so bare float/GOAL spill churn is legitimate.
      bool was_host = (s_prev[i] >> 32) == 0x7f;
      if ((bare && was_host) || (hot && cur[i] == 0 && was_host)) {
        printf("GRV-CANARY %s off=%d(0x%x) old=%016llx new=%016llx tick=%llu\n",
               hot ? "HOT-ANOMALY" : "BARE-WRITE", i * 8, band + i * 8,
               (unsigned long long)s_prev[i], (unsigned long long)cur[i],
               (unsigned long long)s_tick);
        fflush(stdout);
        s_scan_episode = 10;  // correlate for the next 10 ticks too
        // Seeker correlation: if the intruding value looks like a blend float
        // (~0.9..1.1), scan the camera processes' object spans for the SAME u32 —
        // present = duplicated/misdirected heap write (names the seeker field);
        // absent = the arena slot is the value's only home (pointer fully wrong).
        u32 f32 = (u32)cur[i];
        if (f32 >= 0x3f660000u && f32 <= 0x3f8ccccdu) {
          const char* cams[3] = {"*camera*", "*camera-combiner*", "*camera-base-group*"};
          for (int c = 0; c < 3; c++) {
            u32 cp = intern_from_c(cams[c])->value;
            if (cp < 0x1000 || cp >= EE_MAIN_MEM_SIZE || cp == (u32)s7.offset) {
              continue;
            }
            u32 alloc_len = *(u32*)(g_ee_main_mem + cp + 68);
            u32 span = 116 + (alloc_len < 0x8000 ? alloc_len : 0x2000);
            int hits = 0;
            for (u32 o = 0; o + 4 <= span && hits < 4; o += 4) {
              if (*(u32*)(g_ee_main_mem + cp + o) == f32) {
                printf("GRV-CANARY SEEKER-MATCH %s+0x%x (=0x%x) val=%08x tick=%llu\n", cams[c],
                       o, cp + o, f32, (unsigned long long)s_tick);
                hits++;
              }
            }
            if (hits) {
              fflush(stdout);
            }
          }
        }
      }
      s_prev[i] = cur[i];
    }
  }
  // Episode mode: after an anomaly, keep correlating the live [top-24] float against
  // the camera process spans for a few ticks (single-shot scans race the writer).
  if (s_scan_episode > 0) {
    s_scan_episode--;
    u32 f32 = (u32)cur[5];  // [top-24] = band idx 5
    if (f32 >= 0x3f660000u && f32 <= 0x3f8ccccdu) {
      const char* cams[3] = {"*camera*", "*camera-combiner*", "*camera-base-group*"};
      for (int c = 0; c < 3; c++) {
        u32 cp = intern_from_c(cams[c])->value;
        if (cp < 0x1000 || cp >= EE_MAIN_MEM_SIZE || cp == (u32)s7.offset) {
          continue;
        }
        u32 alloc_len = *(u32*)(g_ee_main_mem + cp + 68);
        u32 span = 116 + (alloc_len < 0x8000 ? alloc_len : 0x2000);
        for (u32 o = 0; o + 4 <= span; o += 4) {
          if (*(u32*)(g_ee_main_mem + cp + o) == f32) {
            printf("GRV-CANARY EPISODE-MATCH %s+0x%x val=%08x tick=%llu\n", cams[c], o, f32,
                   (unsigned long long)s_tick);
            fflush(stdout);
          }
        }
      }
    }
  }
}

// ─── ECO SPHERE SPAWN (Geco-spheres debug-only oracle-diff tool) ────────────────
// Env OG_ECO_SPAWN / Android prop debug.opengoal.eco.spawn =
//   "<pickup-type-int> [period-ticks [dx dy dz]]"  — OFF by default.
// Repeatedly births an eco pickup next to *target* on the GOAL kernel thread,
// replaying the x86 oracle capture's listener form byte-for-byte:
//   (birth-pickup-at-point <vec near target> (pickup-type N) 5.0 #t *entity-pool*
//                          (the-as fact-info #f))
// pickup-type (fact-h.gc): 1=eco-yellow 2=eco-red 3=eco-blue 4=eco-green.
// The device build has no goalc listener, no continue point spawns near a live
// eco, and green eco is tutorial-gated — so this is the only lever that puts an
// eco sphere in-frame on BOTH platforms via the identical mechanism, which the
// per-color device-vs-golden screencap gate requires. Re-fires every period
// ticks (default 300) because an eco birthed outside its level context fades
// after a few seconds. DEBUG-ONLY: the prop is never set in the shipped APK;
// x86 is unaffected unless OG_ECO_SPAWN is explicitly exported.
static int s_eco_spawn_type = 0;
static int s_eco_spawn_period = 300;
static float s_eco_dx = 2.0f, s_eco_dy = 1.0f, s_eco_dz = 2.0f;
// Geco-spheres TEMPORARY diagnostic: last hook-spawned eco pickup's ppointer
// (raw pointer, NOT a basic — a u32 into EE memory), captured in eco_spawn_run
// and consumed by eco_trace_maybe() below. 0 = none yet.
static u32 s_eco_trace_pp = 0;

static bool eco_spawn_requested() {
  char buf[128] = {0};
  if (const char* e = std::getenv("OG_ECO_SPAWN")) {
    std::strncpy(buf, e, sizeof(buf) - 1);
  }
#if defined(__ANDROID__)
  if (!buf[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.eco.spawn", pbuf) > 0) {
      std::strncpy(buf, pbuf, sizeof(buf) - 1);
    }
  }
#endif
  if (!buf[0]) {
    return false;
  }
  int type = 0, period = 0;
  float dx = 0.f, dy = 0.f, dz = 0.f;
  int n = std::sscanf(buf, "%d %d %f %f %f", &type, &period, &dx, &dy, &dz);
  if (n < 1 || type < 1 || type > 9) {
    return false;
  }
  s_eco_spawn_type = type;
  if (n >= 2 && period > 30) {
    s_eco_spawn_period = period;
  }
  if (n >= 5) {
    s_eco_dx = dx;
    s_eco_dy = dy;
    s_eco_dz = dz;
  }
  return true;
}

// The spawn body — invoked BY THE KERNEL as *listener-function* (same in-context
// trampoline the warp hooks use): birth-pickup-at-point is a defbehavior, so it
// needs a live process context (pp), which the dispatcher provides.
static u64 eco_spawn_run() {
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == (u32)s7.offset || (tgt & OFFSET_MASK) != 4 /*BASIC_OFFSET*/ ||
      tgt >= (u32)(EE_MAIN_MEM_SIZE - 112)) {
    return 0;
  }
  u32 ctrl = 0;
  std::memcpy(&ctrl, g_ee_main_mem + tgt + 108, 4);  // target control (F1-SPAWN layout)
  if (ctrl == 0 || ctrl == (u32)s7.offset || ctrl >= (u32)(EE_MAIN_MEM_SIZE - 24)) {
    return 0;
  }
  float t[3];
  std::memcpy(t, g_ee_main_mem + ctrl + 12, 12);  // control trans
  u32 fn = intern_from_c("birth-pickup-at-point")->value;
  u32 pool = intern_from_c("*entity-pool*")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset || pool == 0 || pool == (u32)s7.offset) {
    return 0;
  }
  static Ptr<u8> s_vec;  // one 16B GOAL vector, allocated once on the global heap
  if (s_vec.offset == 0) {
    s_vec = kmalloc(kglobalheap, 16, KMALLOC_ALIGN_16, "eco-spawn-vec");
    if (s_vec.offset == 0) {
      return 0;
    }
  }
  float* v = (float*)(g_ee_main_mem + s_vec.offset);
  v[0] = t[0] + s_eco_dx * 4096.f;
  v[1] = t[1] + s_eco_dy * 4096.f;
  v[2] = t[2] + s_eco_dz * 4096.f;
  v[3] = 1.0f;
  // GOAL passes float args as raw 32-bit bits in GPRs.
  float amount = 5.0f;
  u32 amount_bits = 0;
  std::memcpy(&amount_bits, &amount, 4);
  u64 args[8] = {s_vec.offset,
                 (u64)s_eco_spawn_type,
                 amount_bits,
                 (u64)(s7.offset + jak1_symbols::FIX_SYM_TRUE),
                 pool,
                 (u64)s7.offset,  // (the-as fact-info #f)
                 0,
                 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp, (u64)s7.offset,
                                  g_ee_main_mem);
  // Geco-spheres TEMPORARY diagnostic: remember the ppointer of the just-birthed
  // pickup so eco_trace_maybe() can dump its physics each dispatch. r is the
  // (pointer process) return of birth-pickup-at-point (a raw pointer, not a basic).
  if ((u32)r != 0 && (u32)r != (u32)s7.offset) {
    s_eco_trace_pp = (u32)r;
  }
  printf("ECO-SPAWN type=%d at=%.1f,%.1f,%.1f -> #x%x\n", s_eco_spawn_type, v[0], v[1], v[2],
         (u32)r);
  fflush(stdout);
  return r;
}

void eco_spawn_maybe() {
  if (!eco_spawn_requested()) {
    return;
  }
  // Readiness: *target* alive (a real boxed basic) and birth-pickup-at-point bound.
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == (u32)s7.offset || (tgt & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 fn = intern_from_c("birth-pickup-at-point")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    return;
  }
  // Settle ~2s after target exists (camera lands), then re-fire every period.
  static int s_ticks = 0;
  s_ticks++;
  if (s_ticks < 120 || (s_ticks - 120) % s_eco_spawn_period != 0) {
    return;
  }
  // Never stomp a pending listener form (the kernel resets the slot to #f after
  // running it — kboot.cpp dispatch loop).
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  static Ptr<Function> s_fn;  // trampoline allocated once
  if (s_fn.offset == 0) {
    s_fn = make_function_from_c((void*)eco_spawn_run, false);
  }
  ListenerFunction->value = s_fn.offset;
  lg::info("[ECO-SPAWN] armed type={} period={} ticks={}", s_eco_spawn_type, s_eco_spawn_period,
           s_ticks);
}

// ─── TOD-PIN (night A/B test lever) ──────────────────────────────────────────
// Env OG_TOD_HOUR / Android prop debug.opengoal.tod.hour = "<0-23>" — OFF by
// default. Pins the in-game clock: sets *time-of-day-proc*'s hour to the value,
// minute/second/frame to 0, and time-ratio to 0.0 (freezing the clock) so the
// night pose is deterministic for the Gperf-particles night A/B. Latched once
// (parsed on first read like eco_spawn), fires ONCE when the proc is ready.
// GOAL field offsets from decompiler/config/jak1/all-types.gc:8153 (deftype
// time-of-day-proc): hour :offset-assert 128, minute 132, second 136,
// frame 140, time-ratio :offset-assert 148. *time-of-day-proc* is a boxed basic
// (process), so a field write is g_ee_main_mem + proc + (goal_offset - 4),
// exactly like eco_spawn_run's +108 (=112-4 root) / +12 (=16-4 trans) writes.
static int s_tod_hour = -1;

static bool tod_pin_requested() {
  static bool s_parsed = false;
  static bool s_result = false;
  if (s_parsed) {
    return s_result;
  }
  s_parsed = true;
  char buf[16] = {0};
  if (const char* e = std::getenv("OG_TOD_HOUR")) {
    std::strncpy(buf, e, sizeof(buf) - 1);
  }
#if defined(__ANDROID__)
  if (!buf[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.tod.hour", pbuf) > 0) {
      std::strncpy(buf, pbuf, sizeof(buf) - 1);
    }
  }
#endif
  if (!buf[0]) {
    return false;
  }
  int hour = -1;
  int n = std::sscanf(buf, "%d", &hour);
  if (n < 1 || hour < 0 || hour > 23) {
    return false;
  }
  s_tod_hour = hour;
  s_result = true;
  return true;
}

// The pin body — invoked BY THE KERNEL as *listener-function* (same in-context
// trampoline the eco/warp hooks use). Writes the clock fields of
// *time-of-day-proc* directly in GOAL memory.
static u64 tod_pin_run() {
  u32 tod = intern_from_c("*time-of-day-proc*")->value;
  if (tod == 0 || tod == (u32)s7.offset || tod >= (u32)(EE_MAIN_MEM_SIZE - 64)) {
    return 0;
  }
  // *time-of-day-proc* is a ppointer: deref once to get the process basic ptr,
  // then fields live at proc + (deftype_offset - 4). Confirmed by the diagnostic
  // dump: deref+124 held a valid hour and deref+140 the matching time-of-day
  // float; deref is a real basic pointer (& 7 == 4).
  u32 proc = 0;
  std::memcpy(&proc, g_ee_main_mem + tod, 4);
  if (proc < 0x10000u || proc == (u32)s7.offset || (proc & OFFSET_MASK) != 4 ||
      proc >= (u32)(EE_MAIN_MEM_SIZE - 256)) {
    return 0;
  }
  s32 hour = (s32)s_tod_hour;
  s32 zero = 0;
  float ratio = 0.0f;  // freeze the clock (time-ratio 0), like the boundary cmd
  std::memcpy(g_ee_main_mem + proc + 124, &hour, 4);   // hour       (goal 128 - 4)
  std::memcpy(g_ee_main_mem + proc + 128, &zero, 4);   // minute     (goal 132 - 4)
  std::memcpy(g_ee_main_mem + proc + 132, &zero, 4);   // second     (goal 136 - 4)
  std::memcpy(g_ee_main_mem + proc + 136, &zero, 4);   // frame      (goal 140 - 4)
  std::memcpy(g_ee_main_mem + proc + 144, &ratio, 4);  // time-ratio (goal 148 - 4)
  s32 rb = 0;
  std::memcpy(&rb, g_ee_main_mem + proc + 124, 4);
  printf("TOD-PIN hour=%d proc=%x (ppointer=%x) readback_hour=%d\n", s_tod_hour, proc, tod, rb);
  fflush(stdout);
  return 0;
}

void tod_pin_maybe() {
  if (!tod_pin_requested()) {
    return;
  }
  // Re-pin PERIODICALLY (not one-shot): the game's time-of-day tick drifts the
  // clock back to daylight within ~2 min even with time-ratio 0, so re-write the
  // night hour every ~45 dispatch passes to HOLD the pinned night for the A/B.
  static int s_ctr = 0;
  if ((s_ctr++ % 45) != 0) {
    return;
  }
  // Readiness: *time-of-day-proc* is a ppointer (raw pointer); deref it and
  // require the process to be a live basic (& 7 == 4) before arming, so the pin
  // never writes a half-spawned proc.
  u32 tod = intern_from_c("*time-of-day-proc*")->value;
  if (tod < 0x10000u || tod == (u32)s7.offset || tod >= (u32)(EE_MAIN_MEM_SIZE - 8)) {
    return;
  }
  u32 proc = 0;
  std::memcpy(&proc, g_ee_main_mem + tod, 4);
  if (proc < 0x10000u || proc == (u32)s7.offset || (proc & OFFSET_MASK) != 4 ||
      proc >= (u32)(EE_MAIN_MEM_SIZE - 256)) {
    return;
  }
  // Never stomp a pending listener form (the kernel resets the slot to #f after
  // running it — kboot.cpp dispatch loop).
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  static Ptr<Function> s_fn;  // trampoline allocated once
  if (s_fn.offset == 0) {
    s_fn = make_function_from_c((void*)tod_pin_run, false);
  }
  ListenerFunction->value = s_fn.offset;
  static bool s_logged = false;
  if (!s_logged) {
    s_logged = true;
    lg::info("[TOD-PIN] armed hour={} (re-pinning periodically)", s_tod_hour);
  }
}

// ─── TOD FAST-FORWARD (Gperf-particles2 capture lever, NOT a pin) ───────────────
// Env OG_TOD_FAST / Android prop debug.opengoal.tod.fast — OFF by default. UNLIKE
// tod.hour (which FREEZES the clock at time-ratio 0 for a static night pose), this
// makes the clock ADVANCE FAST but continuously: it writes *time-of-day-proc*'s
// time-ratio to 18000.0 (the game's own *time-of-day-fast* rate, ~60x the normal
// 300), so a full day->night->day cycle takes ~24s instead of ~24min. The clock is
// never pinned — every palette state is visited in ORDER, just quickly — which is
// exactly what the Gperf-particles2 correctness proof needs: a NATURAL day->night
// traversal short enough to record on video, and a stress test that makes the
// dropped tod-pingpong's flicker (and any residual TOD bug) unmissable frame-to-
// frame. Value: "1" => the 18000 preset; any float >= 2 => that literal ratio.
// The time-of-day-tick loop reads time-ratio each pass and never rewrites it, so a
// direct write to proc+144 sticks; re-applied periodically because level load /
// time-of-day-setup resets it. Field offset proc+144 = goal 148-4 (time-ratio),
// identical to tod_pin_run. Mutually exclusive with tod.hour (pin wins).
static float s_tod_fast_ratio = 0.0f;

static bool tod_fast_requested() {
  static bool s_parsed = false;
  static bool s_result = false;
  if (s_parsed) {
    return s_result;
  }
  s_parsed = true;
  if (tod_pin_requested()) {
    return false;  // a freeze pin and a fast-forward are contradictory — pin wins.
  }
  char buf[32] = {0};
  if (const char* e = std::getenv("OG_TOD_FAST")) {
    std::strncpy(buf, e, sizeof(buf) - 1);
  }
#if defined(__ANDROID__)
  if (!buf[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.tod.fast", pbuf) > 0) {
      std::strncpy(buf, pbuf, sizeof(buf) - 1);
    }
  }
#endif
  if (!buf[0]) {
    return false;
  }
  float r = 0.0f;
  if (std::sscanf(buf, "%f", &r) < 1) {
    return false;
  }
  if (r == 1.0f) {
    s_tod_fast_ratio = 18000.0f;  // preset: the game's *time-of-day-fast* rate.
  } else if (r >= 2.0f) {
    s_tod_fast_ratio = r;  // explicit ratio (e.g. 36000 = 2x-fast, for tuning).
  } else {
    return false;  // < 2 and != 1 would stall/near-freeze the clock — reject.
  }
  s_result = true;
  return true;
}

static u64 tod_fast_run() {
  u32 tod = intern_from_c("*time-of-day-proc*")->value;
  if (tod == 0 || tod == (u32)s7.offset || tod >= (u32)(EE_MAIN_MEM_SIZE - 64)) {
    return 0;
  }
  u32 proc = 0;
  std::memcpy(&proc, g_ee_main_mem + tod, 4);
  if (proc < 0x10000u || proc == (u32)s7.offset || (proc & OFFSET_MASK) != 4 ||
      proc >= (u32)(EE_MAIN_MEM_SIZE - 256)) {
    return 0;
  }
  float ratio = s_tod_fast_ratio;
  std::memcpy(g_ee_main_mem + proc + 144, &ratio, 4);  // time-ratio (goal 148 - 4)
  static bool s_first = true;
  if (s_first) {
    s_first = false;
    float rb = 0.0f;
    std::memcpy(&rb, g_ee_main_mem + proc + 144, 4);
    printf("TOD-FAST ratio=%.0f proc=%x (ppointer=%x) readback=%.0f\n", ratio, proc, tod, rb);
    fflush(stdout);
  }
  return 0;
}

void tod_fast_maybe() {
  if (!tod_fast_requested()) {
    return;
  }
  // Re-apply periodically (not one-shot): level load / time-of-day-setup resets
  // time-ratio back to the slow 300 rate, so re-write the fast ratio every ~45
  // dispatch passes to HOLD the fast clock through the capture.
  static int s_ctr = 0;
  if ((s_ctr++ % 45) != 0) {
    return;
  }
  u32 tod = intern_from_c("*time-of-day-proc*")->value;
  if (tod < 0x10000u || tod == (u32)s7.offset || tod >= (u32)(EE_MAIN_MEM_SIZE - 8)) {
    return;
  }
  u32 proc = 0;
  std::memcpy(&proc, g_ee_main_mem + tod, 4);
  if (proc < 0x10000u || proc == (u32)s7.offset || (proc & OFFSET_MASK) != 4 ||
      proc >= (u32)(EE_MAIN_MEM_SIZE - 256)) {
    return;
  }
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  static Ptr<Function> s_fn;  // trampoline allocated once
  if (s_fn.offset == 0) {
    s_fn = make_function_from_c((void*)tod_fast_run, false);
  }
  ListenerFunction->value = s_fn.offset;
  static bool s_logged = false;
  if (!s_logged) {
    s_logged = true;
    lg::info("[TOD-FAST] armed ratio={} (re-applying periodically; clock ADVANCES, not pinned)",
             s_tod_fast_ratio);
  }
}

// ─── ECO PHYSICS TRACER (Geco-spheres TEMPORARY arm64-NaN diagnostic) ────────────
// Env OG_ECO_TRACE / Android prop debug.opengoal.eco.trace = "1" — OFF by default.
// Per-dispatch dump of the LAST eco pickup spawned by the eco-spawn hook (its
// ppointer stashed in s_eco_trace_pp). Prints one line of physics state so we can
// see which field first becomes NaN on arm64. Plain printf, like the SPART probes.
// Field offsets are quoted from decompiler/config/jak1/all-types.gc :offset-assert:
//   process-drawable.root         :offset-assert 112   (collide-shape-moving)
//   collectable.base              :offset-assert 208   (vector :inline)
//   collectable.flags             :offset-assert 256   (collectable-flags = uint32)
//   trs.trans (via trsqv<-trsq<-trs) :offset-assert 16  (vector :inline)
//   trsqv.transv                  :offset-assert 64    (vector :inline)
//   collide-shape.root-prim       :offset-assert 160   (collide-shape-prim)
//   collide-shape-moving.local-normal :offset-assert 320 (vector :inline)
//   collide-shape-moving.dynam    :offset-assert 436   (dynamics)
//   collide-shape-prim.prim-core  :offset-assert 16 + collide-prim-core.world-sphere :offset-assert 0
//   dynamics.gravity              :offset-assert 16    (vector :inline)
// Reading a GOAL field from a boxed basic = g_ee_main_mem + basic + (offset - 4).
static bool eco_trace_requested() {
  char buf[16] = {0};
  if (const char* e = std::getenv("OG_ECO_TRACE")) {
    std::strncpy(buf, e, sizeof(buf) - 1);
  }
#if defined(__ANDROID__)
  if (!buf[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.eco.trace", pbuf) > 0) {
      std::strncpy(buf, pbuf, sizeof(buf) - 1);
    }
  }
#endif
  return buf[0] == '1';
}

void eco_trace_maybe() {
  // Gate read once and cache (same pattern as eco_spawn_requested).
  static int s_on = -1;
  if (s_on < 0) {
    s_on = eco_trace_requested() ? 1 : 0;
  }
  if (s_on == 0) {
    return;
  }
  if (s_eco_trace_pp == 0) {
    return;
  }
  static int s_count = 0;
  if (s_count >= 20000) {
    return;
  }

  // s_eco_trace_pp is a RAW (pointer process): load the process basic at it (no -4).
  u32 pp = s_eco_trace_pp;
  if (pp >= (u32)(EE_MAIN_MEM_SIZE - 4)) {
    return;
  }
  u32 proc = 0;
  std::memcpy(&proc, g_ee_main_mem + pp, 4);
  if (proc == 0 || proc == (u32)s7.offset || proc >= (u32)(EE_MAIN_MEM_SIZE - 320)) {
    return;
  }

  // root = collide-shape-moving basic (process-drawable.root @ 112).
  u32 root = 0;
  std::memcpy(&root, g_ee_main_mem + proc + (112 - 4), 4);
  if (root == 0 || root == (u32)s7.offset || root >= (u32)(EE_MAIN_MEM_SIZE - 440)) {
    return;
  }

  // trans @ 16, transv @ 64, local-normal @ 320 (all vector :inline in root).
  float trans[4], transv[4], lnorm[4];
  std::memcpy(trans, g_ee_main_mem + root + (16 - 4), 16);
  std::memcpy(transv, g_ee_main_mem + root + (64 - 4), 16);
  std::memcpy(lnorm, g_ee_main_mem + root + (320 - 4), 16);

  // root-prim @ 160 (collide-shape-prim basic) -> prim-core @ 16 -> world-sphere @ 0.
  u32 rprim = 0;
  std::memcpy(&rprim, g_ee_main_mem + root + (160 - 4), 4);
  if (rprim == 0 || rprim == (u32)s7.offset || rprim >= (u32)(EE_MAIN_MEM_SIZE - 32)) {
    return;
  }
  float ws[4];
  // world-sphere = prim + (16 - 4) + 16 = prim + (16 + 16 - 4).
  std::memcpy(ws, g_ee_main_mem + rprim + (16 + 16 - 4), 16);

  // dynam @ 436 (dynamics basic) -> gravity @ 16 (vector :inline).
  u32 dynam = 0;
  std::memcpy(&dynam, g_ee_main_mem + root + (436 - 4), 4);
  if (dynam == 0 || dynam == (u32)s7.offset || dynam >= (u32)(EE_MAIN_MEM_SIZE - 32)) {
    return;
  }
  float grav[4];
  std::memcpy(grav, g_ee_main_mem + dynam + (16 - 4), 16);

  // collectable.flags @ 256 (uint32), collectable.base @ 208 (vector :inline), y = +4.
  u32 flags = 0;
  std::memcpy(&flags, g_ee_main_mem + proc + (256 - 4), 4);
  float base_y = 0.f;
  std::memcpy(&base_y, g_ee_main_mem + proc + (208 - 4) + 4, 4);

  s_count++;
  printf(
      "ECO-TRACE pp=%x proc=%x trans=%g,%g,%g transv=%g,%g,%g ws=%g,%g,%g,%g lnorm=%g,%g,%g "
      "grav=%g,%g,%g base_y=%g flags=%x\n",
      pp, proc, trans[0], trans[1], trans[2], transv[0], transv[1], transv[2], ws[0], ws[1], ws[2],
      ws[3], lnorm[0], lnorm[1], lnorm[2], grav[0], grav[1], grav[2], base_y, flags);
  fflush(stdout);
}

// ─── ECHO-INTRO (new-game intro cinematic) deterministic warp ───────────────────
// Env OG_ECHO_INTRO / Android prop debug.opengoal.echo.intro — OFF by default.
// TEMPORARY arm64/Android diagnostic. Reaches the NEW-GAME intro cinematic
// DIRECTLY (bypassing title-menu navigation) by replaying the GOAL form that the
// menu's "New Game" / progress.gc fire:
//   (initialize! *game-info* 'game (the-as game-save #f) "intro-start")
// Modeled EXACTLY on f1_maybe_warp_to_geyser above (same gate/readiness/tick-delay
// /listener-function trampoline pattern); kept fully INDEPENDENT of F1-WARP (own
// prop/env, own s_done). x86 is unaffected: the body only runs when armed.
static bool echo_intro_warp_requested() {
  if (std::getenv("OG_ECHO_INTRO")) {
    return true;
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.echo.intro", buf) > 0 && buf[0] == '1') {
    return true;
  }
#endif
  return false;
}

// The warp body — invoked BY THE KERNEL as *listener-function* (same context
// f1_warp_run runs in), so it executes with a live current process on a real
// process stack: the context `initialize!` -> process-spawn require. GOAL regs are
// NOT preserved across the make_function_from_c trampoline, so re-read everything
// and pass pp explicitly to the _call_goal8 trampoline.
static u64 echo_intro_warp_run() {
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    lg::warn("[ECHO-INTRO-WARP] run: *game-info* not ready");
    return 0;
  }
  // Resolve initialize! (method id 9 of game-info) the same way call_method_of_type
  // does: gi_type = type tag word before field-0; the method table starts at
  // type+16 (Type::new_method) with 4-byte Ptr<Function> entries, so
  // get_method(9) = *(u32*)(type + 16 + 9*4). (game-info-h.gc:168-169 — basic
  // methods 0-8, initialize! is the first custom method = id 9.)
  Ptr<Type> gi_type(*Ptr<u32>(gi - 4));  // basic: type tag is the word before field-0
  u32 init_fn = gi_type->get_method(9 /*initialize!*/).offset;
  if (init_fn == 0 || init_fn == (u32)s7.offset) {
    lg::warn("[ECHO-INTRO-WARP] initialize! (method 9) not bound; warp aborted");
    return 0;
  }
  u32 lp = intern_from_c("*listener-process*")->value;
  // (initialize! *game-info* 'game (the-as game-save #f) "intro-start")
  u64 args[8] = {gi,
                 intern_from_c("game").offset,    // the 'game symbol
                 (u64)s7.offset,                  // (the-as game-save #f)
                 make_string_from_c("intro-start"),
                 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + init_fn), args, 0, (u64)lp,
                                  (u64)s7.offset, g_ee_main_mem);
  lg::info("[ECHO-INTRO-WARP] initialize! 'game intro-start -> #x{:x}", (u32)r);
  return r;
}

void echo_intro_warp_maybe() {
  static bool s_done = false;
  if (s_done) {
    return;
  }
  if (!echo_intro_warp_requested()) {
    return;
  }
  // Readiness: *game-info* bound to a real boxed basic (engine far enough along
  // that initialize! can spawn). Same gate shape as f1_maybe_warp_to_geyser.
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  // Settle margin after readiness — let the title attract fully come up before the
  // intro warp fires. Tunable via OG_ECHO_INTRO_DELAY (kernel-dispatch ticks).
  int delay = 600;
  if (const char* d = std::getenv("OG_ECHO_INTRO_DELAY")) {
    delay = atoi(d);
  }
  static int s_ticks = 0;
  if (s_ticks++ < delay) {
    return;
  }
  s_done = true;

  // Hand the warp to the kernel's *listener-function* slot — kernel-dispatcher runs
  // it via reset-and-call INSIDE the dispatch frame with a live process context,
  // exactly as f1_maybe_warp_to_geyser does.
  Ptr<Function> warp_fn = make_function_from_c((void*)echo_intro_warp_run, false);
  ListenerFunction->value = warp_fn.offset;
  lg::info("[ECHO-INTRO-WARP] armed *listener-function* = #x{:x}; kernel will run the warp in-context",
           warp_fn.offset);
}

// ─── Gcrash-mouche: buzzer scout-fly pickup HUD-FX repro ────────────────────────
// Env OG_MOUCHE_FX / Android prop debug.opengoal.mouche.fx — OFF by default.
//
// Reproduces, on the GOAL kernel thread via *listener-function*, the buzzer
// scout-fly pickup "fly-to-HUD" effect (collectables.gc:1273-1274, the buzzer
// `pickup` state):
//   (let ((v1-18 (manipy-spawn (-> self root trans) #f *buzzer-sg* #f :to *entity-pool*)))
//     (send-event (ppointer->process v1-18) 'become-hud-object
//                 (ppointer->process (-> *hud-parts* buzzers))))
// On desktop x86 this does NOT crash (gmouche_x86.sh oracle, 3 spawns, kernel keeps
// ticking). On Android the become-hud-object path forces use-mercneric=1 ->
// draw-bones-generic-merc, whose generic-merc family is noop-bound on arm64
// (mips2c_table_jak1_arm64.cpp kSet) -> the DMA `base` cursor collapses -> the
// owner's deterministic buzzer-collect crash. The device has no goalc listener
// socket (android_runtime_full.cpp registers Deci2Server with NO listener), and
// the flies need platforming cpad_inject cannot do, so this hook drives the EXACT
// FX the x86 oracle measures so the crash can be reproduced + a fix verified.
//
// manipy-spawn expands to: get-process (dead-pool method 14) -> activate
// (process-tree method 9) -> run-function-in-process(manipy-init,...) ->
// (-> new-proc ppointer). become-hud-object's handler (generic-obs.gc:162) just
// calls convert-to-hud-object(self, hud); we call that directly with pp=manipy
// (enter-state's `(!= current-process pp)` branch sets-to-run + returns — no
// non-local exit, identical to the real event delivery). All runs with a live pp
// because the kernel runs this as *listener-function* via reset-and-call.
static u32 mouche_read32(u32 goal_addr) {
  u32 v = 0;
  if (goal_addr != 0 && goal_addr < (u32)(EE_MAIN_MEM_SIZE - 4)) {
    std::memcpy(&v, g_ee_main_mem + goal_addr, 4);
  }
  return v;
}

static int s_mouche_fire_n = 0;

static u64 mouche_fx_run() {
  const u32 fnull = (u32)s7.offset;
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == fnull) { printf("MOUCHE-SKIP reason=target-#f\n"); fflush(stdout); return 0; }
  u32 buzzer_sg = intern_from_c("*buzzer-sg*")->value;
  if (buzzer_sg == 0 || buzzer_sg == fnull) { printf("MOUCHE-SKIP reason=buzzer-sg-#f\n"); fflush(stdout); return 0; }
  u32 entity_pool = intern_from_c("*entity-pool*")->value;
  u32 dead_pool = intern_from_c("*default-dead-pool*")->value;
  u32 manipy_type = intern_from_c("manipy")->value;
  u32 manipy_init = intern_from_c("manipy-init")->value;
  u32 hud_parts = intern_from_c("*hud-parts*")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (entity_pool == 0 || entity_pool == fnull || dead_pool == 0 || dead_pool == fnull ||
      manipy_type == 0 || manipy_type == fnull || manipy_init == 0 || manipy_init == fnull ||
      hud_parts == 0 || hud_parts == fnull) {
    printf("MOUCHE-SKIP reason=env-not-ready ep=#x%x dp=#x%x mt=#x%x mi=#x%x hp=#x%x\n",
           entity_pool, dead_pool, manipy_type, manipy_init, hud_parts);
    fflush(stdout);
    return 0;
  }

  // The crash only fires when (-> *hud-parts* buzzers) is non-#f (else
  // convert-to-hud-object no-ops and the manipy draws as a normal WORLD merc,
  // which is real on arm64). init-target -> activate-hud spawns the buzzers HUD
  // during the warp; force it once if it is somehow absent.
  u32 buzzers_pp = mouche_read32(hud_parts + 16);  // hud-parts buzzers @ +16
  if (buzzers_pp == 0 || buzzers_pp == fnull) {
    u32 ah = intern_from_c("activate-hud")->value;
    if (ah != 0 && ah != fnull) {
      u64 ah_args[8] = {tgt, 0, 0, 0, 0, 0, 0, 0};
      _call_goal8_asm_systemv((void*)(g_ee_main_mem + ah), ah_args, 0, (u64)lp, (u64)s7.offset,
                              g_ee_main_mem);
      buzzers_pp = mouche_read32(hud_parts + 16);
      printf("MOUCHE-HUD forced activate-hud -> buzzers=#x%x\n", buzzers_pp);
      fflush(stdout);
    }
  }
  // (ppointer->process (-> *hud-parts* buzzers)) : deref ppointer[0] then .self (@28)
  u32 hud_proc = fnull;
  if (buzzers_pp != 0 && buzzers_pp != fnull) {
    u32 hud_obj = mouche_read32(buzzers_pp);
    if (hud_obj != 0 && hud_obj != fnull) {
      hud_proc = mouche_read32(hud_obj + 28);
    }
  }

  // (-> *target* root trans): target root(control) @ +108, trans @ +12 (proven by F1-WARP).
  u32 root_ptr = mouche_read32(tgt + 108);
  u32 trans_vec = (root_ptr != 0 && root_ptr != fnull) ? (root_ptr + 12) : 0;
  if (trans_vec == 0) { printf("MOUCHE-SKIP reason=no-trans\n"); fflush(stdout); return 0; }

  // get-process(*default-dead-pool*, manipy, #x4000) — dead-pool method 14
  u32 dp_type = mouche_read32(dead_pool - 4);
  u64 npr = call_method_of_type_arg2(dead_pool, Ptr<Type>(dp_type), 14, manipy_type, 0x4000);
  u32 new_proc = (u32)npr;
  if (new_proc == 0 || new_proc == fnull) { printf("MOUCHE-SKIP reason=get-process-fail\n"); fflush(stdout); return 0; }

  // activate(new_proc, *entity-pool*, 'manipy, *scratch-memory-top*) — process-tree method 9
  Ptr<Type> mt(manipy_type);
  u32 activate_fn = mt->get_method(9).offset;
  u32 manipy_sym = intern_from_c("manipy").offset;  // the SYMBOL object 'manipy
  u64 act_args[8] = {new_proc, entity_pool, manipy_sym, 0x70004000u /*scratch-memory-top*/, 0, 0, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + activate_fn), act_args, 0, (u64)lp,
                          (u64)s7.offset, g_ee_main_mem);

  // run-function-in-process(new_proc, manipy-init, trans, #f, *buzzer-sg*, #f)
  u32 run_fn = intern_from_c("run-function-in-process")->value;
  u64 run_args[8] = {new_proc, manipy_init, trans_vec, (u64)fnull, buzzer_sg, (u64)fnull, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + run_fn), run_args, 0, (u64)lp,
                          (u64)s7.offset, g_ee_main_mem);

  // become-hud-object: convert-to-hud-object(manipy, hud) with pp=manipy. This is
  // verbatim what the manipy-idle 'become-hud-object event handler does. It sets
  // dma-add-func=dma-add-process-drawable-hud and (go hud-collecting), so the next
  // render draws the manipy through draw-bones-hud -> generic-merc (the crash).
  u32 cvt_fn = intern_from_c("convert-to-hud-object")->value;
  s_mouche_fire_n++;
  if (cvt_fn != 0 && cvt_fn != fnull && hud_proc != fnull) {
    u64 cvt_args[8] = {new_proc, hud_proc, 0, 0, 0, 0, 0, 0};
    _call_goal8_asm_systemv((void*)(g_ee_main_mem + cvt_fn), cvt_args, 0, (u64)new_proc,
                            (u64)s7.offset, g_ee_main_mem);
    printf("MOUCHE-FIRE #%d proc=#x%x hud=#x%x trans=#x%x (HUD-merc path armed)\n",
           s_mouche_fire_n, new_proc, hud_proc, trans_vec);
  } else {
    printf("MOUCHE-FIRE #%d proc=#x%x hud=#f (NO hud -> world-merc, NOT the crash path)\n",
           s_mouche_fire_n, new_proc);
  }
  fflush(stdout);
  return new_proc;
}

// ── REAL buzzer collect (full lifecycle, not just the FX) ──────────────────────
// Spawns a real `buzzer` at Jak's position the EXACT way a crate's drop-pickup ->
// birth-pickup-at-point does (get-process *default-dead-pool* buzzer #x4000 ->
// activate (method 9) -> run-now-in-process buzzer-init-by-other(trans, vel, fact,
// entity)). The buzzer lands in `wait` at Jak, runs its `animate` (group-buzzer-effect
// 3D sparticle wings + optional victory-anim spool), and — because Jak is right on it
// — the collide-shape touch fires -> (go-virtual pickup #f ...) -> the FULL pickup
// :code (level-hint-spawn voice/STR, manipy fly-to-HUD FX, task bookkeeping). This
// exercises everything a real scout-fly collect does, which the FX-only path did not.
static u64 mouche_buzzer_run() {
  using namespace jak1_symbols;  // FIX_SYM_GLOBAL_HEAP
  const u32 fnull = (u32)s7.offset;
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == fnull) { printf("MOUCHE-BUZZ-SKIP reason=target-#f\n"); fflush(stdout); return 0; }
  u32 buzzer_type = intern_from_c("buzzer")->value;
  u32 buzzer_init = intern_from_c("buzzer-init-by-other")->value;
  u32 entity_pool = intern_from_c("*entity-pool*")->value;
  u32 dead_pool = intern_from_c("*default-dead-pool*")->value;
  u32 fact_type = intern_from_c("fact-info")->value;
  u32 null_vec = intern_from_c("*null-vector*")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (buzzer_type == 0 || buzzer_type == fnull || buzzer_init == 0 || buzzer_init == fnull ||
      entity_pool == 0 || entity_pool == fnull || dead_pool == 0 || dead_pool == fnull ||
      fact_type == 0 || fact_type == fnull || null_vec == 0 || null_vec == fnull) {
    printf("MOUCHE-BUZZ-SKIP reason=env-not-ready bt=#x%x bi=#x%x dp=#x%x ft=#x%x nv=#x%x\n",
           buzzer_type, buzzer_init, dead_pool, fact_type, null_vec);
    fflush(stdout);
    return 0;
  }

  // fact-info (basic, size 0x28): pickup-type@8, pickup-amount@12, pickup-spawn-amount@16,
  // options@24. C++ addr = obj + (deftype_offset - 4).
  u32 fact = (u32)alloc_heap_object((s7 + FIX_SYM_GLOBAL_HEAP).offset, fact_type, 0x2c, UNKNOWN_PP);
  if (fact == 0 || fact == fnull) { printf("MOUCHE-BUZZ-SKIP reason=fact-alloc-fail\n"); fflush(stdout); return 0; }
  // pickup-amount encodes the scout-fly task: (game-task training-buzzer) = 95 is the
  // real Geyser Rock ('training) scout-fly task, so the pickup :code's get-task-control /
  // close-specific-task! bookkeeping resolves a VALID task (a fresh #x4000 fact would
  // otherwise read task 1 -> "get-task-control received invalid task 1/#f" and hang —
  // a harness artifact, not the buzzer bug). buzzer-init-by-other copies arg2's
  // pickup-spawn-amount into the buzzer's fact pickup-amount.
  { int32_t v = 8;       std::memcpy(g_ee_main_mem + fact + 4, &v, 4); }   // pickup-type = buzzer
  { float v = 95.0f;     std::memcpy(g_ee_main_mem + fact + 8, &v, 4); }   // pickup-amount = training-buzzer
  { float v = 95.0f;     std::memcpy(g_ee_main_mem + fact + 12, &v, 4); }  // pickup-spawn-amount = training-buzzer
  { u32 v = 0;           std::memcpy(g_ee_main_mem + fact + 20, &v, 4); }  // options

  u32 root_ptr = mouche_read32(tgt + 108);
  u32 jak_pos = (root_ptr != 0 && root_ptr != fnull) ? (root_ptr + 12) : 0;
  if (jak_pos == 0) { printf("MOUCHE-BUZZ-SKIP reason=no-trans\n"); fflush(stdout); return 0; }

  u32 dp_type = mouche_read32(dead_pool - 4);
  u64 bpr = call_method_of_type_arg2(dead_pool, Ptr<Type>(dp_type), 14, buzzer_type, 0x4000);
  u32 buzzer_proc = (u32)bpr;
  if (buzzer_proc == 0 || buzzer_proc == fnull) { printf("MOUCHE-BUZZ-SKIP reason=get-process-fail\n"); fflush(stdout); return 0; }

  Ptr<Type> bt(buzzer_type);
  u32 activate_fn = bt->get_method(9).offset;
  u32 buzzer_sym = intern_from_c("buzzer").offset;
  u64 act_args[8] = {buzzer_proc, entity_pool, buzzer_sym, 0x70004000u, 0, 0, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + activate_fn), act_args, 0, (u64)lp, (u64)s7.offset, g_ee_main_mem);

  // run-now-in-process(buzzer, buzzer-init-by-other, jak_pos, *null-vector*, fact, #f)
  u32 run_fn = intern_from_c("run-function-in-process")->value;
  u64 run_args[8] = {buzzer_proc, buzzer_init, jak_pos, null_vec, fact, (u64)fnull, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + run_fn), run_args, 0, (u64)lp, (u64)s7.offset, g_ee_main_mem);

  s_mouche_fire_n++;
  u32 b_status = mouche_read32(buzzer_proc + 36);  // process status @ +36
  u32 b_name = mouche_read32(buzzer_proc + 4);     // process-tree name @ +4
  printf("MOUCHE-BUZZ #%d proc=#x%x fact=#x%x pos=#x%x status=#x%x name=#x%x (real buzzer spawned at Jak)\n",
         s_mouche_fire_n, buzzer_proc, fact, jak_pos, b_status, b_name);
  fflush(stdout);
  return buzzer_proc;
}

void mouche_maybe_fire() {
  static bool s_checked = false, s_enabled = false, s_buzz = false;
  if (!s_checked) {
    s_checked = true;
    if (std::getenv("OG_MOUCHE_FX")) {
      s_enabled = true;
    }
    if (std::getenv("OG_MOUCHE_BUZZ")) {
      s_enabled = true;
      s_buzz = true;
    }
#if defined(__ANDROID__)
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.mouche.fx", buf) > 0 && buf[0] == '1') {
      s_enabled = true;
    }
    char bz[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.mouche.buzz", bz) > 0 && bz[0] == '1') {
      s_enabled = true;
      s_buzz = true;
    }
#endif
  }
  if (!s_enabled) {
    return;
  }

  int count = 2, gap = 240, settle = 300;
  if (const char* c = std::getenv("OG_MOUCHE_COUNT")) count = atoi(c);
  if (const char* g = std::getenv("OG_MOUCHE_GAP")) gap = atoi(g);
  if (const char* s = std::getenv("OG_MOUCHE_SETTLE")) settle = atoi(s);

  static int s_fires = 0;
  if (s_fires >= count) {
    return;
  }
  // readiness: *target* alive + buzzer art loaded
  u32 tgt = intern_from_c("*target*")->value;
  u32 bsg = intern_from_c("*buzzer-sg*")->value;
  if (tgt == 0 || tgt == (u32)s7.offset || bsg == 0 || bsg == (u32)s7.offset) {
    return;
  }
  static int s_settle_ticks = 0;
  if (s_settle_ticks++ < settle) {
    return;
  }
  // only re-arm once the kernel has consumed the previous *listener-function*
  if (ListenerFunction->value != s7.offset) {
    return;
  }
  static int s_gap_ticks = 0;
  if (s_gap_ticks++ < gap) {
    return;
  }
  s_gap_ticks = 0;

  static u32 s_fx_fn = 0;
  if (s_fx_fn == 0) {
    s_fx_fn = make_function_from_c(s_buzz ? (void*)mouche_buzzer_run : (void*)mouche_fx_run, false)
                  .offset;
  }
  ListenerFunction->value = s_fx_fn;
  s_fires++;
  printf("MOUCHE-ARM fire %d/%d mode=%s (settle=%d gap=%d)\n", s_fires, count,
         s_buzz ? "buzzer" : "fx", settle, gap);
  fflush(stdout);
}

// ─── Gdeath-crash: deterministic death/respawn repro + verify ───────────────────
// Env OG_DIE / Android prop debug.opengoal.die — OFF by default. Forces Jak to die
// N times so the arm64 death/respawn crash can be reproduced and ">=5 crash-free
// deaths" proven. Modeled EXACTLY on mouche_maybe_fire / echo_intro_warp (same
// listener-function trampoline + readiness gate + tick cadence). x86 is unaffected
// unless armed. Mode (env OG_DIE_MODE / prop debug.opengoal.die.mode):
//   "respawn"      -> (initialize! *game-info* 'die #f #f): respawn/loader path only.
//   "endlessfall"  -> send-event 'attack-invinc mode='endlessfall (fall death; DEFAULT).
//   "drown-death"  -> send-event 'attack-invinc mode='drown-death (drown death).
//   <other symbol> -> send-event 'attack-invinc with that attack-mode symbol.
// The death :code (target-death.gc:911-914) always ends in
//   (initialize! game 'dead) -> kill+respawn target -> init-target -> target-continue,
// so EVERY mode exercises the common respawn/loader path; the mode selects only the
// preceding animation branch (endlessfall/drown vs. respawn-only).
static char s_die_event_mode[64] = "endlessfall";

static bool die_requested() {
  if (std::getenv("OG_DIE")) {
    return true;
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.die", buf) > 0 && buf[0] == '1') {
    return true;
  }
#endif
  return false;
}

// TRIGGER 1 — respawn-only. Replays the debug "New Life" menu form
// (default-menu.gc:2271) (initialize! *game-info* 'die #f #f), which falls through
// to the mode='play respawn reload. Same get_method(9)+_call_goal8 pattern as the
// echo-intro hook's initialize! call. Runs as *listener-function* (live pp).
static u64 die_respawn_run() {
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    lg::warn("[GDEATH] respawn: *game-info* not ready");
    return 0;
  }
  Ptr<Type> gi_type(*Ptr<u32>(gi - 4));  // basic: type tag is the word before field-0
  u32 init_fn = gi_type->get_method(9).offset;  // initialize!
  u32 lp = intern_from_c("*listener-process*")->value;
  u64 args[8] = {gi, intern_from_c("die").offset, (u64)s7.offset, (u64)s7.offset, 0, 0, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + init_fn), args, 0, (u64)lp, (u64)s7.offset,
                          g_ee_main_mem);
  printf("GDEATH-FIRE mode=respawn (initialize! *game-info* 'die)\n");
  fflush(stdout);
  return 0;
}

// TRIGGER 2 — full death state via the engine's own force-death event
// (logic-target.gc:674): (send-event *target* 'attack-invinc #f
// (static-attack-info ((mode <mode>)))). attack-info + event-message-block are
// `structure`s (NO type tag) -> raw kmalloc + RAW field offsets (NOT the basic -4
// rule). Routes target-hit -> (go target-death <mode>); endlessfall/drown-death are
// handled death branches. Runs as *listener-function* (live pp).
static u64 die_event_run() {
  const u32 fnull = (u32)s7.offset;
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == fnull) {
    printf("GDEATH-SKIP reason=target-#f\n");
    fflush(stdout);
    return 0;
  }
  u32 lp = intern_from_c("*listener-process*")->value;
  u32 sef = intern_from_c("send-event-function")->value;
  // "movie" -> the generic death-MOVIE (else) branch in target-death.gc:872-910
  // (blerc 'blend-shape + pov-camera death spool — the prime arm64 merc suspect).
  // That branch is reached only when health<=0 forces (go target-death <mode>) for a
  // mode NOT explicitly handled in the :code case; 'tar lands in the else branch
  // (case at target-death.gc:873-874). So for "movie" we zero Jak's health first
  // (target.fact @ proc-drawable off 144 -> fact-info-target.health @ off 64; both
  // basic, so C++ addr = field_off - 4) and send the attack with mode='tar, which
  // target-hit's health<=0 guard (target-death.gc:613) routes to (go target-death 'tar).
  bool movie = (std::strcmp(s_die_event_mode, "movie") == 0);
  const char* mode_name = movie ? "tar" : s_die_event_mode;
  u32 mode_sym = intern_from_c(mode_name).offset;
  if (sef == 0 || sef == fnull || mode_sym == 0) {
    printf("GDEATH-SKIP reason=env sef=#x%x mode=#x%x\n", sef, mode_sym);
    fflush(stdout);
    return 0;
  }
  if (movie) {
    u32 fact_ptr = 0;
    std::memcpy(&fact_ptr, g_ee_main_mem + tgt + 140, 4);  // (-> target fact)
    if (fact_ptr != 0 && fact_ptr != fnull && fact_ptr < (u32)(EE_MAIN_MEM_SIZE - 64)) {
      float z = 0.0f;
      std::memcpy(g_ee_main_mem + fact_ptr + 60, &z, 4);  // (-> target fact health) = 0.0
      printf("GDEATH-MOVIE zeroed health fact=#x%x\n", fact_ptr);
    }
  }
  // attack-info (structure, size 0x68): mask@64, mode@68 (RAW offsets).
  u32 atk = (u32)kmalloc(kglobalheap, 0x68, KMALLOC_MEMSET, "die-atk").offset;
  if (atk == 0) {
    printf("GDEATH-SKIP reason=atk-alloc\n");
    fflush(stdout);
    return 0;
  }
  { u32 v = 0x20; std::memcpy(g_ee_main_mem + atk + 64, &v, 4); }       // mask = (attack-mask mode)
  { u32 v = mode_sym; std::memcpy(g_ee_main_mem + atk + 68, &v, 4); }   // mode = <mode-sym>
  // event-message-block (structure, size 0x48): from@4, num-params@8, message@12,
  // param[i]@16+8*i (RAW offsets).
  u32 blk = (u32)kmalloc(kglobalheap, 0x48, KMALLOC_MEMSET, "die-evt").offset;
  if (blk == 0) {
    printf("GDEATH-SKIP reason=blk-alloc\n");
    fflush(stdout);
    return 0;
  }
  { u32 v = tgt; std::memcpy(g_ee_main_mem + blk + 4, &v, 4); }         // from = *target*
  { s32 v = 2; std::memcpy(g_ee_main_mem + blk + 8, &v, 4); }          // num-params = 2
  { u32 v = intern_from_c("attack-invinc").offset;
    std::memcpy(g_ee_main_mem + blk + 12, &v, 4); }                     // message = 'attack-invinc
  { u64 v = (u64)fnull; std::memcpy(g_ee_main_mem + blk + 16, &v, 8); } // param0 = #f (touching-shapes)
  { u64 v = (u64)atk; std::memcpy(g_ee_main_mem + blk + 24, &v, 8); }   // param1 = attack-info
  u64 args[8] = {tgt, blk, 0, 0, 0, 0, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + sef), args, 0, (u64)lp, (u64)s7.offset,
                          g_ee_main_mem);
  printf("GDEATH-FIRE mode=%s (send-event *target* 'attack-invinc) atk=#x%x blk=#x%x\n",
         s_die_event_mode, atk, blk);
  fflush(stdout);
  return 0;
}

void die_maybe_fire() {
  static bool s_checked = false, s_enabled = false, s_respawn = false;
  static int s_count = 6;
  if (!s_checked) {
    s_checked = true;
    if (die_requested()) {
      s_enabled = true;
    }
    const char* m = std::getenv("OG_DIE_MODE");
#if defined(__ANDROID__)
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.die.mode", pbuf) > 0 && pbuf[0]) {
      m = pbuf;
    }
#endif
    if (m && m[0]) {
      std::strncpy(s_die_event_mode, m, sizeof(s_die_event_mode) - 1);
      s_die_event_mode[sizeof(s_die_event_mode) - 1] = 0;
    }
    if (std::strcmp(s_die_event_mode, "respawn") == 0) {
      s_respawn = true;
    }
    if (const char* c = std::getenv("OG_DIE_COUNT")) {
      s_count = atoi(c);
    }
#if defined(__ANDROID__)
    char cbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.die.count", cbuf) > 0 && cbuf[0]) {
      s_count = atoi(cbuf);
    }
#endif
    if (s_count < 1) {
      s_count = 1;
    }
  }
  if (!s_enabled) {
    return;
  }

  int settle = 600, gap = 480;
  if (const char* s = std::getenv("OG_DIE_SETTLE")) settle = atoi(s);
  if (const char* g = std::getenv("OG_DIE_GAP")) gap = atoi(g);

  static int s_fires = 0;
  if (s_fires >= s_count) {
    return;
  }
  // readiness: *target* alive AND game in 'play, so the respawn branch runs and we
  // never fire during a cutscene/menu/respawn transition (when *target* is #f).
  // game-info `mode` is at deftype offset 4 -> C++ addr gi+0 (basic -4 rule).
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == (u32)s7.offset) {
    return;
  }
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4) {
    return;
  }
  u32 gi_mode = 0;
  std::memcpy(&gi_mode, g_ee_main_mem + gi + 0, 4);
  if (gi_mode != intern_from_c("play").offset) {
    return;
  }
  static int s_settle_ticks = 0;
  if (s_settle_ticks++ < settle) {
    return;
  }
  // only re-arm once the kernel consumed the previous *listener-function*
  if (ListenerFunction->value != s7.offset) {
    return;
  }
  static int s_gap_ticks = 0;
  if (s_gap_ticks++ < gap) {
    return;
  }
  s_gap_ticks = 0;

  static u32 s_fn = 0;
  if (s_fn == 0) {
    s_fn = make_function_from_c(s_respawn ? (void*)die_respawn_run : (void*)die_event_run, false)
               .offset;
  }
  ListenerFunction->value = s_fn;
  s_fires++;
  printf("GDEATH-ARM fire %d/%d mode=%s (settle=%d gap=%d)\n", s_fires, s_count,
         s_respawn ? "respawn" : s_die_event_mode, settle, gap);
  fflush(stdout);
}

// ─── TARGET-DRIVE (Gcrash-swamp-load debug-only) ────────────────────────────────
// Env-free / Android prop debug.opengoal.target.drive = "<dx> <dz> <pin_y> <stop_z>"
// (RAW EE units, floats OK), OFF by default. Each kernel dispatch, marches *target*
// (Jak) by (dx,dz) in world space (optionally pinning y), stopping at stop_z — so
// SWA.DGO streams in from Jak's REAL position (a position-triggered load, not a
// want-levels replay). Reads/writes *target*'s world trans via the SAME guarded
// EE-memcpy pattern the mouche_/eco_ hooks use: (-> *target* root) @ tgt+108,
// trans @ root+12 (x@+0 y@+4 z@+8, 4-byte floats). Runs on the GOAL kernel thread
// in the dispatch loop (safe to touch EE, like the eco hook). Never armed in the
// shipped APK.
void target_drive_maybe() {
  // Gate: read the prop once per call; disarmed if empty/unset. Sized 128 (not
  // PROP_VALUE_MAX, an Android-only macro) so the x86 desktop build compiles.
  char buf[128] = {0};
#if defined(__ANDROID__)
  if (!(__system_property_get("debug.opengoal.target.drive", buf) > 0 && buf[0])) {
    return;
  }
#else
  if (const char* e = std::getenv("OG_TARGET_DRIVE")) {
    std::strncpy(buf, e, sizeof(buf) - 1);
  }
  if (!buf[0]) {
    return;
  }
#endif

  const u32 fnull = (u32)s7.offset;
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == fnull) {
    return;
  }
  // (-> *target* root) : control/root ptr @ tgt+108 (same read as kmachine.cpp:2002-2004).
  if (tgt >= (u32)(EE_MAIN_MEM_SIZE - 112)) {
    return;
  }
  u32 root_ptr = 0;
  std::memcpy(&root_ptr, g_ee_main_mem + tgt + 108, 4);
  if (root_ptr == 0 || root_ptr == fnull) {
    return;
  }
  // trans vector @ root+12 (world position); guard the whole [x..z+4) span.
  u32 trans_vec = root_ptr + 12;
  if (trans_vec < 0x1000 || trans_vec >= (u32)(EE_MAIN_MEM_SIZE - 16)) {
    return;
  }

  // Parse "<dx> <dz> <pin_y> <stop_z>" (atof, floats OK).
  float dx = 0.f, dz = 0.f, pin_y = 0.f, stop_z = 0.f;
  int n = std::sscanf(buf, "%f %f %f %f", &dx, &dz, &pin_y, &stop_z);
  if (n < 4) {
    return;  // need all four
  }

  // Read current x,y,z floats from trans_vec.
  float x = 0.f, y = 0.f, z = 0.f;
  std::memcpy(&x, g_ee_main_mem + trans_vec + 0, 4);
  std::memcpy(&y, g_ee_main_mem + trans_vec + 4, 4);
  std::memcpy(&z, g_ee_main_mem + trans_vec + 8, 4);

  // Determine "past the stop" for the drive direction, then step (or hold).
  bool past = (dz < 0 && z <= stop_z) || (dz > 0 && z >= stop_z);
  if (past) {
    // Hold Jak at the stop: x unchanged, z pinned to stop_z, y optionally pinned.
    z = stop_z;
  } else {
    x = x + dx;
    z = z + dz;
  }
  std::memcpy(g_ee_main_mem + trans_vec + 0, &x, 4);
  std::memcpy(g_ee_main_mem + trans_vec + 8, &z, 4);
  if (pin_y != 0.f) {
    y = pin_y;
    std::memcpy(g_ee_main_mem + trans_vec + 4, &y, 4);
  }

  // Progress trace every 15th call so the harness can track Jak's position.
  static int s_drive_n = 0;
  if ((s_drive_n++ % 15) == 0) {
    printf("TARGET-DRIVE pos=(%.1f %.1f %.1f)\n", x, y, z);
    fflush(stdout);
  }
}

// ─── DIAG FLAGS (Gcrash-swamp-load debug-only) ──────────────────────────────────
// Env-free / Android prop debug.opengoal.diag.norepair, OFF by default. When
// value[0]=='1', arms the gk_android_main signal-handler bypass (via the extern
// "C" setter gk_set_diag_norepair) so the three "repair-and-resume" control
// transfer handlers bail out and the TRUE first swamp-load crash reaches the fatal
// forensic dump instead of being silently masked. On desktop this is a no-op.
void diag_flags_maybe() {
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  bool on = (__system_property_get("debug.opengoal.diag.norepair", buf) > 0 && buf[0] == '1');
  gk_set_diag_norepair(on);
#endif
}

// Gcrash-swamp-load fix: clear *part-group-id-table* slots whose sparticle-launch-group
// object lies in [dst_goal, dst_goal+size) — the level-heap region jak1_work_v3 is about
// to overwrite. Race-free (called synchronously right before the segment memcpy). Prevents
// the arm64 level-thrash dangling-slot crash where lookup-part-group-pointer-by-name
// derefs a name pointer that was overwritten with code.
#if defined(__ANDROID__)
void invalidate_part_groups_in_range(u32 dst_goal, u32 size) {
  if (size == 0) return;
  // A/B toggle: the fix is ON by default; debug.opengoal.partgroup.inval=0 disables it
  // (to reproduce the pre-fix swamp-load crash on the same build). OFF-switch only.
  {
    char ib[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.partgroup.inval", ib) > 0 && ib[0] == '0') {
      return;
    }
  }
  const u32 fnull = (u32)s7.offset;
  u32 tbl = intern_from_c("*part-group-id-table*")->value;
  if (tbl == 0 || tbl == fnull || tbl < 0x1000 || tbl >= (u32)(EE_MAIN_MEM_SIZE - 32)) return;
  u32 len = 0; std::memcpy(&len, g_ee_main_mem + tbl + 4, 4);
  if (len > 1024) len = 1024;
  const u64 lo = dst_goal, hi = (u64)dst_goal + size;
  static int s_inval_logged = 0;
  for (u32 i = 0; i < len; i++) {
    u32 slot_addr = tbl + 16 + i * 4;
    if (slot_addr >= (u32)(EE_MAIN_MEM_SIZE - 4)) break;
    u32 group = 0; std::memcpy(&group, g_ee_main_mem + slot_addr, 4);
    if (group == 0 || group == fnull) continue;
    if ((u64)group >= lo && (u64)group < hi) {
      if (s_inval_logged < 16) { s_inval_logged++;
        printf("PARTGROUP-INVAL slot=%u group=0x%x in [0x%x,0x%llx) -> cleared\n",
               i, group, dst_goal, (unsigned long long)hi); fflush(stdout); }
      u32 zero = 0; std::memcpy(g_ee_main_mem + slot_addr, &zero, 4);
    }
  }
}
#endif

}  // namespace jak1

#if defined(__GNUC__)
#pragma GCC diagnostic pop
#elif defined(__clang__)
#pragma clang diagnostic pop
#endif
