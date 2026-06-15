#!/usr/bin/env python3
# Activate the gk (OpenGOAL) window via EWMH _NET_ACTIVE_WINDOW (mutter honors
# this, like wmctrl), then tap Linux key code(s) via raw uinput so they reach
# the now-focused window. Usage: xfocus_tap.py <keycode> [keycode ...]
import ctypes, fcntl, os, struct, sys, time

# ---- X activation (python-xlib) ----
def activate_gk():
    os.environ.setdefault('DISPLAY', ':0')
    os.environ.setdefault('XAUTHORITY', '/run/user/1000/.mutter-Xwaylandauth.RKSTQ3')
    from Xlib import X, display, Xatom
    d = display.Display()
    root = d.screen().root
    NET_ACTIVE = d.intern_atom('_NET_ACTIVE_WINDOW')
    NET_WM_NAME = d.intern_atom('_NET_WM_NAME')

    def name_of(w):
        try:
            for atom in (NET_WM_NAME, Xatom.WM_NAME):
                r = w.get_full_property(atom, 0)
                if r and r.value:
                    v = r.value
                    return v.decode('utf-8', 'replace') if isinstance(v, bytes) else str(v)
        except Exception:
            pass
        return ''

    found = []
    def walk(w):
        try:
            nm = name_of(w)
            if nm and ('OpenGOAL' in nm or 'gk' == nm or 'Jak' in nm):
                found.append((w, nm))
            for c in w.query_tree().children:
                walk(c)
        except Exception:
            pass
    walk(root)
    if not found:
        print('xfocus: gk window NOT found'); return False
    win, nm = found[0]
    print(f'xfocus: activating "{nm}" id=0x{win.id:x}')
    ev = X.ClientMessage
    data = (32, [2, X.CurrentTime, 0, 0, 0])  # source=2 (pager), honored by mutter
    cm = win.send_event  # not used; use root event
    from Xlib.protocol.event import ClientMessage
    msg = ClientMessage(window=win, client_type=NET_ACTIVE, data=data)
    root.send_event(msg, event_mask=(X.SubstructureRedirectMask | X.SubstructureNotifyMask))
    try:
        win.configure(stack_mode=X.Above)
    except Exception:
        pass
    win.set_input_focus(X.RevertToParent, X.CurrentTime)
    d.sync()
    return True

# ---- uinput tap ----
BASE = ord('U')
def _IOC(dr, t, nr, size): return (dr << 30) | (t << 8) | nr | (size << 16)
def _IOW(t, nr, size): return _IOC(1, t, nr, size)
def _IO(t, nr): return _IOC(0, t, nr, 0)
UI_SET_EVBIT, UI_SET_KEYBIT = _IOW(BASE, 100, 4), _IOW(BASE, 101, 4)
UI_DEV_CREATE, UI_DEV_DESTROY = _IO(BASE, 1), _IO(BASE, 2)
EV_SYN, EV_KEY = 0, 1
KEYS = [28, 57, 18, 1, 103, 108, 105, 106]

def emit(fd, et, code, val): os.write(fd, struct.pack('@llHHi', 0, 0, et, code, val))
def tap(fd, code):
    emit(fd, EV_KEY, code, 1); emit(fd, EV_SYN, 0, 0); time.sleep(0.07)
    emit(fd, EV_KEY, code, 0); emit(fd, EV_SYN, 0, 0); time.sleep(0.07)

def main():
    codes = [int(a) for a in sys.argv[1:]] or [28]
    activate_gk()
    time.sleep(0.4)
    fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY); fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
    for k in KEYS: fcntl.ioctl(fd, UI_SET_KEYBIT, k)
    os.write(fd, struct.pack('80s4HI256i', b'autoport-kbd', 0x03, 0x1234, 0x5678, 1, 0, *([0]*256)))
    fcntl.ioctl(fd, UI_DEV_CREATE); time.sleep(0.6)
    for c in codes:
        tap(fd, c); time.sleep(0.12)
    time.sleep(0.3); fcntl.ioctl(fd, UI_DEV_DESTROY); os.close(fd)
    print('xfocus_tap: sent', codes)

if __name__ == '__main__':
    main()
