# Phase E2 — UX (touch overlay) launch report

_Generated: 2026-05-22T04:14:35+02:00_

## Determination

**pass**

## Overlay map

```json
{
  "hits": {
    "dpad_down": {
      "cx": 275,
      "cy": 784,
      "radius": 70,
      "sdl_button": 12
    },
    "dpad_left": {
      "cx": 163,
      "cy": 672,
      "radius": 70,
      "sdl_button": 13
    },
    "dpad_right": {
      "cx": 387,
      "cy": 672,
      "radius": 70,
      "sdl_button": 14
    },
    "dpad_up": {
      "cx": 275,
      "cy": 560,
      "radius": 70,
      "sdl_button": 11
    },
    "east": {
      "cx": 2134,
      "cy": 672,
      "radius": 70,
      "sdl_button": 1
    },
    "north": {
      "cx": 2022,
      "cy": 560,
      "radius": 70,
      "sdl_button": 3
    },
    "south": {
      "cx": 2022,
      "cy": 784,
      "radius": 70,
      "sdl_button": 0
    },
    "start": {
      "cx": 1149,
      "cy": 859,
      "radius": 49,
      "sdl_button": 6
    },
    "west": {
      "cx": 1910,
      "cy": 672,
      "radius": 70,
      "sdl_button": 2
    }
  },
  "note": "Hit-zone -> SDL_GAMEPAD_BUTTON_* mapping. Tap (cx,cy) to fire NativeGk.onPadButton(sdl_button, true|false).",
  "phase": "E2",
  "screen": {
    "h": 934,
    "w": 2298
  },
  "source": "TouchOverlayView.onSizeChanged"
}```

## Marker observations (from logcat)

```
05-22 04:14:25.884 27066 27066 I opengoal-gk: touch overlay setting: enabled=true default=true gamepads_at_start=0
05-22 04:14:25.885 27066 27066 I opengoal-gk: touch overlay enabled — overlay visible (no gamepad at startup)
05-22 04:14:25.885 27066 27066 I opengoal-gk: MainActivity onCreate done; mLayout=true mLayout.children=2
05-22 04:14:25.919 27066 27066 I opengoal-gk: overlay-map: screen=2298x934 south=2022,784,70,0 east=2134,672,70,1 west=1910,672,70,2 north=2022,560,70,3 dpad_up=275,560,70,11 dpad_down=275,784,70,12 dpad_left=163,672,70,13 dpad_right=387,672,70,14 start=1149,859,49,6
05-22 04:14:26.514 27066 27175 D opengoal-gk: link finish: logo
05-22 04:14:26.515 27066 27175 D opengoal-gk: link finish: logo-black
05-22 04:14:26.515 27066 27175 D opengoal-gk: link finish: logo-cam
05-22 04:14:26.515 27066 27175 D opengoal-gk: link finish: logo-volumes
05-22 04:14:27.058 27066 27066 I opengoal-gk: onPadButton: overlay tap -> sdl_button=2 pressed=1 name=west from=overlay
05-22 04:14:27.059 27066 27066 I opengoal-gk: onPadButton: sdl_button=2 pressed=1 (JNI route from Java SDLActivity)
05-22 04:14:27.059 27066 27066 I opengoal-gk: kernel: pad: west pressed
05-22 04:14:27.099 27066 27066 I opengoal-gk: onPadButton: overlay tap -> sdl_button=2 pressed=0 name=west from=overlay
05-22 04:14:27.099 27066 27066 I opengoal-gk: onPadButton: sdl_button=2 pressed=0 (JNI route from Java SDLActivity)
05-22 04:14:27.099 27066 27066 I opengoal-gk: kernel: pad: west released
05-22 04:14:27.623 27066 27066 I opengoal-gk: onPadButton: overlay tap -> sdl_button=3 pressed=1 name=north from=overlay
05-22 04:14:27.623 27066 27066 I opengoal-gk: onPadButton: sdl_button=3 pressed=1 (JNI route from Java SDLActivity)
05-22 04:14:27.623 27066 27066 I opengoal-gk: kernel: pad: north pressed
05-22 04:14:27.627 27066 27066 I opengoal-gk: onPadButton: overlay tap -> sdl_button=3 pressed=0 name=north from=overlay
05-22 04:14:27.627 27066 27066 I opengoal-gk: onPadButton: sdl_button=3 pressed=0 (JNI route from Java SDLActivity)
05-22 04:14:27.627 27066 27066 I opengoal-gk: kernel: pad: north released
```

## Next blocker (if any)

None — E2 markers all observed. Validator should pass.
