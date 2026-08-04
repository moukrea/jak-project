// Phase Gtouch-longjump-regression (autoport): file-driven synthetic MULTI-TOUCH
// replay. `adb shell input` is single-pointer and sendevent on the touchscreen
// node is SELinux-denied on MIUI, so the owner's 3-finger long-jump gesture
// (left thumb holding the virtual stick + a finger holding the L1/R1 pill + a
// thumb tapping X) cannot be reproduced from the shell at all. This player reads
// a gesture script and dispatches REAL multi-pointer MotionEvents into
// TouchOverlayView on the UI thread — exercising the exact suspect path
// (per-pointer hit-testing, SparseArray bookkeeping, the JNI
// onPadButton/onPadAxis merge) with deterministic timing.
//
// DEBUG INSTRUMENT ONLY: armed by the PRESENCE of the script file, which is
// consumed (renamed to .done) on pickup; zero behavior change when absent.
//
// Script: /storage/emulated/0/OpenGOAL/touch_replay.txt — one event per line:
//   <t_ms> down <pid> <x_norm> <y_norm>
//   <t_ms> move <pid> <x_norm> <y_norm>
//   <t_ms> up   <pid>
// t_ms is relative to playback start; x/y are normalized 0..1 and multiplied by
// the overlay view's CURRENT size at dispatch time (robust to MIUI inset
// resizes — the same proportional layout the overlay itself uses). '#' comments
// and blank lines are ignored. Events must be sorted by t_ms.

package org.opengoal.gk;

import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.View;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class TouchReplayPlayer {
    private static final String TAG = "opengoal-gk";
    private static final String SCRIPT_PATH =
            "/storage/emulated/0/OpenGOAL/touch_replay.txt";
    private static final long POLL_MS = 1000;

    private static final class Ev {
        long t;
        int kind; // 0=down 1=move 2=up
        int pid;
        float xn, yn;
    }

    // One live pointer during playback. Order of insertion defines the
    // pointer index order used to build MotionEvents, matching how a real
    // touchscreen keeps a stable index while a pointer is down.
    private static final class Ptr {
        int pid;
        float xn, yn;
    }

    private final View mTarget;
    private final Handler mUi = new Handler(Looper.getMainLooper());
    private final List<Ptr> mActive = new ArrayList<>();
    private volatile boolean mWatching = false;
    private boolean mPlaying = false;
    private long mDownTime = 0;

    public TouchReplayPlayer(View target) {
        mTarget = target;
    }

    public void startWatching() {
        if (mWatching) return;
        mWatching = true;
        Thread t = new Thread(() -> {
            Log.i(TAG, "touch-replay: watcher armed on " + SCRIPT_PATH
                    + " (poll " + POLL_MS + "ms; inert until the file appears)");
            while (mWatching) {
                try {
                    File f = new File(SCRIPT_PATH);
                    if (f.isFile()) {
                        List<Ev> evs = parse(f);
                        // Consume: rename so a crash mid-run can't loop us.
                        File done = new File(SCRIPT_PATH + ".done");
                        done.delete();
                        if (!f.renameTo(done)) f.delete();
                        if (evs != null && !evs.isEmpty()) {
                            schedule(evs);
                        } else {
                            Log.w(TAG, "touch-replay: script empty/unparseable, ignored");
                        }
                    }
                    Thread.sleep(POLL_MS);
                } catch (InterruptedException ie) {
                    return;
                } catch (Exception e) {
                    Log.w(TAG, "touch-replay: watcher error: " + e);
                }
            }
        }, "touch-replay-watch");
        t.setDaemon(true);
        t.start();
    }

    public void stopWatching() {
        mWatching = false;
    }

    private static List<Ev> parse(File f) {
        List<Ev> out = new ArrayList<>();
        try (BufferedReader r = new BufferedReader(new FileReader(f))) {
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] tok = line.split("\\s+");
                Ev e = new Ev();
                e.t = Long.parseLong(tok[0]);
                switch (tok[1]) {
                    case "down": e.kind = 0; break;
                    case "move": e.kind = 1; break;
                    case "up":   e.kind = 2; break;
                    default: continue;
                }
                e.pid = Integer.parseInt(tok[2]);
                if (e.kind != 2) {
                    e.xn = Float.parseFloat(tok[3]);
                    e.yn = Float.parseFloat(tok[4]);
                }
                out.add(e);
            }
        } catch (Exception ex) {
            Log.w(TAG, "touch-replay: parse failed: " + ex);
            return null;
        }
        return out;
    }

    private void schedule(List<Ev> evs) {
        mUi.post(() -> {
            if (mPlaying) {
                Log.w(TAG, "touch-replay: already playing, new script dropped");
                return;
            }
            mPlaying = true;
            mActive.clear();
            long base = SystemClock.uptimeMillis() + 500;
            Log.i(TAG, "touch-replay: START " + evs.size() + " events, view="
                    + mTarget.getWidth() + "x" + mTarget.getHeight());
            for (Ev e : evs) {
                mUi.postAtTime(() -> fire(e), base + e.t);
            }
            long endT = evs.get(evs.size() - 1).t;
            mUi.postAtTime(() -> {
                mPlaying = false;
                Log.i(TAG, "touch-replay: DONE (" + evs.size() + " events over "
                        + endT + "ms)");
            }, base + endT + 50);
        });
    }

    private Ptr find(int pid) {
        for (Ptr p : mActive) if (p.pid == pid) return p;
        return null;
    }

    private void fire(Ev e) {
        try {
            int action;
            int index;
            switch (e.kind) {
                case 0: { // down
                    if (find(e.pid) != null) return; // duplicate down, ignore
                    Ptr p = new Ptr();
                    p.pid = e.pid;
                    p.xn = e.xn;
                    p.yn = e.yn;
                    mActive.add(p);
                    index = mActive.size() - 1;
                    if (mActive.size() == 1) {
                        mDownTime = SystemClock.uptimeMillis();
                        action = MotionEvent.ACTION_DOWN;
                    } else {
                        action = MotionEvent.ACTION_POINTER_DOWN
                                | (index << MotionEvent.ACTION_POINTER_INDEX_SHIFT);
                    }
                    dispatch(action, e);
                    break;
                }
                case 1: { // move
                    Ptr p = find(e.pid);
                    if (p == null) return;
                    p.xn = e.xn;
                    p.yn = e.yn;
                    dispatch(MotionEvent.ACTION_MOVE, e);
                    break;
                }
                case 2: { // up: event still CONTAINS the lifting pointer
                    Ptr p = find(e.pid);
                    if (p == null) return;
                    index = mActive.indexOf(p);
                    action = (mActive.size() == 1)
                            ? MotionEvent.ACTION_UP
                            : (MotionEvent.ACTION_POINTER_UP
                               | (index << MotionEvent.ACTION_POINTER_INDEX_SHIFT));
                    dispatch(action, e);
                    mActive.remove(p);
                    break;
                }
            }
        } catch (Exception ex) {
            Log.w(TAG, "touch-replay: fire failed: " + ex);
        }
    }

    private void dispatch(int action, Ev cause) {
        final int n = mActive.size();
        final int w = Math.max(1, mTarget.getWidth());
        final int h = Math.max(1, mTarget.getHeight());
        MotionEvent.PointerProperties[] props = new MotionEvent.PointerProperties[n];
        MotionEvent.PointerCoords[] coords = new MotionEvent.PointerCoords[n];
        for (int i = 0; i < n; i++) {
            Ptr p = mActive.get(i);
            props[i] = new MotionEvent.PointerProperties();
            props[i].id = p.pid;
            props[i].toolType = MotionEvent.TOOL_TYPE_FINGER;
            coords[i] = new MotionEvent.PointerCoords();
            coords[i].x = p.xn * w;
            coords[i].y = p.yn * h;
            coords[i].pressure = 1f;
            coords[i].size = 0.1f;
        }
        long now = SystemClock.uptimeMillis();
        MotionEvent ev = MotionEvent.obtain(mDownTime, now, action, n, props,
                coords, 0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0);
        mTarget.dispatchTouchEvent(ev);
        ev.recycle();
        int masked = action & MotionEvent.ACTION_MASK;
        if (masked != MotionEvent.ACTION_MOVE) {
            Log.i(TAG, String.format(Locale.ROOT,
                    "touch-replay: t=%d %s pid=%d n=%d at (%.3f,%.3f)",
                    cause.t,
                    masked == MotionEvent.ACTION_DOWN ? "DOWN"
                            : masked == MotionEvent.ACTION_POINTER_DOWN ? "PDOWN"
                            : masked == MotionEvent.ACTION_UP ? "UP" : "PUP",
                    cause.pid, n, cause.xn, cause.yn));
        }
    }
}
