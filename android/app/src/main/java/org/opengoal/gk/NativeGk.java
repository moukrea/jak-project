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

    /**
     * Phase 23: deliver a button press/release from the on-screen pad
     * overlay to the runtime. The native side logs every event as
     * {@code kernel: pad: <name> pressed|released} (lowercase name) and
     * pushes the state into the SDL virtual joystick that gk_sdl_main
     * attached at startup, so the desktop input layer picks it up
     * unmodified.
     *
     * @param sdlButton One of the SDL3 {@code SDL_GAMEPAD_BUTTON_*}
     *                  values defined in SDL_gamepad.h. Out-of-range
     *                  values are logged and dropped.
     * @param pressed   true on ACTION_DOWN, false on ACTION_UP/CANCEL.
     */
    public static native void onPadButton(int sdlButton, boolean pressed);

    /**
     * Phase Gtouch-controls (autoport): deliver an analog-axis deflection
     * from the on-screen overlay (left virtual stick, right camera-drag
     * zone, or the combined L2/R2 trigger button) to the runtime. Feeds
     * the SAME native axis path a real gamepad's SDL_EVENT_GAMEPAD_AXIS_MOTION
     * uses (android_input_audio::on_pad_axis -> the PS2 cpad mirror), so the
     * injected event is byte-equivalent to a physical pad's.
     *
     * @param sdlAxis One of the SDL3 {@code SDL_GAMEPAD_AXIS_*} values:
     *                LEFTX=0, LEFTY=1, RIGHTX=2, RIGHTY=3,
     *                LEFT_TRIGGER=4, RIGHT_TRIGGER=5.
     * @param value   SDL axis range: sticks -32768..32767 (0 = neutral),
     *                triggers 0..32767. Out-of-range axes are dropped.
     */
    public static native void onPadAxis(int sdlAxis, int value);

    /**
     * Phase Gtouch-controls (autoport): true when the game is currently in
     * a navigable MENU (the title option menu OR the in-game pause/progress
     * menu), false during active gameplay. Computed on the GOAL thread from
     * the live GOAL state (*progress-process* non-#f, or *master-mode* in
     * {menu, progress}) and published via an atomic, so this read is cheap
     * and race-free. The overlay polls it to switch the bottom-left control
     * between the analog stick (gameplay) and a digital d-pad (menus).
     */
    public static native boolean isInMenu();

    /**
     * Phase Gwarp-dpad (autoport): true while the warp/teleporter
     * destination-selection UI is open (a warp-gate process in its 'active
     * state). That screen is D-pad-driven, so {@link TouchOverlayView} ORs
     * this with {@link #isInMenu()} when latching whether the left control
     * acts as an analog stick or a d-pad. Reads a native atomic published on
     * the GOAL thread — cheap and race-free, like isInMenu().
     */
    public static native boolean isInWarp();

    /**
     * Phase Gtouch-menus (autoport): forward a single menu-row tap to the
     * runtime. Called from the overlay on a finger DOWN that missed every
     * on-screen control while {@link #isInMenu()} is true. The coordinates are
     * NORMALIZED to [0,1] (touch pixel / view size) so the native side is
     * resolution-independent; the GOAL progress-menu code hit-tests them against
     * the rows currently on screen and drives the same action the D-pad + confirm
     * would (enter submenu, toggle, cycle a carousel, or go back). Purely
     * additive — the D-pad/gamepad overlay path is unchanged.
     *
     * @param nx Normalized x in [0,1] (left..right).
     * @param ny Normalized y in [0,1] (top..bottom).
     */
    public static native void onMenuTap(float nx, float ny);

    /**
     * Phase Gtitle-tap (autoport): true while the title "PRESS START" screen is
     * up (*target* in target-title-wait, no menu). When true, the overlay turns
     * ANY screen tap into a synthetic START press via {@link #onTitleTap()}.
     */
    public static native boolean isOnTitleStart();

    /**
     * Phase Gtitle-tap (autoport): report a screen tap on the title PRESS START
     * screen. Native synthesizes a short START press into the same PS2 cpad
     * mirror the gamepad uses, so the game sees a genuine edge and opens the
     * start menu exactly as a gamepad START would.
     */
    public static native void onTitleTap();

    /**
     * Phase D3 (autoport): return the cumulative SDL_GL_SwapWindow count
     * since the most recent android_renderer_run entry. Used by the
     * supervisor's reality-check toolkit (D4) to assert that the
     * eglSwapBuffers loop is iterating on hardware — the count must
     * increase monotonically while the activity is foregrounded. A
     * stalled counter while the activity is alive means the GLES
     * context lost the SurfaceView (surface destroyed without
     * surfaceCreated firing again) or the SDL thread is wedged.
     */
    public static native long getRendererFrameCount();

    /**
     * Phase E2 (autoport): return the number of physical SDL gamepads
     * currently opened by android_input_audio (the map populated by
     * SDL_EVENT_GAMEPAD_ADDED / closed on _REMOVED). The Activity polls
     * this on the UI thread to auto-hide the on-screen touch overlay
     * when a Bluetooth pad connects.
     *
     * The virtual joystick attached for the overlay itself does NOT
     * count here — it is a SDL_Joystick, not a SDL_Gamepad-opened
     * device, and the open-gamepad map only tracks real pads.
     */
    public static native int getOpenGamepadCount();

    /**
     * Phase E3 (autoport): write a deterministic save bank to {@code path}
     * by invoking the cross-platform kmemcard writer. The resulting
     * 67584-byte file is byte-identical to what the desktop x86_64 build
     * produces under the same call — the save-portability contract.
     * Returns 0 on success.
     */
    public static native int writeTestSave(String path);
}
