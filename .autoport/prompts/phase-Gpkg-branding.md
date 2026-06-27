# Phase Gpkg-branding — app name "Jak & Daxter" + proper launcher icon

## Goal (owner directive 2026-06-27, do LAST — after all gameplay bugs)
The shipped APK must present as a real game: **app label "Jak & Daxter"** (not the current
`org.opengoal.gk`/dev name) and a **proper Jak & Daxter launcher icon** at all densities.

## Scope
- **App name:** set the launcher label to `Jak & Daxter` — `android/app/src/main/AndroidManifest.xml`
  `android:label` (+ `strings.xml` `app_name`), and any `build.gradle` flavor label for the jak1 variant.
  Keep the package id `org.opengoal.gk.jak1` (changing it breaks installs/saves) — only the visible
  LABEL changes.
- **Launcher icon:** a proper adaptive icon (`mipmap-anydpi-v26` foreground+background + legacy
  `mipmap-*dpi` PNGs at mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi, and the round variant). Wire it as
  `android:icon` / `android:roundIcon`.
- Optional: a matching splash/launch screen.

## OWNER INPUT NEEDED (when this phase runs)
The ICON ARTWORK is a content asset I must not invent/scrape (copyright). Before/at this phase, the
owner provides a source icon image (≥512×512 PNG, ideally the foreground art + a background color) at a
known path (e.g. `.autoport/assets/icon-src.png`); this phase resizes/wires it into all densities +
the adaptive XML. If no art is supplied, generate a clean PLACEHOLDER (e.g. a stylized "J&D" on a
themed background) and flag it for owner replacement — do NOT ship a scraped copyrighted image.

## Validator PASS requires
1. `android:label` resolves to `Jak & Daxter` (manifest/strings/gradle), package id unchanged.
2. Launcher icon resources present at ALL standard densities + adaptive (anydpi-v26) + round; wired via
   `android:icon`/`android:roundIcon`.
3. The jak1 APK BUILDS, installs on eae4df44, and the launcher shows the name + icon (verified via
   `pm`/`dumpsys package` label + the mipmap resources in the built APK). `deploy_verify.sh eae4df44`
   still PASS (engine unaffected). Report `.autoport/reports/Gpkg-branding/report.txt` with
   `RESULT: APP NAME + ICON SHIPPED`.

## Locks: ANDROID_SERIAL=eae4df44 only; .autoport/gold READ-ONLY; goal_src 1-to-1 (this is APK packaging, no engine change).
## Max: max_turns 1200, max_retries 3.
