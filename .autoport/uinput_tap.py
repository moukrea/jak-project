#!/usr/bin/env python3
# Minimal raw-uinput key tapper (no evdev dependency). Creates a virtual
# keyboard, taps the given Linux key code(s), then destroys the device.
# Events go to the compositor's focused surface, so the gk window must have
# focus. Usage: uinput_tap.py <keycode> [keycode ...]   (default 28 = ENTER)
import ctypes, fcntl, os, struct, sys, time

BASE = ord('U')
def _IOC(d, t, nr, size): return (d << 30) | (t << 8) | nr | (size << 16)
def _IOW(t, nr, size): return _IOC(1, t, nr, size)
def _IO(t, nr): return _IOC(0, t, nr, 0)
UI_SET_EVBIT  = _IOW(BASE, 100, 4)
UI_SET_KEYBIT = _IOW(BASE, 101, 4)
UI_DEV_CREATE = _IO(BASE, 1)
UI_DEV_DESTROY = _IO(BASE, 2)
EV_SYN, EV_KEY, SYN_REPORT = 0, 1, 0

# Keys we ever inject (ENTER, SPACE, E, ESC, arrows) so libinput sees a keyboard.
KEYS = [28, 57, 18, 1, 103, 108, 105, 106]

def emit(fd, etype, code, val):
    os.write(fd, struct.pack('@llHHi', 0, 0, etype, code, val))

def tap(fd, code):
    emit(fd, EV_KEY, code, 1); emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.06)
    emit(fd, EV_KEY, code, 0); emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.06)

def main():
    codes = [int(a) for a in sys.argv[1:]] or [28]
    fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
    for k in KEYS:
        fcntl.ioctl(fd, UI_SET_KEYBIT, k)
    name = b'autoport-virtual-kbd'
    # struct uinput_user_dev: name[80], input_id(4*u16), ff_effects_max(u32),
    # absmax/absmin/absfuzz/absflat (4 * 64 * s32)
    dev = struct.pack('80s4HI256i', name, 0x03, 0x1234, 0x5678, 1, 0, *([0] * 256))
    os.write(fd, dev)
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.6)  # let the compositor register the new device
    for c in codes:
        tap(fd, c)
        time.sleep(0.15)
    time.sleep(0.3)
    fcntl.ioctl(fd, UI_DEV_DESTROY)
    os.close(fd)
    print("uinput_tap: sent", codes)

if __name__ == '__main__':
    main()
