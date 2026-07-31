// Phase Gtouch-controls (autoport): the full on-screen touch overlay.
//
// Owner-specified modern-mobile layout (2026-06-23), replacing the partial
// E2 overlay (face + standalone d-pad + START, ASCII letters, always-on):
//
//   top-LEFT     : ONE combined L2/R2 button  (injects both trigger axes)
//   top-RIGHT    : ONE combined L1/R1 button  (injects both shoulder buttons)
//   top-CENTRE   : small SELECT + START
//   bottom-LEFT  : the left control — analog STICK in gameplay, digital
//                  D-PAD in menus (the game navigates menus with the d-pad;
//                  native tells us which via NativeGk.isInMenu())
//   bottom-RIGHT : the face buttons  ✕ ○ □ △  (SOUTH/EAST/WEST/NORTH)
//   right side   : the CAMERA — a FLOATING, INVISIBLE virtual stick. Any
//                  right-side touch that misses a button ANCHORS an invisible
//                  stick at the touch-down point; RIGHTX/RIGHTY = the
//                  DEFLECTION (current finger - anchor), clamped + normalized,
//                  so holding the finger deflected gives a SUSTAINED camera
//                  pan (like a physical right stick), NOT a per-frame swipe
//                  delta. Release zeroes the axes. Nothing is drawn (invisible)
//                  — the left stick is fixed+visible, this one floats wherever
//                  the finger lands (modern mobile "floating right stick").
//
// Dropped per owner: the two stick-press buttons and the standalone
// directional pad (the left control IS the directional pad, in menu mode).
//
// Same-behavior contract (unchanged from E2): every control injects through
// the SAME native path a real gamepad uses — NativeGk.onPadButton maps to
// SDL_EVENT_GAMEPAD_BUTTON, NativeGk.onPadAxis maps to
// SDL_EVENT_GAMEPAD_AXIS_MOTION — so the cpad state the GOAL kernel reads is
// byte-equivalent to a physical DualShock's. Each control logs an
// `overlay-map:` (layout) and `overlay-actuate:` (per-touch) marker so the
// device harness can prove the mapping without re-deriving the layout math.
//
// Visibility: hidden by default (alpha 0, still touchable — alpha never
// affects hit-testing); any touch fades it in and resets a 10 s idle timer;
// after 10 s with no touch it fades out. A touch while faded brings it back.
// Control touches actuate AND reset the timer.
//
// ALWAYS-PRESENT contract (Grecharged-mesh-browser REOPEN, 2026-07-29): this
// view is now ALWAYS constructed and addView()-ed by MainActivity, whatever the
// "touch_overlay_enabled" preference says. The debug mesh browser routes ALL of
// its finger input through this view (onTouchEvent -> handleBrowserTouch ->
// NativeGk.onBrowserTouch), so a missing view means a browser that no finger can
// reach. The old "overlay disabled" preference — which is persisted on the FIRST
// launch of a fresh install as (gamepadsAtStart == 0), i.e. it latches to false
// forever if a pad merely happened to be attached that one time — therefore no
// longer suppresses the view's EXISTENCE. It now means exactly one thing:
// padSuppressed, i.e. the VIRTUAL GAMEPAD ROLE is off. A pad-suppressed overlay
// draws nothing and actuates nothing, but still carries browser touches.

package org.opengoal.gk;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.util.SparseArray;
import android.view.MotionEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class TouchOverlayView extends View {
    private static final String TAG = "opengoal-gk";

    // SDL3 SDL_GAMEPAD_BUTTON_* (SDL_gamepad.h). A static_assert in
    // android_input_audio.cpp::button_name traps any future renumbering.
    public static final int SDL_GAMEPAD_BUTTON_SOUTH = 0;   // ✕
    public static final int SDL_GAMEPAD_BUTTON_EAST = 1;    // ○
    public static final int SDL_GAMEPAD_BUTTON_WEST = 2;    // □
    public static final int SDL_GAMEPAD_BUTTON_NORTH = 3;   // △
    public static final int SDL_GAMEPAD_BUTTON_BACK = 4;    // SELECT
    public static final int SDL_GAMEPAD_BUTTON_START = 6;
    public static final int SDL_GAMEPAD_BUTTON_LEFT_STICK = 7;      // L3
    public static final int SDL_GAMEPAD_BUTTON_RIGHT_STICK = 8;     // R3
    public static final int SDL_GAMEPAD_BUTTON_LEFT_SHOULDER = 9;   // L1
    public static final int SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER = 10; // R1
    public static final int SDL_GAMEPAD_BUTTON_DPAD_UP = 11;
    public static final int SDL_GAMEPAD_BUTTON_DPAD_DOWN = 12;
    public static final int SDL_GAMEPAD_BUTTON_DPAD_LEFT = 13;
    public static final int SDL_GAMEPAD_BUTTON_DPAD_RIGHT = 14;

    // SDL3 SDL_GAMEPAD_AXIS_* (SDL_gamepad.h): contiguous from 0.
    public static final int SDL_GAMEPAD_AXIS_LEFTX = 0;
    public static final int SDL_GAMEPAD_AXIS_LEFTY = 1;
    public static final int SDL_GAMEPAD_AXIS_RIGHTX = 2;
    public static final int SDL_GAMEPAD_AXIS_RIGHTY = 3;
    public static final int SDL_GAMEPAD_AXIS_LEFT_TRIGGER = 4;
    public static final int SDL_GAMEPAD_AXIS_RIGHT_TRIGGER = 5;

    private static final int AXIS_MAX = 32767;   // SDL stick/trigger max

    // Right camera = a FLOATING, INVISIBLE virtual stick (anchor+deflection),
    // NOT a frame-delta drag. Full deflection (=AXIS_MAX pan rate) is reached at
    // CAM_RADIUS_FRAC of the view height of finger travel from the anchor; a
    // small radial deadzone suppresses anchor jitter. Owner-tunable feel.
    private static final float CAM_RADIUS_FRAC = 0.16f;
    private static final float CAM_DEADZONE_FRAC = 0.12f;

    // Control kinds.
    private static final int KIND_BUTTON = 0;  // single SDL button (face/start/select)
    private static final int KIND_L1R1 = 1;    // both shoulders
    private static final int KIND_L2R2 = 2;    // both triggers (axes)
    private static final int KIND_STICK = 3;   // left: analog stick OR menu d-pad
    private static final int KIND_CAMERA = 4;  // right-side floating invisible deflection stick
    // Grecharged-mesh-browser V2 (freecam): a SINGLE trigger button. sdlButton
    // holds the SDL *axis* id (LEFT_TRIGGER/RIGHT_TRIGGER); press injects
    // AXIS_MAX, release injects 0 — the freecam needs L2 and R2 SEPARATELY,
    // unlike the gameplay combined l2r2 pill.
    private static final int KIND_TRIGGER = 5;

    // Shapes.
    private static final int SHAPE_CIRCLE = 0;
    private static final int SHAPE_RRECT = 1;

    // Visibility / fade.
    private static final long IDLE_FADE_MS = 10_000;  // 10 s idle -> fade out
    private static final long FADE_IN_MS = 180;
    private static final long FADE_OUT_MS = 600;
    private static final long HEARTBEAT_MS = 250;      // idle check + menu-mode poll

    // PlayStation face-button tints.
    private static final int COL_TRIANGLE = Color.argb(0xFF, 0x4A, 0xD9, 0x91);
    private static final int COL_CIRCLE   = Color.argb(0xFF, 0xF0, 0x55, 0x55);
    private static final int COL_CROSS    = Color.argb(0xFF, 0x6E, 0xA8, 0xF0);
    private static final int COL_SQUARE   = Color.argb(0xFF, 0xE0, 0x7C, 0xC8);

    private static final class Ctl {
        final String name;
        final int kind;
        final int shape;
        final int sdlButton;       // for KIND_BUTTON (SDL axis id for KIND_TRIGGER)
        String label;              // pill label (freecam controls); null = derived
        float cx, cy, radius;      // SHAPE_CIRCLE
        final RectF rect = new RectF(); // SHAPE_RRECT
        boolean pressed;           // visual press state (single-button controls)
        long lastLogMs;            // per-control actuation-log throttle

        Ctl(String name, int kind, int shape, int sdlButton) {
            this.name = name;
            this.kind = kind;
            this.shape = shape;
            this.sdlButton = sdlButton;
        }

        boolean contains(float x, float y) {
            if (shape == SHAPE_CIRCLE) {
                float dx = x - cx, dy = y - cy;
                return dx * dx + dy * dy <= radius * radius;
            }
            return rect.contains(x, y);
        }
    }

    // Per-pointer touch tracking.
    private static final class Touch {
        Ctl ctl;            // null for camera / wake-only
        int kind;           // cached control kind (KIND_* or -1 for wake-only)
        boolean stickMenuMode; // latched at down: true => d-pad, false => analog
        float lastX, lastY; // left-stick knob position (drawing only)
        float anchorX, anchorY; // camera: floating-stick anchor, captured at touch-down
        long lastLogMs;     // per-pointer actuation-log throttle (camera/wake)
        // d-pad bits currently held by this stick-in-menu pointer.
        boolean dUp, dDown, dLeft, dRight;
    }

    private final List<Ctl> controls = new ArrayList<>();
    // Grecharged-mesh-browser V2 (freecam): the mode-2 control set. Separate
    // list so normal-mode hit-testing/drawing is untouched; the left stick and
    // the camera-look region are SHARED with normal mode.
    private final List<Ctl> fcControls = new ArrayList<>();
    private Ctl cLeftStick;   // the bottom-left control (stick / menu d-pad)
    private Ctl cFcam;        // mode-0-only "FCAM" button (R3 -> enter freecam)
    private float camRegionLeft;  // x >= this & not on a button => camera drag

    private final SparseArray<Touch> active = new SparseArray<>();

    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint fillBright = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint glyph = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();

    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean heartbeatRunning = false;
    private boolean shown = false;        // logical visible state
    // Ginput-replay-realinput (autoport): while an input record/replay is armed,
    // keep the controls visible (don't idle-fade) so the owner SEES that touch
    // controls are available to record with — otherwise a record made with a
    // silent Bluetooth gamepad and an invisible overlay is silently all-neutral.
    private boolean persistentVisible = false;
    private long lastTouchMs = 0;
    private boolean lastMenuMode = false; // cached for glyph redraws
    // Grecharged-mesh-browser V2 (freecam): the browser MODE, polled from
    // native (NativeGk.meshBrowserMode). 0 = closed (normal virtual pad, plus
    // the small FCAM button). 1 = list-UI: the virtual gamepad is suspended and
    // every MotionEvent is forwarded RAW (multi-touch) to the browser — exactly
    // the old boolean browserMode behavior. 2 = FREECAM: the virtual pad stays
    // LIVE with a freecam control set (fcControls + left stick + camera look).
    private int mbMode = 0;
    private long lastBrowserLogMs = 0;    // MOVE-log throttle for browserMode
    // Grecharged-mesh-browser REOPEN (owner 2026-07-29): the virtual gamepad
    // role is off (see setPadSuppressed). The view still exists and still routes
    // browser touches — only the pad is inert.
    private boolean padSuppressed = false;
    private boolean mapLogged = false;

    public TouchOverlayView(Context context) {
        super(context);
        setFocusable(false);
        setFocusableInTouchMode(false);
        setClickable(false);
        // Start hidden but touchable. View alpha never affects hit-testing,
        // so a touch anywhere still wakes us.
        setAlpha(0f);

        fill.setColor(Color.argb(0x55, 0x18, 0x18, 0x18));
        fill.setStyle(Paint.Style.FILL);
        fillBright.setColor(Color.argb(0x90, 0x30, 0x30, 0x30));
        fillBright.setStyle(Paint.Style.FILL);
        stroke.setColor(Color.argb(0xC8, 0xEC, 0xEC, 0xEC));
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(4f);
        stroke.setStrokeCap(Paint.Cap.ROUND);
        glyph.setStyle(Paint.Style.STROKE);
        glyph.setStrokeWidth(6f);
        glyph.setStrokeCap(Paint.Cap.ROUND);
        glyph.setStrokeJoin(Paint.Join.ROUND);
        text.setColor(Color.argb(0xF0, 0xF4, 0xF4, 0xF4));
        text.setTextAlign(Paint.Align.CENTER);
        text.setFakeBoldText(true);

        buildControls();

        Log.i(TAG, "overlay-visibility: hidden at start (alpha=0, invisible "
                + "until first touch; fades after 10s idle)");
    }

    private void buildControls() {
        // Face buttons (bottom-right). Geometry filled in layoutControls().
        controls.add(new Ctl("south", KIND_BUTTON, SHAPE_CIRCLE, SDL_GAMEPAD_BUTTON_SOUTH));
        controls.add(new Ctl("east",  KIND_BUTTON, SHAPE_CIRCLE, SDL_GAMEPAD_BUTTON_EAST));
        controls.add(new Ctl("west",  KIND_BUTTON, SHAPE_CIRCLE, SDL_GAMEPAD_BUTTON_WEST));
        controls.add(new Ctl("north", KIND_BUTTON, SHAPE_CIRCLE, SDL_GAMEPAD_BUTTON_NORTH));
        // Combined shoulders (top-right) + combined triggers (top-left).
        controls.add(new Ctl("l1r1", KIND_L1R1, SHAPE_RRECT, -1));
        controls.add(new Ctl("l2r2", KIND_L2R2, SHAPE_RRECT, -1));
        // START + SELECT (top-centre).
        controls.add(new Ctl("start",  KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_START));
        controls.add(new Ctl("select", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_BACK));
        // Left control (bottom-left): analog stick / menu d-pad.
        cLeftStick = new Ctl("left-stick", KIND_STICK, SHAPE_CIRCLE, -1);
        controls.add(cLeftStick);
        // Grecharged-mesh-browser V2: mode-0-only FCAM button (R3). GOAL
        // listens for R3 to enter the freecam; the owner has no gamepad, so
        // this is the only finger path into it. Drawn/hit in mode 0 only —
        // in mode 2 the EXIT button covers leaving.
        cFcam = fc(controls, "fcam", KIND_BUTTON, SHAPE_RRECT,
                SDL_GAMEPAD_BUTTON_RIGHT_STICK, "CAM");

        // Grecharged-mesh-browser V2 FREECAM control set (mode 2 only). The
        // GOAL freecam is 100% pad-driven: left stick fly, right stick look,
        // R1/R2 target, L1/L2 hide/show, Square checker, Circle gizmos,
        // START isolation (render ONLY the target), Triangle defocus, X
        // boost, dpad left/right time-of-day, dpad up/down relief, R3 exit.
        // L1 vs R1 (and L2 vs R2) must be SEPARATE buttons here, unlike the
        // gameplay combined pills.
        fc(fcControls, "fc-l1", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_LEFT_SHOULDER, "L1");
        fc(fcControls, "fc-r1", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, "R1");
        fc(fcControls, "fc-l2", KIND_TRIGGER, SHAPE_RRECT, SDL_GAMEPAD_AXIS_LEFT_TRIGGER, "L2");
        fc(fcControls, "fc-r2", KIND_TRIGGER, SHAPE_RRECT, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER, "R2");
        fc(fcControls, "fc-triangle", KIND_BUTTON, SHAPE_CIRCLE, SDL_GAMEPAD_BUTTON_NORTH, null);
        fc(fcControls, "fc-circle", KIND_BUTTON, SHAPE_CIRCLE, SDL_GAMEPAD_BUTTON_EAST, null);
        fc(fcControls, "fc-square", KIND_BUTTON, SHAPE_CIRCLE, SDL_GAMEPAD_BUTTON_WEST, null);
        fc(fcControls, "fc-boost", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_SOUTH, "BOOST");
        fc(fcControls, "fc-tod-minus", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_DPAD_LEFT, "TOD-");
        fc(fcControls, "fc-tod-plus", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_DPAD_RIGHT, "TOD+");
        fc(fcControls, "fc-rel-minus", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_DPAD_DOWN, "REL-");
        fc(fcControls, "fc-rel-plus", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_DPAD_UP, "REL+");
        // V2.3: MARK = L3 (flag the reticle-hovered polygon -> mesh_marks.jsonl). Same right-edge
        // pill style as BOOST, placed just under it.
        fc(fcControls, "fc-mark", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_LEFT_STICK, "MARK");
        // V2.6-bis: ISOL = START (toggle isolation: render ONLY the targeted mesh). Same virtual
        // pad button + mechanism as the mode-0 START pill; left edge under L2.
        fc(fcControls, "fc-isol", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_START, "ISOL");
        fc(fcControls, "fc-exit", KIND_BUTTON, SHAPE_RRECT, SDL_GAMEPAD_BUTTON_RIGHT_STICK, "EXIT");
    }

    private static Ctl fc(List<Ctl> into, String name, int kind, int shape, int sdlTarget,
                          String label) {
        Ctl c = new Ctl(name, kind, shape, sdlTarget);
        c.label = label;
        into.add(c);
        return c;
    }

    private Ctl ctl(String name) {
        for (Ctl c : controls) if (c.name.equals(name)) return c;
        return null;
    }

    private Ctl fctl(String name) {
        for (Ctl c : fcControls) if (c.name.equals(name)) return c;
        return null;
    }

    @Override
    public boolean hasOverlappingRendering() {
        // Glyphs don't meaningfully overlap; let setAlpha() composite the
        // whole view cleanly without forcing an off-screen layer.
        return false;
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        layoutControls(w, h);
        text.setTextSize(Math.max(18f, h * 0.030f));
        stroke.setStrokeWidth(Math.max(3f, h * 0.006f));
        glyph.setStrokeWidth(Math.max(4f, h * 0.009f));
        if (!mapLogged && w > 0 && h > 0) {
            mapLogged = true;
            logOverlayMap(w, h);
        }
        invalidate();
    }

    private void layoutControls(int w, int h) {
        // Face cluster: bottom-right diamond.
        final float r = Math.max(38f, h * 0.070f);
        final float gap = r * 1.55f;
        final float faceCx = w * 0.86f;
        final float faceCy = h * 0.70f;
        place("south", faceCx,        faceCy + gap, r);
        place("east",  faceCx + gap,  faceCy,       r);
        place("west",  faceCx - gap,  faceCy,       r);
        place("north", faceCx,        faceCy - gap, r);

        // Left control: bottom-left. The hit zone is generous so the thumb
        // finds it; the visible ring/d-pad is drawn at ~0.6 of the zone.
        final float stickR = Math.max(70f, h * 0.165f);
        cLeftStick.cx = w * 0.155f;
        cLeftStick.cy = h * 0.68f;
        cLeftStick.radius = stickR;

        // Combined trigger button (top-left) + shoulder button (top-right).
        final float bw = Math.max(120f, w * 0.115f);
        final float bh = Math.max(54f, h * 0.105f);
        final float top = h * 0.055f;
        ctl("l2r2").rect.set(w * 0.030f, top, w * 0.030f + bw, top + bh);
        ctl("l1r1").rect.set(w * 0.970f - bw, top, w * 0.970f, top + bh);

        // START + SELECT: small pills, top-centre (SELECT left of START).
        final float sw = Math.max(90f, w * 0.085f);
        final float sh = Math.max(36f, h * 0.060f);
        final float sTop = h * 0.045f;
        ctl("select").rect.set(w * 0.5f - sw - 10f, sTop, w * 0.5f - 10f, sTop + sh);
        ctl("start").rect.set(w * 0.5f + 10f, sTop, w * 0.5f + 10f + sw, sTop + sh);

        // Grecharged-mesh-browser V2: CAM (mode 0 only). Owner placement decision
        // 2026-07-30: "La place du bouton freecam à côté de start et select je
        // dirais" — it lives IN the Start/Select group: same row, same pill size
        // and style, immediately right of START (the group reads SELECT|START|CAM).
        cFcam.rect.set(w * 0.5f + 10f + sw + 20f, sTop, w * 0.5f + 10f + sw + 20f + sw, sTop + sh);

        // Grecharged-mesh-browser V2 FREECAM layout (mode 2 only). The centre
        // of the screen stays CLEAR: the reticle and the world must be
        // visible. Shoulders/triggers in the top corners, face buttons down
        // the right edge, TOD/REL small along the bottom, EXIT
        // top-centre-right. Left stick + camera-look region are shared.
        final float fbw = Math.max(110f, w * 0.100f);
        final float fbh = Math.max(48f, h * 0.095f);
        final float fgap = h * 0.020f;
        fctl("fc-l1").rect.set(w * 0.030f, top, w * 0.030f + fbw, top + fbh);
        fctl("fc-l2").rect.set(w * 0.030f, top + fbh + fgap, w * 0.030f + fbw, top + 2f * fbh + fgap);
        // V2.6-bis ISOL: left edge, directly under L2 (same pill size) — mirrors MARK under BOOST
        // on the right edge; the left stick region starts far lower, no overlap.
        fctl("fc-isol").rect.set(w * 0.030f, top + 2f * (fbh + fgap),
                w * 0.030f + fbw, top + 3f * fbh + 2f * fgap);
        fctl("fc-r1").rect.set(w * 0.970f - fbw, top, w * 0.970f, top + fbh);
        fctl("fc-r2").rect.set(w * 0.970f - fbw, top + fbh + fgap, w * 0.970f, top + 2f * fbh + fgap);
        fctl("fc-exit").rect.set(w * 0.575f, sTop, w * 0.575f + sw, sTop + sh);
        final float fr = Math.max(34f, h * 0.062f);
        final float fcx = w * 0.925f;
        place2(fctl("fc-triangle"), fcx, h * 0.33f, fr);
        place2(fctl("fc-circle"),   fcx, h * 0.47f, fr);
        place2(fctl("fc-square"),   fcx, h * 0.61f, fr);
        fctl("fc-boost").rect.set(w * 0.970f - fbw, h * 0.70f, w * 0.970f, h * 0.70f + fbh);
        // V2.3 MARK: right edge, directly under BOOST (same pill size); clears the TOD/REL bottom
        // row (x 0.300-0.690) by construction.
        fctl("fc-mark").rect.set(w * 0.970f - fbw, h * 0.70f + fbh + fgap,
                w * 0.970f, h * 0.70f + 2f * fbh + fgap);
        final float fsw = Math.max(84f, w * 0.075f);
        final float fsh = Math.max(34f, h * 0.058f);
        final float fby = h * 0.895f;
        fctl("fc-tod-minus").rect.set(w * 0.300f, fby, w * 0.300f + fsw, fby + fsh);
        fctl("fc-tod-plus").rect.set(w * 0.395f, fby, w * 0.395f + fsw, fby + fsh);
        fctl("fc-rel-minus").rect.set(w * 0.520f, fby, w * 0.520f + fsw, fby + fsh);
        fctl("fc-rel-plus").rect.set(w * 0.615f, fby, w * 0.615f + fsw, fby + fsh);

        // Camera drag zone: the right portion of the screen. A right-side
        // touch that misses every button pans the camera.
        camRegionLeft = w * 0.45f;
    }

    private static void place2(Ctl c, float cx, float cy, float r) {
        if (c != null) { c.cx = cx; c.cy = cy; c.radius = r; }
    }

    private void place(String name, float cx, float cy, float r) {
        Ctl c = ctl(name);
        if (c != null) { c.cx = cx; c.cy = cy; c.radius = r; }
    }

    private void logOverlayMap(int w, int h) {
        // One marker line the harness greps and serialises into controls.txt.
        // Enumerates EVERY control: name -> SDL target -> region. Note the
        // left control's dual role (analog stick / menu d-pad) and the
        // right-side camera drag zone.
        StringBuilder sb = new StringBuilder();
        sb.append("overlay-map: screen=").append(w).append('x').append(h);
        Ctl c;
        c = ctl("south"); sb.append(" south=").append(circ(c)).append("->onPadButton(SOUTH=0)");
        c = ctl("east");  sb.append(" east=").append(circ(c)).append("->onPadButton(EAST=1)");
        c = ctl("west");  sb.append(" west=").append(circ(c)).append("->onPadButton(WEST=2)");
        c = ctl("north"); sb.append(" north=").append(circ(c)).append("->onPadButton(NORTH=3)");
        c = ctl("l1r1");  sb.append(" l1r1=").append(rrect(c))
                .append("->onPadButton(LEFT_SHOULDER+RIGHT_SHOULDER)[top-right,combined]");
        c = ctl("l2r2");  sb.append(" l2r2=").append(rrect(c))
                .append("->onPadAxis(LEFT_TRIGGER+RIGHT_TRIGGER)[top-left,combined]");
        c = ctl("start");  sb.append(" start=").append(rrect(c)).append("->onPadButton(START=6)");
        c = ctl("select"); sb.append(" select=").append(rrect(c)).append("->onPadButton(BACK=4)[SELECT]");
        sb.append(" left-stick=").append(circ(cLeftStick))
                .append("->onPadAxis(LEFTX/LEFTY)[bottom-left,gameplay]");
        sb.append(" menu-dpad=<left-stick becomes a digital d-pad in menus>")
                .append("->onPadButton(DPAD_UP/DOWN/LEFT/RIGHT)");
        sb.append(" camera=<right-side FLOATING invisible deflection stick, anchors on touch-down at x>=")
                .append((int) camRegionLeft)
                .append(", RIGHTX/RIGHTY=(cur-anchor) sustained, not-drag-delta>->onPadAxis(RIGHTX/RIGHTY)");
        sb.append(" dropped=<the two stick-press buttons + the standalone directional pad>");
        Log.i(TAG, sb.toString());

        // Grecharged-mesh-browser V2: one marker line per new control, greppable
        // by the proof harness for tap coordinates. fcam is mode-0 only; the
        // fc-* set is mode-2 (FREECAM) only, where the virtual pad stays LIVE
        // and the left stick + right-side camera-look region above are shared.
        Log.i(TAG, "overlay-map: fcam=" + rrect(cFcam)
                + "->onPadButton(RIGHT_STICK=8)[R3 enter-freecam CAM pill, Start/Select group, mode0 only]");
        Log.i(TAG, "overlay-map: fc-l1=" + rrect(fctl("fc-l1"))
                + "->onPadButton(LEFT_SHOULDER=9)[freecam hide, top-left]");
        Log.i(TAG, "overlay-map: fc-r1=" + rrect(fctl("fc-r1"))
                + "->onPadButton(RIGHT_SHOULDER=10)[freecam target, top-right]");
        Log.i(TAG, "overlay-map: fc-l2=" + rrect(fctl("fc-l2"))
                + "->onPadAxis(LEFT_TRIGGER=4)[freecam show, top-left, separate]");
        Log.i(TAG, "overlay-map: fc-r2=" + rrect(fctl("fc-r2"))
                + "->onPadAxis(RIGHT_TRIGGER=5)[freecam target, top-right, separate]");
        Log.i(TAG, "overlay-map: fc-triangle=" + circ(fctl("fc-triangle"))
                + "->onPadButton(NORTH=3)[freecam defocus, right edge]");
        Log.i(TAG, "overlay-map: fc-circle=" + circ(fctl("fc-circle"))
                + "->onPadButton(EAST=1)[freecam gizmos, right edge]");
        Log.i(TAG, "overlay-map: fc-square=" + circ(fctl("fc-square"))
                + "->onPadButton(WEST=2)[freecam checker, right edge]");
        Log.i(TAG, "overlay-map: fc-boost=" + rrect(fctl("fc-boost"))
                + "->onPadButton(SOUTH=0)[freecam BOOST, right edge]");
        Log.i(TAG, "overlay-map: fc-mark=" + rrect(fctl("fc-mark"))
                + "->onPadButton(LEFT_STICK=7)[freecam mark polygon, right edge under BOOST]");
        Log.i(TAG, "overlay-map: fc-isol=" + rrect(fctl("fc-isol"))
                + "->onPadButton(START=6)[freecam isolation toggle, left edge under L2]");
        Log.i(TAG, "overlay-map: fc-tod-minus=" + rrect(fctl("fc-tod-minus"))
                + "->onPadButton(DPAD_LEFT=13)[freecam time-of-day -, bottom]");
        Log.i(TAG, "overlay-map: fc-tod-plus=" + rrect(fctl("fc-tod-plus"))
                + "->onPadButton(DPAD_RIGHT=14)[freecam time-of-day +, bottom]");
        Log.i(TAG, "overlay-map: fc-rel-minus=" + rrect(fctl("fc-rel-minus"))
                + "->onPadButton(DPAD_DOWN=12)[freecam relief -, bottom]");
        Log.i(TAG, "overlay-map: fc-rel-plus=" + rrect(fctl("fc-rel-plus"))
                + "->onPadButton(DPAD_UP=11)[freecam relief +, bottom]");
        Log.i(TAG, "overlay-map: fc-exit=" + rrect(fctl("fc-exit"))
                + "->onPadButton(RIGHT_STICK=8)[R3 exit-freecam, top-centre-right]");
    }

    private static String circ(Ctl c) {
        return String.format(Locale.ROOT, "%d,%d,%d", (int) c.cx, (int) c.cy, (int) c.radius);
    }

    private static String rrect(Ctl c) {
        return String.format(Locale.ROOT, "%d,%d,%d,%d",
                (int) c.rect.left, (int) c.rect.top, (int) c.rect.width(), (int) c.rect.height());
    }

    // ---------------------------------------------------------------------
    // Drawing
    // ---------------------------------------------------------------------

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        // Grecharged-mesh-browser REOPEN: the list-UI browser owns the screen;
        // its list must not be covered by the virtual pad glyphs.
        if (mbMode == 1) return;
        // Grecharged-mesh-browser V2: FREECAM — the virtual pad is LIVE with
        // the freecam control set. Drawn even when padSuppressed: the freecam
        // is finger-driven by design (the owner has no gamepad and no adb), so
        // like the browser's raw-touch path it takes priority over the
        // pad-suppression preference.
        if (mbMode == 2) {
            drawFreecam(canvas);
            return;
        }
        // Grecharged-mesh-browser REOPEN: the virtual pad role is off (the old
        // "overlay disabled" preference). The view still exists to carry browser
        // touches, but an inert overlay must draw nothing.
        if (padSuppressed) return;
        for (Ctl c : controls) {
            switch (c.kind) {
                case KIND_BUTTON:
                    if (c.shape == SHAPE_RRECT) {
                        // start / select / fcam: pills with a text label.
                        drawPill(canvas, c, c.label != null
                                ? c.label : c.name.toUpperCase(Locale.ROOT));
                    } else {
                        drawFace(canvas, c);
                    }
                    break;
                case KIND_L1R1: drawPill(canvas, c, "L1  R1"); break;
                case KIND_L2R2: drawPill(canvas, c, "L2  R2"); break;
                case KIND_STICK: drawLeftControl(canvas, c); break;
                default: break;
            }
        }
    }

    // Keyed on the SDL button (not the control name) so the freecam's
    // fc-triangle/fc-circle/fc-square reuse the same PlayStation glyphs.
    private void drawFace(Canvas canvas, Ctl c) {
        canvas.drawCircle(c.cx, c.cy, c.radius, c.pressed ? fillBright : fill);
        int tint;
        switch (c.sdlButton) {
            case SDL_GAMEPAD_BUTTON_NORTH: tint = COL_TRIANGLE; break;
            case SDL_GAMEPAD_BUTTON_EAST:  tint = COL_CIRCLE; break;
            case SDL_GAMEPAD_BUTTON_SOUTH: tint = COL_CROSS; break;
            default:                       tint = COL_SQUARE; break; // west
        }
        stroke.setColor(applyA(tint, 0xC8));
        canvas.drawCircle(c.cx, c.cy, c.radius, stroke);
        glyph.setColor(tint);
        float g = c.radius * 0.5f;
        switch (c.sdlButton) {
            case SDL_GAMEPAD_BUTTON_SOUTH: // ✕
                canvas.drawLine(c.cx - g, c.cy - g, c.cx + g, c.cy + g, glyph);
                canvas.drawLine(c.cx - g, c.cy + g, c.cx + g, c.cy - g, glyph);
                break;
            case SDL_GAMEPAD_BUTTON_EAST:  // ○
                canvas.drawCircle(c.cx, c.cy, g, glyph);
                break;
            case SDL_GAMEPAD_BUTTON_WEST:  // □
                canvas.drawRect(c.cx - g, c.cy - g, c.cx + g, c.cy + g, glyph);
                break;
            case SDL_GAMEPAD_BUTTON_NORTH: // △
                path.reset();
                path.moveTo(c.cx, c.cy - g);
                path.lineTo(c.cx + g, c.cy + g * 0.85f);
                path.lineTo(c.cx - g, c.cy + g * 0.85f);
                path.close();
                canvas.drawPath(path, glyph);
                break;
            default: break;
        }
        // restore default stroke colour for non-face controls
        stroke.setColor(Color.argb(0xC8, 0xEC, 0xEC, 0xEC));
    }

    // Grecharged-mesh-browser V2: the FREECAM control set (mode 2). Face-glyph
    // circles reuse drawFace; everything else is a labelled pill. The shared
    // left stick is drawn too (always analog here — the freecam flies with it);
    // the camera-look region stays invisible, exactly like normal mode.
    private void drawFreecam(Canvas canvas) {
        for (Ctl c : fcControls) {
            if (c.kind == KIND_BUTTON && c.shape == SHAPE_CIRCLE) {
                drawFace(canvas, c);
            } else {
                drawPill(canvas, c, c.label);
            }
        }
        drawLeftControl(canvas, cLeftStick);
    }

    private void drawPill(Canvas canvas, Ctl c, String labelText) {
        float rad = c.rect.height() * 0.5f;
        canvas.drawRoundRect(c.rect, rad, rad, c.pressed ? fillBright : fill);
        canvas.drawRoundRect(c.rect, rad, rad, stroke);
        float ts = Math.min(text.getTextSize(), c.rect.height() * 0.55f);
        float prev = text.getTextSize();
        text.setTextSize(ts);
        canvas.drawText(labelText, c.rect.centerX(),
                c.rect.centerY() + ts * 0.35f, text);
        text.setTextSize(prev);
    }

    private void drawLeftControl(Canvas canvas, Ctl c) {
        // Freecam always flies with the analog stick, whatever the menu poll says.
        final boolean menu = lastMenuMode && mbMode != 2;
        final float baseR = c.radius * 0.62f;
        // base disc
        canvas.drawCircle(c.cx, c.cy, baseR, fill);
        canvas.drawCircle(c.cx, c.cy, baseR, stroke);
        if (menu) {
            // d-pad cross (plus shape) + highlight any held direction
            float arm = baseR * 0.78f;
            float wdt = baseR * 0.30f;
            path.reset();
            path.moveTo(c.cx - wdt, c.cy - arm);
            path.lineTo(c.cx + wdt, c.cy - arm);
            path.lineTo(c.cx + wdt, c.cy - wdt);
            path.lineTo(c.cx + arm, c.cy - wdt);
            path.lineTo(c.cx + arm, c.cy + wdt);
            path.lineTo(c.cx + wdt, c.cy + wdt);
            path.lineTo(c.cx + wdt, c.cy + arm);
            path.lineTo(c.cx - wdt, c.cy + arm);
            path.lineTo(c.cx - wdt, c.cy + wdt);
            path.lineTo(c.cx - arm, c.cy + wdt);
            path.lineTo(c.cx - arm, c.cy - wdt);
            path.lineTo(c.cx - wdt, c.cy - wdt);
            path.close();
            glyph.setColor(Color.argb(0xE0, 0xF0, 0xF0, 0xF0));
            canvas.drawPath(path, glyph);
        } else {
            // analog knob: follow the active stick pointer if any, else centre
            float kx = c.cx, ky = c.cy;
            Touch t = stickTouch();
            if (t != null) { kx = t.lastX; ky = t.lastY; }
            // clamp knob to the base
            float dx = kx - c.cx, dy = ky - c.cy;
            float d = (float) Math.hypot(dx, dy);
            float maxR = baseR;
            if (d > maxR && d > 0) { kx = c.cx + dx / d * maxR; ky = c.cy + dy / d * maxR; }
            float knobR = baseR * 0.46f;
            canvas.drawCircle(kx, ky, knobR, fillBright);
            canvas.drawCircle(kx, ky, knobR, stroke);
        }
    }

    private Touch stickTouch() {
        for (int i = 0; i < active.size(); i++) {
            Touch t = active.valueAt(i);
            if (t.kind == KIND_STICK) return t;
        }
        return null;
    }

    private static int applyA(int color, int a) {
        return Color.argb(a, Color.red(color), Color.green(color), Color.blue(color));
    }

    // ---------------------------------------------------------------------
    // Touch handling
    // ---------------------------------------------------------------------

    @Override
    public boolean onTouchEvent(MotionEvent ev) {
        // Grecharged-mesh-browser V2: poll the browser MODE. Mode 1 (list-UI)
        // suspends the virtual gamepad and forwards the raw gesture stream to
        // the browser (swipe / drag / pinch), which taps cannot express. Mode 2
        // (FREECAM) keeps the virtual pad LIVE with the freecam control set.
        final int mode = queryBrowserMode();
        if (mode != mbMode) {
            mbMode = mode;
            releaseAll();   // never leave a pad button/stick/trigger latched across a mode switch
            invalidate();
        }
        if (mbMode == 1) return handleBrowserTouch(ev);
        // padSuppressed gates mode 0 only: the freecam (mode 2) is
        // finger-driven by design — the owner has no gamepad and no adb — so
        // like the browser's raw-touch path it overrides the pad-suppression
        // preference.
        if (padSuppressed && mbMode != 2) return true;   // overlay present for the mesh browser, but the virtual pad is off
        final int action = ev.getActionMasked();
        keepAwake();
        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: {
                final int idx = ev.getActionIndex();
                final int pid = ev.getPointerId(idx);
                onPointerDown(pid, ev.getX(idx), ev.getY(idx));
                invalidate();
                return true;
            }
            case MotionEvent.ACTION_MOVE: {
                for (int i = 0; i < ev.getPointerCount(); i++) {
                    onPointerMove(ev.getPointerId(i), ev.getX(i), ev.getY(i));
                }
                invalidate();
                return true;
            }
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP: {
                final int idx = ev.getActionIndex();
                onPointerUp(ev.getPointerId(idx));
                invalidate();
                return true;
            }
            case MotionEvent.ACTION_CANCEL: {
                releaseAll();
                invalidate();
                return true;
            }
            default:
                return true;
        }
    }

    private void onPointerDown(int pid, float x, float y) {
        // Phase Gtitle-tap (autoport): on the title "PRESS START" screen, ANY
        // tap acts as START. The native pulse feeds the same PS2 cpad mirror
        // the gamepad uses, so title-obs.gc's (cpad-pressed? 0 start) sees a
        // genuine edge -> same menu transition, same sound. Native scopes the
        // flag to target-title-wait with no menu up, so in-game taps and the
        // Gtouch-menus in-menu tap path are untouched. Falls through so the
        // overlay controls still actuate normally (harmless on the title).
        if (NativeGk.isOnTitleStart()) {
            NativeGk.onTitleTap();
        }
        Touch t = new Touch();
        t.lastX = x;
        t.lastY = y;
        // Priority: explicit controls (buttons, then left-stick), then the
        // right-side camera zone, else a wake-only touch. In FREECAM (mode 2)
        // the button set is fcControls; the left stick and the camera-look
        // region are shared with normal mode.
        Ctl hit = null;
        for (Ctl c : (mbMode == 2 ? fcControls : controls)) {
            if (c.kind == KIND_STICK) continue; // checked after buttons
            if (c.contains(x, y)) { hit = c; break; }
        }
        if (hit == null && cLeftStick.contains(x, y)) hit = cLeftStick;

        if (hit != null) {
            t.ctl = hit;
            t.kind = hit.kind;
            actuateDown(t, hit, x, y);
        } else if (mbMode != 2 && NativeGk.isInMenu()) {
            // Phase Gtouch-menus (autoport): a tap that missed every on-screen
            // control while a menu is up drives menu-row navigation by touch.
            // Forward the NORMALIZED tap; the GOAL progress-menu code hit-tests
            // the row under it and reproduces the d-pad+confirm action. This is
            // additive: taps on the d-pad/buttons above still hit `hit != null`.
            // No camera pan in menus, so this takes priority over camRegionLeft.
            t.kind = -1; // wake-only: no per-move handling, released on UP
            final int vw = getWidth();
            final int vh = getHeight();
            if (vw > 0 && vh > 0) {
                NativeGk.onMenuTap(x / (float) vw, y / (float) vh);
                logActuate(t, "menu-tap", "normalized ("
                        + String.format("%.3f", x / (float) vw) + ","
                        + String.format("%.3f", y / (float) vh)
                        + ") -> NativeGk.onMenuTap (GOAL hit-tests the row)", true);
            }
        } else if (x >= camRegionLeft) {
            t.ctl = null;
            t.kind = KIND_CAMERA;
            // Anchor the floating invisible stick at the touch-down point. The
            // camera axis is the DEFLECTION (current finger - anchor), so it
            // starts at neutral and only pans once the finger moves off-anchor.
            t.anchorX = x;
            t.anchorY = y;
            NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_RIGHTX, 0);
            NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_RIGHTY, 0);
            logActuate(t, "camera", "anchor (x=" + (int) x + ",y=" + (int) y
                    + ") -> floating invisible RIGHTX/RIGHTY stick "
                    + "(deflection = cur - anchor, sustained while held)", true);
        } else {
            t.kind = -1; // wake-only
        }
        active.put(pid, t);
    }

    private void onPointerMove(int pid, float x, float y) {
        Touch t = active.get(pid);
        if (t == null) return;
        switch (t.kind) {
            case KIND_STICK:
                updateStick(t, x, y);
                t.lastX = x; t.lastY = y;
                break;
            case KIND_CAMERA: {
                // Floating-stick deflection: the offset from the touch-down
                // anchor (cur - anchor), clamped + normalized. A HELD finger
                // keeps injecting the SAME value (sustained pan) — it does NOT
                // decay to neutral like a per-frame swipe delta would.
                int[] rv = camDeflection(x - t.anchorX, y - t.anchorY, camMaxRadius());
                NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_RIGHTX, rv[0]);
                NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_RIGHTY, rv[1]);
                logActuateThrottled(t, "camera",
                        "deflect dx=" + (int) (x - t.anchorX) + " dy=" + (int) (y - t.anchorY)
                                + " -> onPadAxis(RIGHTX) value=" + rv[0]
                                + ", onPadAxis(RIGHTY) value=" + rv[1] + " [sustained held]");
                break;
            }
            default:
                t.lastX = x; t.lastY = y;
                break;
        }
    }

    private void onPointerUp(int pid) {
        Touch t = active.get(pid);
        if (t == null) return;
        releaseTouch(t);
        active.remove(pid);
    }

    private void releaseAll() {
        for (int i = 0; i < active.size(); i++) releaseTouch(active.valueAt(i));
        active.clear();
    }

    private void releaseTouch(Touch t) {
        switch (t.kind) {
            case KIND_BUTTON:
                t.ctl.pressed = false;
                NativeGk.onPadButton(t.ctl.sdlButton, false);
                logActuate(t, t.ctl.name, "release -> onPadButton(sdl="
                        + t.ctl.sdlButton + ") pressed=0", true);
                break;
            case KIND_L1R1:
                t.ctl.pressed = false;
                NativeGk.onPadButton(SDL_GAMEPAD_BUTTON_LEFT_SHOULDER, false);
                NativeGk.onPadButton(SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, false);
                logActuate(t, "l1r1", "release -> onPadButton(LEFT_SHOULDER+RIGHT_SHOULDER) pressed=0", true);
                break;
            case KIND_L2R2:
                t.ctl.pressed = false;
                NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_LEFT_TRIGGER, 0);
                NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_RIGHT_TRIGGER, 0);
                logActuate(t, "l2r2", "release -> onPadAxis(LEFT_TRIGGER+RIGHT_TRIGGER) value=0", true);
                break;
            case KIND_TRIGGER:
                // Freecam separate L2 / R2: sdlButton holds the SDL axis id.
                t.ctl.pressed = false;
                NativeGk.onPadAxis(t.ctl.sdlButton, 0);
                logActuate(t, t.ctl.name, "release -> onPadAxis(axis="
                        + t.ctl.sdlButton + ") value=0", true);
                break;
            case KIND_STICK:
                if (t.stickMenuMode) {
                    releaseDpad(t);
                    logActuate(t, "menu-dpad", "release -> onPadButton(DPAD_*) pressed=0", true);
                } else {
                    NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_LEFTX, 0);
                    NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_LEFTY, 0);
                    logActuate(t, "left-stick", "release -> onPadAxis(LEFTX) value=0, onPadAxis(LEFTY) value=0 (neutral)", true);
                }
                break;
            case KIND_CAMERA:
                // Release the floating stick: it disappears and the look axes
                // snap back to neutral.
                NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_RIGHTX, 0);
                NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_RIGHTY, 0);
                logActuate(t, "camera", "release -> onPadAxis(RIGHTX) value=0, onPadAxis(RIGHTY) value=0 (neutral)", true);
                break;
            default:
                break;
        }
    }

    private void actuateDown(Touch t, Ctl c, float x, float y) {
        switch (c.kind) {
            case KIND_BUTTON:
                c.pressed = true;
                NativeGk.onPadButton(c.sdlButton, true);
                logActuate(t, c.name, "tap (" + (int) x + "," + (int) y
                        + ") -> onPadButton(sdl=" + c.sdlButton + ") pressed=1", true);
                break;
            case KIND_L1R1:
                c.pressed = true;
                NativeGk.onPadButton(SDL_GAMEPAD_BUTTON_LEFT_SHOULDER, true);
                NativeGk.onPadButton(SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, true);
                logActuate(t, "l1r1", "tap -> onPadButton(LEFT_SHOULDER+RIGHT_SHOULDER) pressed=1 [combined]", true);
                break;
            case KIND_L2R2:
                c.pressed = true;
                NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_LEFT_TRIGGER, AXIS_MAX);
                NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_RIGHT_TRIGGER, AXIS_MAX);
                logActuate(t, "l2r2", "tap -> onPadAxis(LEFT_TRIGGER) value=" + AXIS_MAX
                        + ", onPadAxis(RIGHT_TRIGGER) value=" + AXIS_MAX + " [combined]", true);
                break;
            case KIND_TRIGGER:
                // Freecam separate L2 / R2: sdlButton holds the SDL axis id.
                c.pressed = true;
                NativeGk.onPadAxis(c.sdlButton, AXIS_MAX);
                logActuate(t, c.name, "tap (" + (int) x + "," + (int) y
                        + ") -> onPadAxis(axis=" + c.sdlButton + ") value=" + AXIS_MAX
                        + " [separate trigger]", true);
                break;
            case KIND_STICK: {
                // Latch the mode for the whole gesture from the live GOAL state.
                // Gwarp-dpad: the warp/teleporter destination picker is D-pad
                // driven like the menus, so it gets the same stick->d-pad
                // mapping; it reverts to analog once the warp UI closes.
                // Freecam (mode 2) always flies analog.
                boolean inMenu = queryMenu();
                boolean inWarp = queryWarp();
                t.stickMenuMode = (inMenu || inWarp) && mbMode != 2;
                logActuate(t, t.stickMenuMode ? "menu-dpad" : "left-stick",
                        "down mode=" + (t.stickMenuMode ? "MENU(d-pad)" : "GAMEPLAY(analog)")
                                + " (native isInMenu=" + inMenu + " isInWarp=" + inWarp + ")", true);
                updateStick(t, x, y);
                break;
            }
            default:
                break;
        }
    }

    // Update the left control from a finger position. In gameplay it is the
    // analog stick (LEFTX/LEFTY); in a menu it is a digital d-pad.
    private void updateStick(Touch t, float x, float y) {
        float dx = x - cLeftStick.cx;
        float dy = y - cLeftStick.cy;
        float maxR = cLeftStick.radius * 0.62f;
        float dead = maxR * 0.22f;

        if (t.stickMenuMode) {
            boolean up = dy < -dead, down = dy > dead;
            boolean left = dx < -dead, right = dx > dead;
            // Edge-trigger each direction so we don't spam press/press.
            setDpad(t, SDL_GAMEPAD_BUTTON_DPAD_UP, up, t.dUp);    t.dUp = up;
            setDpad(t, SDL_GAMEPAD_BUTTON_DPAD_DOWN, down, t.dDown); t.dDown = down;
            setDpad(t, SDL_GAMEPAD_BUTTON_DPAD_LEFT, left, t.dLeft); t.dLeft = left;
            setDpad(t, SDL_GAMEPAD_BUTTON_DPAD_RIGHT, right, t.dRight); t.dRight = right;
            if (up || down || left || right) {
                logActuateThrottled(t, "menu-dpad", "drag -> onPadButton(DPAD"
                        + (up ? "_UP" : "") + (down ? "_DOWN" : "")
                        + (left ? "_LEFT" : "") + (right ? "_RIGHT" : "") + ") pressed=1");
            }
        } else {
            float nx = dx, ny = dy;
            float d = (float) Math.hypot(nx, ny);
            if (d < dead) { nx = 0; ny = 0; }
            else if (d > maxR) { nx = nx / d * maxR; ny = ny / d * maxR; }
            int vx = (int) (nx / maxR * AXIS_MAX);
            int vy = (int) (ny / maxR * AXIS_MAX); // up == finger above == negative == forward
            NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_LEFTX, clampAxis(vx));
            NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_LEFTY, clampAxis(vy));
            logActuateThrottled(t, "left-stick", "deflect -> onPadAxis(LEFTX) value="
                    + clampAxis(vx) + ", onPadAxis(LEFTY) value=" + clampAxis(vy));
        }
    }

    private void setDpad(Touch t, int sdlButton, boolean now, boolean was) {
        if (now == was) return;
        NativeGk.onPadButton(sdlButton, now);
    }

    private void releaseDpad(Touch t) {
        if (t.dUp)    { NativeGk.onPadButton(SDL_GAMEPAD_BUTTON_DPAD_UP, false);    t.dUp = false; }
        if (t.dDown)  { NativeGk.onPadButton(SDL_GAMEPAD_BUTTON_DPAD_DOWN, false);  t.dDown = false; }
        if (t.dLeft)  { NativeGk.onPadButton(SDL_GAMEPAD_BUTTON_DPAD_LEFT, false);  t.dLeft = false; }
        if (t.dRight) { NativeGk.onPadButton(SDL_GAMEPAD_BUTTON_DPAD_RIGHT, false); t.dRight = false; }
    }

    // Right-camera max-deflection radius in px: full stick (=AXIS_MAX) at
    // CAM_RADIUS_FRAC of the view height of finger travel from the anchor.
    private float camMaxRadius() {
        return Math.max(60f, getHeight() * CAM_RADIUS_FRAC);
    }

    // Floating right-stick deflection. Pure function of the offset (cur -
    // anchor) from the touch-down anchor: a small radial deadzone, then clamp
    // to maxR and normalize to +/-AXIS_MAX. Because it reads the CURRENT offset
    // (NOT a frame-to-frame delta), a held finger yields a SUSTAINED,
    // non-decaying value — exactly like a physical right stick held deflected.
    // Returns {RIGHTX, RIGHTY}. The same direction sense as the old swipe:
    // finger right/below the anchor => +RIGHTX / +RIGHTY.
    static int[] camDeflection(float dx, float dy, float maxR) {
        float dead = maxR * CAM_DEADZONE_FRAC;
        float d = (float) Math.hypot(dx, dy);
        if (d < dead) return new int[]{0, 0};
        float ox = dx, oy = dy;
        if (d > maxR) { ox = dx / d * maxR; oy = dy / d * maxR; }
        int vx = clampAxis((int) (ox / maxR * AXIS_MAX));
        int vy = clampAxis((int) (oy / maxR * AXIS_MAX));
        return new int[]{vx, vy};
    }

    private static int clampAxis(int v) {
        if (v > AXIS_MAX) return AXIS_MAX;
        if (v < -AXIS_MAX) return -AXIS_MAX;
        return v;
    }

    private boolean queryMenu() {
        try {
            return NativeGk.isInMenu();
        } catch (UnsatisfiedLinkError e) {
            return false;
        }
    }

    // Gwarp-dpad: is the warp/teleporter destination-selection UI open? Gets
    // the same stick->d-pad treatment as the menus; only the stick-mode latch
    // and the glyph consult this — menu tap routing stays on queryMenu() alone.
    private boolean queryWarp() {
        try {
            return NativeGk.isInWarp();
        } catch (UnsatisfiedLinkError e) {
            return false;
        }
    }

    // Grecharged-mesh-browser V2: the browser MODE (0=off, 1=list-UI raw
    // touch with the pad suspended, 2=FREECAM with the pad LIVE). Falls back
    // to the boolean getter (as mode 1) if the int JNI is missing, so an old
    // native lib degrades to the pre-V2 behavior instead of a dead browser.
    private int queryBrowserMode() {
        try {
            return NativeGk.meshBrowserMode();
        } catch (UnsatisfiedLinkError e) {
            try {
                return NativeGk.isInMeshBrowser() ? 1 : 0;
            } catch (UnsatisfiedLinkError e2) {
                return 0;
            }
        }
    }

    // ---------------------------------------------------------------------
    // Grecharged-mesh-browser REOPEN: raw multi-touch forwarding
    // ---------------------------------------------------------------------

    private boolean handleBrowserTouch(MotionEvent ev) {
        keepAwake();
        final int vw = getWidth(), vh = getHeight();
        if (vw <= 0 || vh <= 0) return true;
        int n = ev.getPointerCount();
        int act;
        switch (ev.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: act = 0; break;
            case MotionEvent.ACTION_MOVE:         act = 1; break;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:   act = 2; n = Math.max(0, n - 1); break;
            case MotionEvent.ACTION_CANCEL:       act = 3; n = 0; break;
            default: return true;
        }
        // The pointer that is going up is still present in the event; exclude it so the
        // coordinates we forward describe the fingers that REMAIN down.
        final int skip = (act == 2) ? ev.getActionIndex() : -1;
        final float[] xs = new float[2];
        final float[] ys = new float[2];
        int k = 0;
        for (int i = 0; i < ev.getPointerCount() && k < 2; i++) {
            if (i == skip) continue;
            xs[k] = ev.getX(i) / (float) vw;
            ys[k] = ev.getY(i) / (float) vh;
            k++;
        }
        NativeGk.onBrowserTouch(act, n, xs[0], ys[0], xs[1], ys[1]);
        logBrowserTouch(act, n, xs[0], ys[0], xs[1], ys[1]);
        return true;
    }

    // The `overlay-browser:` marker line the device harness greps to prove the
    // Java -> native chain actually fired. Every DOWN/UP/CANCEL is logged
    // unthrottled; MOVE is throttled to one line per 120 ms so a drag cannot
    // flood logcat (and drop the very lines we need).
    private void logBrowserTouch(int act, int n, float x0, float y0, float x1, float y1) {
        if (act == 1) {
            long now = SystemClock.uptimeMillis();
            if (now - lastBrowserLogMs < 120) return;
            lastBrowserLogMs = now;
        }
        Log.i(TAG, "overlay-browser: act=" + act + " n=" + n + " x0=" + String.format(Locale.ROOT, "%.4f", x0) + " y0=" + String.format(Locale.ROOT, "%.4f", y0) + " x1=" + String.format(Locale.ROOT, "%.4f", x1) + " y1=" + String.format(Locale.ROOT, "%.4f", y1) + " -> NativeGk.onBrowserTouch");
    }

    // ---------------------------------------------------------------------
    // Visibility / fade
    // ---------------------------------------------------------------------

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        // Stay hidden until the first touch; the heartbeat only runs while shown.
        lastTouchMs = SystemClock.uptimeMillis();
    }

    @Override
    protected void onDetachedFromWindow() {
        stopHeartbeat();
        super.onDetachedFromWindow();
    }

    // Called on every touch event: refresh idle timer, show if hidden.
    private void keepAwake() {
        lastTouchMs = SystemClock.uptimeMillis();
        if (!shown) fadeIn();
        startHeartbeat();
    }

    private void fadeIn() {
        shown = true;
        animate().cancel();
        animate().alpha(1f).setDuration(FADE_IN_MS).start();
        Log.i(TAG, "overlay-visibility: shown (touch -> wake -> alpha=1)");
    }

    private void fadeOut() {
        shown = false;
        animate().cancel();
        animate().alpha(0f).setDuration(FADE_OUT_MS).start();
        Log.i(TAG, "overlay-visibility: faded (10s / 10000ms idle, no touch -> alpha=0, hidden)");
    }

    // Ginput-replay-realinput (autoport): keep the controls visible (no idle fade)
    // while an input record/replay is armed, so the owner can SEE and use the touch
    // controls to capture a demo — a record must never silently produce all-neutral
    // because the only available input source was an invisible overlay.
    public void setPersistentVisible(boolean p) {
        persistentVisible = p;
        if (p) {
            lastTouchMs = SystemClock.uptimeMillis();
            if (!shown) fadeIn();
            startHeartbeat();
            Log.i(TAG, "overlay-visibility: PERSISTENT (input record/replay armed) — "
                    + "controls stay visible so touch is a usable, recordable input");
        }
    }

    // Grecharged-mesh-browser REOPEN (owner 2026-07-29): suppress the VIRTUAL
    // GAMEPAD role without removing the view.
    //
    // Reason: MainActivity used to skip constructing/addView-ing this overlay
    // entirely when the "touch_overlay_enabled" preference was false. That
    // preference is written ONCE, on the first launch of a fresh install, as
    // (gamepadsAtStart == 0) — so a pad that merely happened to be attached at
    // that one launch disabled the overlay FOREVER, even after unplugging. The
    // debug mesh browser sends every finger event through this view, and the
    // owner has no permanently-attached gamepad and no adb to fix a bad pref, so
    // an absent view = a browser that can never be driven by touch. The view is
    // therefore always added now, and "disabled" means only this: the pad is
    // inert (draws nothing, actuates nothing), while browser touches still flow.
    public void setPadSuppressed(boolean s) { padSuppressed = s; if (s) releaseAll(); invalidate(); }

    private void startHeartbeat() {
        if (heartbeatRunning) return;
        heartbeatRunning = true;
        handler.postDelayed(heartbeat, HEARTBEAT_MS);
    }

    private void stopHeartbeat() {
        heartbeatRunning = false;
        handler.removeCallbacks(heartbeat);
    }

    private final Runnable heartbeat = new Runnable() {
        @Override public void run() {
            if (!heartbeatRunning) return;
            long idle = SystemClock.uptimeMillis() - lastTouchMs;
            if (shown && idle >= IDLE_FADE_MS && active.size() == 0 && !persistentVisible) {
                fadeOut();
                stopHeartbeat(); // nothing to poll while hidden; touch restarts us
                return;
            }
            // Poll menu mode so the left control's glyph (stick vs d-pad)
            // tracks the game state even without a touch. The warp selection
            // UI (Gwarp-dpad) shows the d-pad glyph too.
            boolean m = queryMenu() || queryWarp();
            if (m != lastMenuMode) {
                lastMenuMode = m;
                Log.i(TAG, "overlay-mode: left-control now "
                        + (m ? "MENU(d-pad)" : "GAMEPLAY(analog stick)"));
                invalidate();
            }
            // Grecharged-mesh-browser V2: poll the browser MODE too, so mbMode
            // (and the glyph set) tracks the game state even when the owner is
            // not touching the screen.
            int mode = queryBrowserMode();
            if (mode != mbMode) {
                mbMode = mode;
                releaseAll();   // never leave a button/stick/trigger latched across a mode switch
                if (mode != 0) {
                    // If a gamepad was connected BEFORE the browser was opened, MainActivity has
                    // already View.GONE'd us — and GONE means no hit-testing, so not one browser
                    // gesture (or freecam button) would land. The browser is finger-driven by
                    // design, so it takes priority: make ourselves hit-testable again. We stay
                    // alpha-0 until touched, so a pad user sees nothing appear.
                    if (getVisibility() != VISIBLE) {
                        setVisibility(VISIBLE);
                        Log.i(TAG, "overlay-visibility: forced VISIBLE for the mesh browser "
                                + "(was GONE because a gamepad is connected; GONE would have "
                                + "swallowed every browser gesture)");
                    }
                }
                if (mode == 2) {
                    // FREECAM: show the control set immediately — the owner
                    // must SEE the buttons to know the freecam is finger-drivable.
                    lastTouchMs = SystemClock.uptimeMillis();
                    if (!shown) fadeIn();
                }
                Log.i(TAG, "overlay-mode: mesh browser "
                        + (mode == 1 ? "OPEN mode=1 (list-UI: raw multi-touch -> onBrowserTouch, virtual pad suspended)"
                           : mode == 2 ? "OPEN mode=2 (FREECAM: virtual pad LIVE, freecam control set)"
                                       : "CLOSED mode=0 (normal virtual pad restored)"));
                // Re-dump the control map on every browser-mode change: the view can RESIZE
                // mid-session (MIUI inset settling took us 2298x934 -> 2400x1080) and the layout
                // is proportional, so a map harvested at open aims ~95px off afterwards — enough
                // to miss every circle button while still landing inside the wide pills. A fresh
                // dump within 250ms of each mode flip gives any coordinate consumer (the proof
                // harness, or a human debugging by log) the CURRENT geometry.
                if (getWidth() > 0 && getHeight() > 0) logOverlayMap(getWidth(), getHeight());
                invalidate();
            }
            handler.postDelayed(this, HEARTBEAT_MS);
        }
    };

    // ---------------------------------------------------------------------
    // Actuation logging (the same-behavior contract trail)
    // ---------------------------------------------------------------------

    private void logActuate(Touch t, String name, String what, boolean force) {
        Log.i(TAG, "overlay-actuate: " + name + " " + what);
    }

    private void logActuateThrottled(Touch t, String name, String what) {
        long now = SystemClock.uptimeMillis();
        if (t.ctl != null) {
            if (now - t.ctl.lastLogMs < 150) return;
            t.ctl.lastLogMs = now;
        } else {
            if (now - t.lastLogMs < 150) return;
            t.lastLogMs = now;
        }
        Log.i(TAG, "overlay-actuate: " + name + " " + what);
    }
}
