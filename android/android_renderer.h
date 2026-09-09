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

// hdr-display-output : luminances de l'ecran annoncees par le systeme (Java ->
// NativeGk.setDisplayHdrCaps, gk_android_main.cpp), lues par android_renderer.cpp pour les
// metadonnees SMPTE2086 posees sur la surface EGL apres une bascule HDR. 0 = inconnu.
// Sonde EGL precoce (fil Java, avant GOAL) : voir android_renderer.cpp.
void android_hdr_out_probe_early();
extern int g_hdr_out_max_lum_nits;
extern int g_hdr_out_min_lum_x10000;
// hdr-display-output : appel natif -> Java (NativeGk.onHdrOutputExtendedRange) qui pose
// SurfaceControl.Transaction.setExtendedRangeBrightness(sc, ratio, ratio) sur la SDLSurface :
// la marge (ratio HDR/SDR) que le jeu souhaite au-dessus du blanc SDR, sur une surface scRGB.
// Sans effet sous API 34. Implemente dans gk_android_main.cpp (JNI) ; fil quelconque.
void android_hdr_out_request_extended_range(float desired_ratio);
