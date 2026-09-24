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
     * Grecharged-buildsys-firstboot (autoport 2026-07): push the absolute path of
     * the per-game external root (e.g. /storage/emulated/0/OpenGOAL/jak1) into a
     * process-lifetime native global. This is the ONLY data-source mode: gk_sdl_main
     * boots with `--game-root <path>`, and FileUtil resolves the
     * assets/custom_assets/saves/settings.ini layout under it. Same call-ordering
     * requirement as {@link #setSelectedGame(String)}. Required (there is no
     * internal / portable fallback).
     */
    public static native void setGameRoot(String path);

    /**
     * External-asset-root feature (autoport 2026-07): push the absolute path of a
     * directory scanned FIRST by fake_iso (per-arch *.CGO/*.DGO + COMMON.TXT
     * overrides) into a process-lifetime native global. gk_sdl_main appends
     * `--iso-overlay <path>` when set: the unpacked CGO pack dir
     * (<filesDir>/cgo/<game>), scanned first so fresh code always wins over the
     * user-folder assets/iso. Same ordering requirement.
     */
    public static native void setIsoOverlay(String path);

    /**
     * Grecharged-buildsys-packaging: push the absolute path of the unpacked
     * package-shipped custom-assets dir (<filesDir>/custom/<game>, holding
     * recharged_assets/ and fr3/) into a process-lifetime native global.
     * gk_sdl_main appends `--custom-assets <path>` when set; FileUtil then
     * prefers it over the vanilla data tree. Same ordering requirement.
     */
    public static native void setCustomRoot(String path);

    /**
     * Owner swamp-crash capture build (INSTRUMENTATION ONLY): push the app's
     * EXTERNAL files dir (getExternalFilesDir(null).getAbsolutePath(), e.g.
     * /sdcard/Android/data/org.opengoal.gk.jak1/files) into a native global so
     * the fatal-signal handler can append the crash forensic to
     * jak_swamp_crash.txt there — a location the owner can retrieve from the
     * phone's Files app WITHOUT adb. The native side only stores this in a
     * JAK_SWAMP_CAPTURE build; in a normal build the native method is an inert
     * no-op, so calling it unconditionally here is harmless.
     */
    public static native void setExternalFilesDir(String dir);

    /**
     * hdr-display-output: push what the SYSTEM announces for the display
     * ({@code Display.getHdrCapabilities()} / {@code Display.isWideColorGamut()})
     * into the native HDR-output module BEFORE the renderer starts. The native
     * side ANDs this with what EGL announces to decide whether the "HDR Output"
     * option exists at all for this player; nothing here forces it ON.
     *
     * @param typesMask       Bitmask {@code 1 << type} over
     *                        {@code HdrCapabilities.getSupportedHdrTypes()}
     *                        (DOLBY_VISION=1, HDR10=2, HLG=3, HDR10_PLUS=4).
     * @param maxLumNits      {@code getDesiredMaxLuminance()} in nits (0 if unknown).
     * @param maxAvgLumNits   {@code getDesiredMaxAverageLuminance()} in nits (0 if unknown).
     * @param minLumX10000    {@code getDesiredMinLuminance()} times 10000 (0 if unknown).
     * @param wideColorGamut  {@code Display.isWideColorGamut()}.
     */
    public static native void setDisplayHdrCaps(int typesMask, int maxLumNits, int maxAvgLumNits,
                                                int minLumX10000, boolean wideColorGamut);

    /** hdr-display-output: platform API level and whether Display.isHdrSdrRatioAvailable() (API 34+). */
    public static native void setDisplayPlatformInfo(int sdkInt, boolean hdrSdrRatioAvailable);

    /**
     * title-tap-prompt-regression: push whether THIS DEVICE has a touch screen into native,
     * before the GOAL runtime boots. The title-screen prompt is chosen from this fact, never
     * from the platform: the SHIELD is Android and has no touch screen, so it must read
     * "Press Start", while any phone reads "Press Start or Tap Screen".
     *
     * @param present            {@code PackageManager.hasSystemFeature(FEATURE_TOUCHSCREEN)}.
     * @param touchInputDevices  INDEPENDENT witness from a different subsystem (InputManager):
     *                           how many {@code InputDevice}s advertise SOURCE_TOUCHSCREEN.
     *                           -1 when the enumeration failed. Published beside the fact so a
     *                           disagreement between the two is visible instead of silent.
     */
    public static native void setTouchScreenPresent(boolean present, int touchInputDevices);

    /** hdr-display-output: current Display.getHdrSdrRatio() (1.0 = no headroom); pushed on every change. */
    public static native void setHdrSdrRatio(float ratio);

    /** hdr-display-output: called FROM native (GL thread) when the scRGB buffer's encoding ratio (currentRatio = the HDR/SDR ratio the game actually rendered to, 1.0 = SDR white) or the desired headroom changed; forwards to MainActivity on the main thread. */
    public static void onHdrOutputExtendedRange(final float currentRatio, final float desiredRatio) {
        MainActivity.applyExtendedRangeBrightness(currentRatio, desiredRatio);
    }

    /** hdr-display-output: called FROM native (GL thread) when the HDR output surface becomes active/inactive; asks the WINDOW for HDR color mode and HDR headroom (the two levers beside setExtendedRangeBrightness). */
    public static void onHdrOutputWindowLevers(final boolean on, final float desiredHeadroom,
                                              final float brightnessTarget) {
        MainActivity.applyHdrOutputWindowLevers(on, desiredHeadroom, brightnessTarget);
    }

    /**
     * Grecharged-managed-assets: does this libgk.so have the PBR path compiled
     * in (OG_FEAT_PBR)? The downloader uses it to decide whether the material-
     * map shards are worth fetching — they are useless, and roughly three
     * quarters of the download, without a renderer that samples them.
     */
    public static native boolean hasPbrFeature();

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

    /** owner-level-teleport-menu : vrai quand le banc de preuve du menu de teleportation est arme. Jamais vrai pour le joueur. */
    public static native boolean isTeleportBenchArmed();

    /**
     * autoport `mesh-browser-removal`: report the touch overlay's OWN pill
     * census to the engine, so the removal gate can read it.
     *
     * Java lives OUTSIDE libgk.so: no C++ probe can count the pills this view
     * builds, and a gate that cannot see the overlay button the owner
     * complained about would be green by blindness. So the overlay reports:
     * {@code sites} = pills belonging to the debug mesh browser,
     * {@code control} = pills of the normal game that must survive. The
     * control count is what makes a zero falsifiable — zero on BOTH sides
     * means the enumeration is broken, not that the browser is gone. Until
     * this bridge is called at least once the engine counts a penalty site,
     * never zero.
     */
    public static native void autoportOverlayCensus(int sites, int control);

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

    // -----------------------------------------------------------------
    // menu-dpad-steps (autoport)
    //
    // Le correctif du d-pad tactile (verrou de direction pour la duree du
    // geste) et son pilote d'auto-test vivent dans TouchOverlayView. Ces
    // entrees ne portent aucune logique : elles delegent a
    // autoport_proof:: / menu_dpad_census:: cote natif.
    // -----------------------------------------------------------------

    /**
     * Armement du correctif pour l'item nomme. VRAI par defaut (y compris si
     * le pont natif manque) : un correctif derriere un drapeau eteint
     * n'existe pas pour l'owner. Faux uniquement quand le harnais mesure CET
     * item avec armed=0 (le bras d'ablation).
     */
    public static native boolean isAutoportArmedFor(String id);

    /** Vrai quand le harnais mesure l'item {@code menu-dpad-steps} : le pilote d'auto-test s'arme. Jamais vrai pour le joueur. */
    public static native boolean isMenuDpadSelftestArmed();

    /** Jambe courante de la campagne : 0 repos, 1 manette, 2 tactile franc, 3 tactile seme. */
    public static native void menuDpadLeg(int leg);

    /**
     * Fin d'un geste pilote. {@code edges} = fronts montants REELLEMENT emis
     * pour ce geste ; {@code legacyEdges} = ce que la regle d'ORIGINE (quatre
     * seuils nus, sans memoire) aurait emis pour le MEME geste, calculee en
     * ombre a chaque image sans jamais toucher le jeu. Sur un geste seme, la
     * paire attendue est (1, 3) : c'est la mesure, dans la course livree, du
     * defaut que le correctif supprime.
     */
    public static native void menuDpadGesture(int edges, int legacyEdges);

    /**
     * Geometrie de la croix, en px de VUE x100 : zone morte, bord interieur de
     * la branche dessinee, et amplitude du creux du controle SEME. Le creux est
     * publie pour que l'owner puisse juger si le stimulus est realiste ou taille
     * pour passer.
     */
    public static native void menuDpadGeometry(int deadX100, int armInnerX100, int seedDipX100);

    /** Campagne terminee : bitmask des jambes finies (1 manette, 2 tactile franc, 4 tactile seme). */
    public static native void menuDpadDone(int legsDone);

    /** Dernier display-state vu par GOAL, -1 si aucun. Sert a prouver qu'on a change de page. */
    public static native int menuDpadScreen();
}
