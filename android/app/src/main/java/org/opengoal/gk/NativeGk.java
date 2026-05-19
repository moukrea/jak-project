// Phase 13 (autoport): JNI bridge for libgk.so.
//
// Mirrors the extern "C" surface declared in android/gk_android_main.cpp.
// Per phase 13 requirements, the bridge does more than expose a version
// banner: it can boot the GOAL runtime with a game selection and forward
// raw Android MotionEvents into the runtime's input layer (which on
// desktop is fed by SDL events).

package org.opengoal.gk;

public final class NativeGk {
    static {
        System.loadLibrary("gk");
    }

    private NativeGk() {}

    /** Returns the version banner baked into libgk.so. */
    public static native String version();

    /** Initialize kernel core globals (kboot/kmalloc/kprint/...). */
    public static native int init();

    /**
     * Boot the GOAL runtime for the given game.
     *
     * @param gameName  One of "jak1", "jak2", "jak3". Forwarded to the
     *                  runtime as `--game <gameName>`.
     * @param dataRoot  Absolute path to the directory containing the
     *                  extracted PS2 ISO data for that game (usually
     *                  getFilesDir()/iso_data/<gameName>). The runtime
     *                  is started with `-fakeiso` and reads from here.
     * @return          0 on a clean exit, non-zero on error.
     */
    public static native int startGame(String gameName, String dataRoot);

    /**
     * Push the selected game name (e.g. "jak1") into a process-lifetime
     * native global. Phase 20: gk_sdl_main reads it when assembling the
     * argv handed to goal_main. MUST be called before SDLActivity.onCreate
     * triggers the SDL thread, since the SDL thread will dlsym
     * gk_sdl_main and consume the global synchronously.
     */
    public static native void setSelectedGame(String gameName);

    /**
     * Push the absolute path of the extracted iso_data directory (e.g.
     * /data/data/org.opengoal.gk.jak1/files/iso_data/jak1) into a
     * process-lifetime native global. Phase 20: goal_main opens
     * "${dataRoot}/KERNEL.CGO" from this path. Same ordering requirement
     * as {@link #setSelectedGame(String)}.
     */
    public static native void setDataRoot(String dataRoot);

    /**
     * Forward an Android MotionEvent into the runtime. The native side
     * synthesizes the equivalent SDL_MOUSEBUTTON / SDL_MOUSEMOTION event
     * and pushes it onto SDL's event queue, so the existing input layer
     * picks it up without per-platform special-casing.
     *
     * @param x       Screen-space x in pixels.
     * @param y       Screen-space y in pixels.
     * @param action  Android MotionEvent.ACTION_* constant (DOWN=0, UP=1,
     *                MOVE=2, CANCEL=3).
     */
    public static native void onTouchEvent(int x, int y, int action);
}
