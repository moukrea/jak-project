// Phase 11 (autoport): JNI binding for libgk.so.
//
// Mirrors the extern "C" surface declared in android/gk_android_main.cpp.
// As the runtime grows in later phases (full SDL2/SDL3 bring-up, the GOAL
// kernel boot path), more entrypoints will land here.

package org.opengoal.gk;

public final class NativeGk {
    static {
        System.loadLibrary("gk");
    }

    private NativeGk() {}

    /** Returns the version banner baked into libgk.so. */
    public static native String version();
}
