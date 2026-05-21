// Phase 21 (autoport): GLES bring-up + shader compile + render loop.
//
// android_renderer_run() owns the SDL main thread for the duration of
// the process. It returns when SDL_EVENT_QUIT/TERMINATING arrives or
// when MasterExit transitions out of RUNNING. Called from goal_main
// (android/android_goal_main.cpp) on the SDL thread that SDLActivity
// dispatched into via nativeRunMain.
//
// Phase D3 (autoport): the loop maintains a process-lifetime atomic
// frame counter that is incremented after every SDL_GL_SwapWindow.
// android_renderer_frame_count() reads it for the JNI bridge in
// gk_android_main.cpp (Java_org_opengoal_gk_NativeGk_getRendererFrameCount).
// The counter is the observable evidence that the eglSwapBuffers loop
// is iterating; a periodic logcat marker fires every 60 frames.

#pragma once

#include <cstdint>

int android_renderer_run();
uint64_t android_renderer_frame_count();
