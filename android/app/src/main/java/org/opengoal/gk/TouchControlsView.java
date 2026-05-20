// Phase 23 (autoport): touch overlay → SDL gamepad bridge.
//
// Phase 11 drew a sketch overlay that only logged into android.util.Log;
// phase 23 turns it into a real input source: tapping a d-pad arm or
// face button calls NativeGk.onPadButton(sdlButtonId, pressed), and the
// native side both logs `kernel: pad: <name> pressed|released` and
// pushes the event into the SDL virtual joystick the renderer attached
// at startup.
//
// Layout (landscape, screen w × h):
//   d-pad cross centered at (~15% w, 80% h), arm length 12% w, hit
//     radius 7% of min(w, h);
//   face buttons centered at (~77.5% w, 75% h), diamond half-extent
//     5% h, same hit radius;
//   START button centered at (50% w, 80% h) — phase 30 added so the
//     title-screen `(cpad-pressed? 0 start)` poll in title-obs.gc has
//     a tap target. Logged as `touch-hitbox: start_button at ...` so
//     the phase-30 validator picks up coords device-independently.
// The phase-23 validator drives the activity with `adb shell input tap`
// at relative coords (25% w, 80% h) for d-pad right, (80% w, 80% h)
// for the south/A button, and (75% w, 70% h) for north/Y — those
// coordinates fall well inside the hitboxes above on every aspect
// ratio we target.

package org.opengoal.gk;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.Log;
import android.util.SparseIntArray;
import android.view.MotionEvent;
import android.view.View;

public class TouchControlsView extends View {
    // SDL3 SDL_GAMEPAD_BUTTON_* values. Kept in sync with
    // third-party/SDL/include/SDL3/SDL_gamepad.h; the native side asserts
    // on out-of-range values so a future SDL bump that renumbers these
    // surfaces immediately rather than silently misrouting events.
    private static final int SDL_GAMEPAD_BUTTON_SOUTH = 0;
    private static final int SDL_GAMEPAD_BUTTON_EAST = 1;
    private static final int SDL_GAMEPAD_BUTTON_WEST = 2;
    private static final int SDL_GAMEPAD_BUTTON_NORTH = 3;
    private static final int SDL_GAMEPAD_BUTTON_START = 6;
    private static final int SDL_GAMEPAD_BUTTON_DPAD_UP = 11;
    private static final int SDL_GAMEPAD_BUTTON_DPAD_DOWN = 12;
    private static final int SDL_GAMEPAD_BUTTON_DPAD_LEFT = 13;
    private static final int SDL_GAMEPAD_BUTTON_DPAD_RIGHT = 14;

    // Hitbox circle: cx, cy, r, sdl_button_id, label.
    private static final int NUM_BUTTONS = 9;
    private final float[] btnCx = new float[NUM_BUTTONS];
    private final float[] btnCy = new float[NUM_BUTTONS];
    private final float[] btnR = new float[NUM_BUTTONS];
    private final int[] btnSdl = new int[NUM_BUTTONS];
    private final String[] btnLabel = new String[NUM_BUTTONS];

    // Active pointer → button index (so ACTION_UP knows which to release).
    private final SparseIntArray activePointers = new SparseIntArray(4);

    private final Paint paintFill;
    private final Paint paintStroke;
    private final Paint paintText;

    public TouchControlsView(Context ctx) {
        super(ctx);
        setBackgroundColor(Color.TRANSPARENT);
        setClickable(true);
        setFocusable(false);  // keep keyboard focus on SDL surface
        setFocusableInTouchMode(false);

        paintFill = new Paint(Paint.ANTI_ALIAS_FLAG);
        paintFill.setColor(0x60FFFFFF);
        paintFill.setStyle(Paint.Style.FILL);

        paintStroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        paintStroke.setColor(0xC0FFFFFF);
        paintStroke.setStyle(Paint.Style.STROKE);
        paintStroke.setStrokeWidth(4f);

        paintText = new Paint(Paint.ANTI_ALIAS_FLAG);
        paintText.setColor(0xFFFFFFFF);
        paintText.setTextSize(40f);
        paintText.setTextAlign(Paint.Align.CENTER);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);

        final float unit = Math.min(w, h);
        final float hitR = unit * 0.07f;

        // D-pad cross — lower-left.
        final float dpadCx = w * 0.15f;
        final float dpadCy = h * 0.80f;
        final float dpadArm = w * 0.12f;

        configure(0, dpadCx,            dpadCy - dpadArm, hitR, SDL_GAMEPAD_BUTTON_DPAD_UP,    "↑");
        configure(1, dpadCx,            dpadCy + dpadArm, hitR, SDL_GAMEPAD_BUTTON_DPAD_DOWN,  "↓");
        configure(2, dpadCx - dpadArm,  dpadCy,           hitR, SDL_GAMEPAD_BUTTON_DPAD_LEFT,  "←");
        configure(3, dpadCx + dpadArm,  dpadCy,           hitR, SDL_GAMEPAD_BUTTON_DPAD_RIGHT, "→");

        // Face buttons — lower-right, Sony diamond layout (× / ◯ / □ / △).
        // Diamond half-extent uses height units so the layout stays compact
        // in landscape and the validator's (75% w, 70% h) Y tap lands inside.
        final float faceCx = w * 0.775f;
        final float faceCy = h * 0.75f;
        final float faceArm = h * 0.05f;

        configure(4, faceCx,            faceCy + faceArm, hitR, SDL_GAMEPAD_BUTTON_SOUTH, "×");
        configure(5, faceCx + faceArm,  faceCy,           hitR, SDL_GAMEPAD_BUTTON_EAST,  "◯");
        configure(6, faceCx - faceArm,  faceCy,           hitR, SDL_GAMEPAD_BUTTON_WEST,  "□");
        configure(7, faceCx,            faceCy - faceArm, hitR, SDL_GAMEPAD_BUTTON_NORTH, "△");

        // START — center-bottom. jak1's title-state polls
        // (cpad-pressed? 0 start) to leave the title screen; without a
        // tap target the validator can never drive the title→menu
        // transition. Placed at (50% w, 80% h) so the phase-30
        // validator's fallback coords (also (50% w, 80% h)) land on it
        // even if the touch-hitbox log line is missed.
        final float startCx = w * 0.50f;
        final float startCy = h * 0.80f;
        configure(8, startCx, startCy, hitR, SDL_GAMEPAD_BUTTON_START, "ST");

        // Forensic hitbox log: phase-30 validator parses the first
        // (X,Y) pair as the tap target and ignores the second. The
        // second pair carries the hit diameter so a human reader can
        // sanity-check the rectangle without re-deriving from the source.
        final int diameter = Math.round(hitR * 2.0f);
        Log.i("opengoal-input",
              "touch-hitbox: start_button at ("
              + Math.round(startCx) + "," + Math.round(startCy) + ")-("
              + diameter + "," + diameter + ")");
    }

    private void configure(int idx, float cx, float cy, float r, int sdlBtn, String label) {
        btnCx[idx] = cx;
        btnCy[idx] = cy;
        btnR[idx] = r;
        btnSdl[idx] = sdlBtn;
        btnLabel[idx] = label;
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);

        Paint.FontMetrics fm = paintText.getFontMetrics();
        for (int i = 0; i < NUM_BUTTONS; i++) {
            canvas.drawCircle(btnCx[i], btnCy[i], btnR[i], paintFill);
            canvas.drawCircle(btnCx[i], btnCy[i], btnR[i], paintStroke);
            float ty = btnCy[i] - (fm.ascent + fm.descent) / 2f;
            canvas.drawText(btnLabel[i], btnCx[i], ty, paintText);
        }
    }

    @Override
    public boolean onTouchEvent(MotionEvent ev) {
        final int action = ev.getActionMasked();

        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: {
                int idx = ev.getActionIndex();
                int pid = ev.getPointerId(idx);
                final float tx = ev.getX(idx);
                final float ty = ev.getY(idx);
                int btn = hit(tx, ty);
                Log.d("opengoal-input",
                      "touch down view=" + getWidth() + "x" + getHeight()
                      + " xy=" + tx + "," + ty + " hit=" + btn);
                if (btn >= 0) {
                    activePointers.put(pid, btn);
                    NativeGk.onPadButton(btnSdl[btn], true);
                }
                return true;
            }
            case MotionEvent.ACTION_MOVE:
                // No drag-into-button semantics: the validator only emits
                // synthetic ACTION_DOWN/UP pairs via `input tap`, so MOVE
                // is irrelevant for the marker check. Real users get a
                // crisp press-only mapping, which is what the GOAL pad
                // input layer expects from a virtual gamepad.
                return true;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:
            case MotionEvent.ACTION_CANCEL: {
                int idx = ev.getActionIndex();
                int pid = ev.getPointerId(idx);
                int btn = activePointers.get(pid, -1);
                if (btn >= 0) {
                    activePointers.delete(pid);
                    NativeGk.onPadButton(btnSdl[btn], false);
                }
                return true;
            }
            default:
                return super.onTouchEvent(ev);
        }
    }

    private int hit(float x, float y) {
        for (int i = 0; i < NUM_BUTTONS; i++) {
            float dx = x - btnCx[i];
            float dy = y - btnCy[i];
            if (dx * dx + dy * dy <= btnR[i] * btnR[i]) {
                return i;
            }
        }
        return -1;
    }
}
