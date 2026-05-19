// Phase 23 (autoport): SDL3 virtual gamepad + audio playback bring-up.
//
// gk_sdl_main calls android_input_audio_init() once on the SDL main
// thread, before goal_main reaches the renderer. The init:
//   1. brings up SDL_INIT_JOYSTICK,
//   2. attaches a virtual joystick with a SDL_GAMEPAD_TYPE_STANDARD
//      button layout (so SDL_GAMEPAD_BUTTON_* indices map 1:1),
//   3. brings up SDL_INIT_AUDIO,
//   4. opens an SDL_OpenAudioDeviceStream on the default playback
//      device with a silence-fill get-callback,
//   5. starts the stream so the callback begins firing.
//
// android_input_audio_on_pad_button is called from the JNI bridge
// (Java_org_opengoal_gk_NativeGk_onPadButton) on every press/release.
// It logs `kernel: pad: <name> pressed|released` and forwards the
// state to the virtual joystick via SDL_SetJoystickVirtualButton, so
// the desktop input layer (which is already wired to SDL gamepad
// events) picks the press up without per-platform special-casing.

#pragma once

namespace android_input_audio {

void init();
void on_pad_button(int sdl_button, bool pressed);

}  // namespace android_input_audio
