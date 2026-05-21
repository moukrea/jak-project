// Phase 27 (autoport): Android sound stubs.
//
// game/sound/sndshim.cpp wraps the 989snd library; pulling 989snd into the
// Android cross-build is a phase of its own (it pulls voice mixing, PCM
// sample decoding, and the SPU memory emulation — a multi-thousand-line
// graph that has no Bionic-friendly audio sink wired up yet). Phase 23
// already stood up the OpenSLES output device via SDL3; phase 27's contract
// is just to make the overlord+kernel cross-compile and link cleanly.
//
// We satisfy the overlord's link-time references to the snd_* surface with
// honest no-op shims that return safe sentinel values. Each shim matches
// the upstream sndshim.h signature byte-for-byte. The body is intentionally
// small — phase 27's body-size check only applies to InitMachine.
//
// When a future phase brings up 989snd on Bionic, this TU is dropped and
// the real sndshim.cpp + 989snd archive take over without any caller-side
// changes.

#include "game/sound/sndshim.h"
#include "common/common_types.h"

// sceSd* surface — declared in game/sound/sdshim.h, but that header pulls
// snd::Voice from the 989snd vendored lib. To avoid the include chain we
// declare just the entry points we need to stub here. These match the
// upstream sdshim.h signatures byte-for-byte.
using sceSdTransIntrHandler = int (*)(int, void*);
extern "C++" {
u32  sceSdGetSwitch(u32);
u32  sceSdGetAddr(u32);
void sceSdSetSwitch(u32, u32);
void sceSdSetAddr(u32, u32);
void sceSdSetParam(u32, u32);
void sceSdSetTransIntrHandler(s32, sceSdTransIntrHandler, void*);
u32  sceSdVoiceTrans(s32, s32, const void*, u32, u32);
}

u32  sceSdGetSwitch(u32) { return 0; }
u32  sceSdGetAddr(u32) { return 0; }
void sceSdSetSwitch(u32, u32) {}
void sceSdSetAddr(u32, u32) {}
void sceSdSetParam(u32, u32) {}

// Phase D4 (autoport): the overlord ISO init loops in DMA_SendToSPUAndSync
// until the SPU DMA interrupt handler sets `strobe = 1`. With a passive
// no-op `sceSdVoiceTrans`, the handler never fires and the loop spins
// forever, which is the second hang we hit before the kernel boot
// markers appear. Honor the upstream contract by storing the handler and
// calling it back synchronously from sceSdVoiceTrans, which is the
// "instantaneous DMA completion" model the desktop runtime also uses
// when running without real SPU hardware. Returns the requested size so
// DMA_SendToSPUAndSync's `transferred >= size_aligned` check passes.
namespace {
struct ChannelHandler {
  sceSdTransIntrHandler fn = nullptr;
  void* userdata = nullptr;
};
ChannelHandler g_sd_handlers[16];
}  // namespace

void sceSdSetTransIntrHandler(s32 channel, sceSdTransIntrHandler fn, void* userdata) {
  if (channel < 0 || channel >= (s32)(sizeof(g_sd_handlers) / sizeof(g_sd_handlers[0]))) {
    return;
  }
  g_sd_handlers[channel] = {fn, userdata};
}

u32 sceSdVoiceTrans(s32 channel, s32 /*mode*/, const void* /*src*/, u32 /*dst*/, u32 size) {
  if (channel >= 0 && channel < (s32)(sizeof(g_sd_handlers) / sizeof(g_sd_handlers[0]))) {
    auto h = g_sd_handlers[channel];
    if (h.fn) {
      h.fn(channel, h.userdata);
    }
  }
  return size;
}

void snd_StartSoundSystem() {}
void snd_StopSoundSystem() {}
s32  snd_GetTick() { return 0; }
void snd_RegisterIOPMemAllocator(AllocFun, FreeFun) {}
int  snd_LockVoiceAllocator(bool) { return 0; }
void snd_UnlockVoiceAllocator() {}
s32  snd_ExternVoiceAlloc(s32, s32) { return -1; }
u32  snd_SRAMMalloc(u32) { return 0; }
void snd_SRAMMarkUsed(u32, u32) {}
void snd_SetMixerMode(s32, s32) {}
void snd_SetGroupVoiceRange(s32, s32, s32) {}
void snd_SetReverbDepth(s32, s32, s32) {}
void snd_SetReverbType(s32, s32) {}
void snd_SetPanTable(s16*) {}
void snd_SetPlayBackMode(s32) {}
s32  snd_SoundIsStillPlaying(s32) { return 0; }
void snd_StopSound(s32) {}
u32  snd_GetSoundID(s32) { return 0; }
void snd_SetSoundVolPan(s32, s32, s32) {}
void snd_SetMasterVolume(s32, s32) {}
void snd_UnloadBank(snd::BankHandle) {}
void snd_ResolveBankXREFS() {}
void snd_ContinueAllSoundsInGroup(u8) {}
void snd_PauseAllSoundsInGroup(u8) {}
void snd_SetMIDIRegister(s32, u8, u8) {}
void snd_SetGlobalExcite(u8) {}
s32  snd_PlaySoundVolPanPMPB(snd::BankHandle, s32, s32, s32, s32, s32) { return 0; }
s32  snd_PlaySoundByNameVolPanPMPB(snd::BankHandle, char*, char*, s32, s32, s32, s32) { return 0; }
void snd_SetSoundPitchModifier(s32, s32) {}
void snd_SetSoundPitchBend(s32, s32) {}
void snd_PauseSound(s32) {}
void snd_ContinueSound(s32) {}
void snd_AutoPitch(s32, s32, s32, s32) {}
void snd_AutoPitchBend(s32, s32, s32, s32) {}
snd::BankHandle snd_BankLoadEx(const char*, s32, u32, u32) { return nullptr; }
void snd_BankLoadFromIOPPartialEx_Start() {}
void snd_BankLoadFromIOPPartialEx(const u8*, u32, u32, u32) {}
snd::BankHandle snd_BankLoadFromIOPPartialEx_Completion() { return nullptr; }
s32  snd_GetVoiceStatus(s32) { return 0; }
s32  snd_GetFreeSPUDMA() { return 0; }
void snd_FreeSPUDMA(s32) {}
void snd_keyOnVoiceRaw(u32, u32) {}
void snd_keyOffVoiceRaw(u32, u32) {}
s32  snd_GetSoundUserData(snd::BankHandle, char*, s32, char*, SFXUserData*) { return 0; }
void snd_SetSoundReg(s32, s32, u8) {}
