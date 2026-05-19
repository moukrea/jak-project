// Phase 21 (autoport): GLES bring-up + shader compile + render loop.
//
// android_renderer_run() owns the SDL main thread for the duration of
// the process. It returns when SDL_EVENT_QUIT/TERMINATING arrives or
// when MasterExit transitions out of RUNNING. Called from goal_main
// (android/android_goal_main.cpp) on the SDL thread that SDLActivity
// dispatched into via nativeRunMain.

#pragma once

int android_renderer_run();
