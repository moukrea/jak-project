// Phase 11 (autoport): minimal touch-controls scaffolding.
//
// Renders a virtual analog stick (left side) and four face buttons
// (right side) over the activity's content view. The point of this is
// to prove the input pipeline works end-to-end — touch events arrive,
// get translated into logical pad inputs, and would be forwarded to
// libgk.so once the SDL input bridge lands.
//
// For now, events are logged via android.util.Log so they show up in
// `adb logcat`. No actual game input is dispatched.

package org.opengoal.gk;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;

public class TouchControlsView extends View {
    private static final String TAG = "opengoal-input";

    // Knob geometry — recomputed on every layout pass.
    private float stickBaseX, stickBaseY, stickRadius;
    private float stickKnobX, stickKnobY;
    private int stickPointerId = -1;

    // Face button geometry.
    private float[][] buttons = new float[4][3]; // [i] = {cx, cy, radius}
    private static final String[] BUTTON_LABELS = {"A", "B", "X", "Y"};

    private final Paint paintFill;
    private final Paint paintStroke;
    private final Paint paintText;

    public TouchControlsView(Context ctx) {
        super(ctx);
        setBackgroundColor(Color.TRANSPARENT);

        paintFill = new Paint(Paint.ANTI_ALIAS_FLAG);
        paintFill.setColor(0x60FFFFFF);
        paintFill.setStyle(Paint.Style.FILL);

        paintStroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        paintStroke.setColor(0xC0FFFFFF);
        paintStroke.setStyle(Paint.Style.STROKE);
        paintStroke.setStrokeWidth(4f);

        paintText = new Paint(Paint.ANTI_ALIAS_FLAG);
        paintText.setColor(0xFFFFFFFF);
        paintText.setTextSize(48f);
        paintText.setTextAlign(Paint.Align.CENTER);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);

        // Stick: lower-left quadrant.
        stickRadius = Math.min(w, h) * 0.12f;
        stickBaseX = stickRadius * 1.6f;
        stickBaseY = h - stickRadius * 1.6f;
        stickKnobX = stickBaseX;
        stickKnobY = stickBaseY;

        // Buttons: lower-right diamond.
        float br = Math.min(w, h) * 0.06f;
        float cx = w - br * 4f;
        float cy = h - br * 4f;
        // A bottom, B right, X left, Y top — Xbox-ish layout.
        buttons[0] = new float[]{cx, cy + br * 2f, br};
        buttons[1] = new float[]{cx + br * 2f, cy, br};
        buttons[2] = new float[]{cx - br * 2f, cy, br};
        buttons[3] = new float[]{cx, cy - br * 2f, br};
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);

        // Stick base + knob.
        canvas.drawCircle(stickBaseX, stickBaseY, stickRadius, paintStroke);
        canvas.drawCircle(stickKnobX, stickKnobY, stickRadius * 0.4f, paintFill);

        // Face buttons.
        for (int i = 0; i < buttons.length; i++) {
            float bx = buttons[i][0];
            float by = buttons[i][1];
            float br = buttons[i][2];
            canvas.drawCircle(bx, by, br, paintFill);
            canvas.drawCircle(bx, by, br, paintStroke);
            // text vertical centering via FontMetrics
            Paint.FontMetrics fm = paintText.getFontMetrics();
            float ty = by - (fm.ascent + fm.descent) / 2f;
            canvas.drawText(BUTTON_LABELS[i], bx, ty, paintText);
        }
    }

    @Override
    public boolean onTouchEvent(MotionEvent ev) {
        int action = ev.getActionMasked();
        int pointerIndex = ev.getActionIndex();
        int pointerId = ev.getPointerId(pointerIndex);
        float x = ev.getX(pointerIndex);
        float y = ev.getY(pointerIndex);

        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: {
                if (stickPointerId == -1
                        && dist(x, y, stickBaseX, stickBaseY) <= stickRadius * 1.5f) {
                    stickPointerId = pointerId;
                    updateStick(x, y);
                    Log.d(TAG, "stick down");
                } else {
                    int btn = hitButton(x, y);
                    if (btn >= 0) {
                        Log.d(TAG, "button down: " + BUTTON_LABELS[btn]);
                    }
                }
                return true;
            }
            case MotionEvent.ACTION_MOVE: {
                for (int i = 0; i < ev.getPointerCount(); i++) {
                    if (ev.getPointerId(i) == stickPointerId) {
                        updateStick(ev.getX(i), ev.getY(i));
                        invalidate();
                    }
                }
                return true;
            }
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:
            case MotionEvent.ACTION_CANCEL: {
                if (pointerId == stickPointerId) {
                    stickPointerId = -1;
                    stickKnobX = stickBaseX;
                    stickKnobY = stickBaseY;
                    invalidate();
                    Log.d(TAG, "stick up");
                }
                return true;
            }
            default:
                return super.onTouchEvent(ev);
        }
    }

    private void updateStick(float x, float y) {
        float dx = x - stickBaseX;
        float dy = y - stickBaseY;
        float d = (float) Math.hypot(dx, dy);
        if (d > stickRadius) {
            dx = dx / d * stickRadius;
            dy = dy / d * stickRadius;
        }
        stickKnobX = stickBaseX + dx;
        stickKnobY = stickBaseY + dy;
    }

    private int hitButton(float x, float y) {
        for (int i = 0; i < buttons.length; i++) {
            if (dist(x, y, buttons[i][0], buttons[i][1]) <= buttons[i][2]) {
                return i;
            }
        }
        return -1;
    }

    private static float dist(float ax, float ay, float bx, float by) {
        return (float) Math.hypot(ax - bx, ay - by);
    }
}
