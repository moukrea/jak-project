// Phase 23 (autoport): SDL3 virtual gamepad + audio playback bring-up.
//
// gk_sdl_main calls android_input_audio_init() once on the SDL main
// thread, before goal_main reaches the renderer. The init:
//   1. brings up SDL_INIT_JOYSTICK,
//   2. attaches a virtual joystick with a SDL_GAMEPAD_TYPE_STANDARD
//      button layout (so SDL_GAMEPAD_BUTTON_* indices map 1:1),
//   3. brings up SDL_INIT_GAMEPAD (E1: opens the SDL gamepad layer
//      so SDL_OpenGamepad() and SDL_EVENT_GAMEPAD_* events are live),
//   4. brings up SDL_INIT_AUDIO,
//   5. opens an SDL_OpenAudioDeviceStream on the default playback
//      device with a silence-fill get-callback,
//   6. starts the stream so the callback begins firing.
//
// android_input_audio_on_pad_button is called from the JNI bridge
// (Java_org_opengoal_gk_NativeGk_onPadButton) on every press/release.
// It logs `kernel: pad: <name> pressed|released` and forwards the
// state to the virtual joystick via SDL_SetJoystickVirtualButton, so
// the desktop input layer (which is already wired to SDL gamepad
// events) picks the press up without per-platform special-casing.
//
// Phase E1 (autoport): process_sdl_event() routes SDL_EVENT_GAMEPAD_*
// dispatched on the SDL main thread (by the renderer's PollEvent loop)
// into SDL_OpenGamepad + on_pad_button. This is how a real Bluetooth
// pad reaches the GOAL kernel — the desktop x86_64 port does the same
// thing in game/system/hid/sdl_util.cpp.

#pragma once

#include <cstdint>

union SDL_Event;

namespace android_input_audio {

void init();
void on_pad_button(int sdl_button, bool pressed);

// Phase F1d (autoport): analog-stick state from a real gamepad. axis is
// an SDL_GAMEPAD_AXIS_* index; value is the raw SDL axis range
// (-32768..32767). Routed from SDL_EVENT_GAMEPAD_AXIS_MOTION in
// process_sdl_event into the cpad mirror that CPadGetData reads.
void on_pad_axis(int sdl_axis, int value);

// Phase F1d (autoport): read the aggregate PS2 controller state that the
// Android CPadGetData (android_runtime_compat.cpp) stamps into the GOAL
// cpad-info each frame. This is the bridge that was missing: the overlay
// JNI / real gamepad / headless injector all update an internal mirror;
// the GOAL kernel reads it here.
//   button0 — PS2 button0 bitmask (pressed = 1), ButtonIndex layout from
//             game/system/hid/input_bindings.h.
//   lx/ly/rx/ry — analog sticks, 0..255, 127 = neutral.
void get_cpad_state(uint16_t* button0, uint8_t* lx, uint8_t* ly,
                    uint8_t* rx, uint8_t* ry);

// Phase F1d (autoport): start the headless input-injection watcher. It
// polls `inject_file_path` (an app-private file the test harness writes
// via run-as) and applies the requested held button/stick STATE into the
// cpad mirror, so an autonomous run can press START and drive movement
// without a human. This injects a real INPUT at the boundary — the GOAL
// game logic still decides what to do with it. No-op if the path is empty
// or the file never appears.
void start_inject_watcher(const char* inject_file_path);

// Phase Gtitle-tap (autoport): synthesize a short START press (button0 bit 3)
// held across a few get_cpad_state polls, so a screen tap on the title
// "PRESS START" screen produces a clean rising edge then release for
// title-obs.gc's (cpad-pressed? 0 start).
void trigger_title_start_pulse();

// Phase E1: route a single SDL event through the gamepad / open-device
// logic. Returns true if the event was consumed (i.e. it was a
// SDL_EVENT_GAMEPAD_* event), false otherwise. Called from the
// renderer's SDL_PollEvent loop on the SDL main thread.
bool process_sdl_event(const SDL_Event& event);

// Phase 30 (autoport): the Android build has no Display::GetMainDisplay()
// registered (android_renderer owns its own SDL window outside the
// graphics/ Gfx::Init path), so scePadRead's `if (pad_data)` branch is
// dead — GOAL never sees a START press. Until phase 31+ wires the real
// GOAL VM and a fallback in game/sce/libpad.cpp, the renderer reads
// this directly so it can respond visibly to input. Returns the
// monotonic-ms-since-epoch of the last SDL_GAMEPAD_BUTTON_START
// press, or 0 if START has not been pressed in this process lifetime.
int64_t last_start_press_ms();

// Monotonic clock readout in the same units as last_start_press_ms().
// Helper so callers can compute the age of the last press without
// re-deriving the clock source.
int64_t monotonic_ms_now();

// Phase E2 (autoport): count of physical SDL gamepads currently held
// open by process_sdl_event (the map populated on
// SDL_EVENT_GAMEPAD_ADDED, decremented on _REMOVED). The Activity
// reads this from the UI thread via a JNI bridge to auto-hide the
// touch overlay when a Bluetooth pad arrives.
//
// Thread-safety: the open-gamepad map itself lives on the SDL main
// thread; we expose only an atomic snapshot of its size so the UI
// thread reader doesn't need to take the SDL thread's lock. Stale
// reads are fine — the worst case is one extra poll cycle (1 s)
// before the overlay hides.
int open_gamepad_count();

}  // namespace android_input_audio
