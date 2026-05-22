// Phase E2 (autoport): optional on-screen PS2-button overlay.
//
// Sits on top of the SDLSurface inside SDLActivity.mLayout (RelativeLayout,
// last-added child is topmost). Eight circular hit-zones for the four face
// buttons and the d-pad. Taps within a hit-zone synthesise a
// NativeGk.onPadButton(sdl_button, pressed) JNI call whose shape is
// byte-equivalent to the call a real Bluetooth gamepad would issue via
// the SDL_EVENT_GAMEPAD_BUTTON_* → process_sdl_event path — that's the
// "same-behavior contract" the E2 validator enforces with trace-diff.
//
// Hit-zone → SDL_GAMEPAD_BUTTON mapping mirrors the desktop default in
// game/system/hid/input_bindings.cpp:DEFAULT_KEYBOARD_BINDS — × → SOUTH,
// ○ → EAST, □ → WEST, △ → NORTH, plus the d-pad and START. The exact
// per-button SDL enum values are emitted to logcat at layout time so
// e2_run.sh can serialise them to .autoport/reports/E2-overlay-map.json
// and drive synthetic taps at the right pixel coordinates without
// duplicating the layout math.
//
// Touch dispatch: hits inside a hit-zone return true (event consumed);
// hits outside return false so RelativeLayout's dispatch loop walks
// down to the SDLSurface below us. SDL therefore still receives any
// taps not aimed at our buttons, which keeps the desktop input
// pipeline (which is what game/system/hid/sdl_util.cpp also consumes)
// fully reachable.

package org.opengoal.gk;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class TouchOverlayView extends View {
    private static final String TAG = "opengoal-gk";

    // SDL3 SDL_GAMEPAD_BUTTON_* constants. Hard-coded here so this class
    // doesn't need to JNI just to learn the enum values. A static_assert
    // in android_input_audio.cpp::button_name traps any future SDL
    // renumbering; if that fires we update both sides together.
    public static final int SDL_GAMEPAD_BUTTON_SOUTH = 0;       // ×
    public static final int SDL_GAMEPAD_BUTTON_EAST = 1;        // ○
    public static final int SDL_GAMEPAD_BUTTON_WEST = 2;        // □
    public static final int SDL_GAMEPAD_BUTTON_NORTH = 3;       // △
    public static final int SDL_GAMEPAD_BUTTON_BACK = 4;
    public static final int SDL_GAMEPAD_BUTTON_START = 6;
    public static final int SDL_GAMEPAD_BUTTON_DPAD_UP = 11;
    public static final int SDL_GAMEPAD_BUTTON_DPAD_DOWN = 12;
    public static final int SDL_GAMEPAD_BUTTON_DPAD_LEFT = 13;
    public static final int SDL_GAMEPAD_BUTTON_DPAD_RIGHT = 14;

    private static final class Hit {
        final String name;
        final int sdlButton;
        float cx, cy, radius;
        int pointerId = -1; // -1 = not pressed

        Hit(String name, int sdlButton) {
            this.name = name;
            this.sdlButton = sdlButton;
        }
    }

    private final List<Hit> hits = new ArrayList<>();
    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint label = new Paint(Paint.ANTI_ALIAS_FLAG);

    private boolean mapLogged = false;

    public TouchOverlayView(Context context) {
        super(context);
        // Don't steal focus from the SDL SurfaceView; we only care about
        // direct touch dispatch.
        setFocusable(false);
        setFocusableInTouchMode(false);
        setClickable(false);

        hits.add(new Hit("south", SDL_GAMEPAD_BUTTON_SOUTH));
        hits.add(new Hit("east", SDL_GAMEPAD_BUTTON_EAST));
        hits.add(new Hit("west", SDL_GAMEPAD_BUTTON_WEST));
        hits.add(new Hit("north", SDL_GAMEPAD_BUTTON_NORTH));
        hits.add(new Hit("dpad_up", SDL_GAMEPAD_BUTTON_DPAD_UP));
        hits.add(new Hit("dpad_down", SDL_GAMEPAD_BUTTON_DPAD_DOWN));
        hits.add(new Hit("dpad_left", SDL_GAMEPAD_BUTTON_DPAD_LEFT));
        hits.add(new Hit("dpad_right", SDL_GAMEPAD_BUTTON_DPAD_RIGHT));
        hits.add(new Hit("start", SDL_GAMEPAD_BUTTON_START));

        fill.setColor(Color.argb(0x60, 0x20, 0x20, 0x20));
        stroke.setColor(Color.argb(0xC0, 0xE0, 0xE0, 0xE0));
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(4f);
        label.setColor(Color.argb(0xFF, 0xF0, 0xF0, 0xF0));
        label.setTextAlign(Paint.Align.CENTER);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        layoutHits(w, h);
        label.setTextSize(Math.max(20f, h * 0.025f));
        if (!mapLogged && w > 0 && h > 0) {
            mapLogged = true;
            logOverlayMap(w, h);
        }
        invalidate();
    }

    private void layoutHits(int w, int h) {
        // Landscape clusters. r is hit-zone radius; clusters live at
        // ~75% of the way down the screen (above the gesture nav region
        // on most devices) and 12% / 88% horizontally so they sit on
        // either edge.
        final float r = Math.max(40f, h * 0.075f);
        final float spacing = r * 1.6f; // centre-to-centre

        final float dpadCx = w * 0.12f;
        final float dpadCy = h * 0.72f;
        setHit("dpad_up",    dpadCx,           dpadCy - spacing, r);
        setHit("dpad_down",  dpadCx,           dpadCy + spacing, r);
        setHit("dpad_left",  dpadCx - spacing, dpadCy,           r);
        setHit("dpad_right", dpadCx + spacing, dpadCy,           r);

        final float faceCx = w * 0.88f;
        final float faceCy = h * 0.72f;
        setHit("south", faceCx,           faceCy + spacing, r); // ×
        setHit("east",  faceCx + spacing, faceCy,           r); // ○
        setHit("west",  faceCx - spacing, faceCy,           r); // □
        setHit("north", faceCx,           faceCy - spacing, r); // △

        setHit("start", w * 0.5f, h * 0.92f, r * 0.7f);
    }

    private void setHit(String name, float cx, float cy, float r) {
        for (Hit h : hits) {
            if (h.name.equals(name)) {
                h.cx = cx; h.cy = cy; h.radius = r;
                return;
            }
        }
    }

    private void logOverlayMap(int w, int h) {
        // One key=val token per hit-zone: e.g. `south=cx,cy,r`. e2_run.sh
        // greps the `overlay-map:` line, parses these, and serialises them
        // to .autoport/reports/E2-overlay-map.json. Pixel coords are the
        // raw view-local values — for our full-screen MATCH_PARENT overlay
        // these equal the device screen coordinates that `adb shell input
        // tap` consumes.
        StringBuilder sb = new StringBuilder();
        sb.append("overlay-map: screen=").append(w).append('x').append(h);
        for (Hit h2 : hits) {
            sb.append(' ').append(h2.name).append('=');
            sb.append((int) h2.cx).append(',').append((int) h2.cy);
            sb.append(',').append((int) h2.radius);
            sb.append(',').append(h2.sdlButton);
        }
        Log.i(TAG, sb.toString());
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        for (Hit h : hits) {
            if (h.radius <= 0) continue;
            canvas.drawCircle(h.cx, h.cy, h.radius, fill);
            canvas.drawCircle(h.cx, h.cy, h.radius, stroke);
            String tag = labelFor(h.name);
            float ty = h.cy + label.getTextSize() * 0.35f;
            canvas.drawText(tag, h.cx, ty, label);
        }
    }

    private static String labelFor(String name) {
        switch (name) {
            case "south":      return "X";
            case "east":       return "O";
            case "west":       return "[]";
            case "north":      return "/\\";
            case "dpad_up":    return "^";
            case "dpad_down":  return "v";
            case "dpad_left":  return "<";
            case "dpad_right": return ">";
            case "start":      return "START";
            default:           return name;
        }
    }

    @Override
    public boolean onTouchEvent(MotionEvent ev) {
        final int action = ev.getActionMasked();
        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: {
                final int idx = (action == MotionEvent.ACTION_POINTER_DOWN)
                        ? ev.getActionIndex() : 0;
                final int pid = ev.getPointerId(idx);
                final float x = ev.getX(idx);
                final float y = ev.getY(idx);
                Hit h = findHit(x, y);
                if (h == null) {
                    return false; // miss — let SDLSurface have it
                }
                h.pointerId = pid;
                dispatchPad(h, true);
                return true;
            }
            case MotionEvent.ACTION_MOVE: {
                // Don't change press state on drag; once pressed, stays
                // pressed until the originating pointer lifts.
                return anyPressed();
            }
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:
            case MotionEvent.ACTION_CANCEL: {
                final int idx = (action == MotionEvent.ACTION_POINTER_UP)
                        ? ev.getActionIndex() : 0;
                final int pid = ev.getPointerId(idx);
                boolean handled = false;
                for (Hit h : hits) {
                    if (h.pointerId == pid) {
                        h.pointerId = -1;
                        dispatchPad(h, false);
                        handled = true;
                    }
                }
                if (action == MotionEvent.ACTION_CANCEL) {
                    // Release everything still held; safer than leaving
                    // phantom presses if the OS yanks our gesture.
                    for (Hit h : hits) {
                        if (h.pointerId != -1) {
                            h.pointerId = -1;
                            dispatchPad(h, false);
                            handled = true;
                        }
                    }
                }
                return handled;
            }
            default:
                return false;
        }
    }

    private Hit findHit(float x, float y) {
        Hit best = null;
        float bestDist2 = Float.MAX_VALUE;
        for (Hit h : hits) {
            float dx = x - h.cx, dy = y - h.cy;
            float d2 = dx * dx + dy * dy;
            if (d2 <= h.radius * h.radius && d2 < bestDist2) {
                best = h;
                bestDist2 = d2;
            }
        }
        return best;
    }

    private boolean anyPressed() {
        for (Hit h : hits) if (h.pointerId != -1) return true;
        return false;
    }

    private void dispatchPad(Hit h, boolean pressed) {
        // Marker line keyed by the E2 validator's
        // `onPadButton.*from=overlay` regex. Leading `onPadButton:` token
        // mirrors the JNI-side gamepad log shape AND matches the
        // trace_diff Android-drop pattern (`onPadButton:`) so this
        // platform-only line doesn't burn the trace-diff event budget.
        // Emitted BEFORE the JNI call so even a crash in native code
        // still leaves the marker visible.
        Log.i(TAG, String.format(Locale.ROOT,
                "onPadButton: overlay tap -> sdl_button=%d pressed=%d name=%s from=overlay",
                h.sdlButton, pressed ? 1 : 0, h.name));
        NativeGk.onPadButton(h.sdlButton, pressed);
    }
}
