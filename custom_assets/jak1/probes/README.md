# jak1 LOCAL light-probe grids (Grecharged-lightprobes)

First-party baked data made by US (the port). Per the owner directive (2026-07-20):
these `.probes` grids are **committed to the repo** AND **embedded in the APK** so a
plain `adb install` ships them — **no manual side-load**.

## What ships here
- `village1.probes` — the precomputed LOCAL environment probe grid for `village1`
  (L2 irradiance SH per probe × 8 TOD keys + prefiltered reflection cubemaps).
  Baked PROGRAMMATICALLY from the STOCK `village1.fr3` baked lighting (suns included).

## How it reaches the device (APK-install-only, no side-load)
1. `android/build_custom_pack.sh <game>` stages every `custom_assets/<game>/probes/*.probes`
   into the port-custom pack as `fr3/<name>.probes`.
2. That pack is bundled into the APK (`assets/bundle/jak1_custom.zip`) by gradle.
3. On (re)install, `LoaderActivity.unpackCustomPackIfNeeded()` extracts it to
   `<filesDir>/custom/jak1/fr3/village1.probes` (content-versioned stamp → re-extracts
   whenever the file changes).
4. Runtime `LightProbeGrid` reads `get_custom_fr3_dir()/<level>.probes` (the custom/
   package dir WINS over external `assets/fr3`) → zero manual placement.

## How to regenerate / roll out to more levels (reproducible bake)
The bake tool stays the source of truth:

```
# 1. bake from the STOCK fr3 (offline, full-res HDRI capture, render-scaling OFF):
tools/probe_bake/... <level>        # writes out/jak1/fr3/<level>.probes  (build OUTPUT)

# 2. accept it as the shipping asset (commit it here):
cp out/jak1/fr3/<level>.probes custom_assets/jak1/probes/<level>.probes
git add custom_assets/jak1/probes/<level>.probes

# 3. repack + reassemble the APK; a fresh install ships the new grid:
android/build_custom_pack.sh jak1
( cd android && ./gradlew assembleJak1Debug )
```

`out/jak1/fr3/<level>.probes` is a build OUTPUT (git-ignored). The committed copy in
THIS directory is the first-party shipping asset the APK actually bundles.
