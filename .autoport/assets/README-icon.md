# Launcher icon — placeholder, for the owner to replace

The shipped Jak 1 Android APK (`org.opengoal.gk.jak1`, label **"Jak & Daxter"**)
currently uses a **clean, non-copyrighted PLACEHOLDER** launcher icon: a
typographic **"J&D"** monogram in Precursor-gold on a deep-blue → eco-teal
gradient. It deliberately ships **no scraped/copyrighted character art**.

Master reference: `icon-src-placeholder.png` (512×512).

## To install final artwork

1. Provide a square source image, ≥512×512 PNG. Two parts work best:
   - a **foreground** (transparent PNG: the logo/character, no background), and
   - a **background** (solid color or simple gradient).
   For an adaptive icon, keep the important content inside the central ~66 % of
   the canvas (the launcher mask crops the edges).

2. Either:
   - **Re-run the generator** after pointing it at your art
     (`.autoport/assets/gen_icon.py`), or
   - **Hand-replace** these files (keep the names + densities):
     - `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`
       (48/72/96/144/192 px) and `ic_launcher_round.png` (same sizes, circular)
     - `android/app/src/main/res/mipmap-{...}/ic_launcher_foreground.png`
       (adaptive foreground: 108/162/216/324/432 px, transparent, safe-zone)
     - `android/app/src/main/res/drawable/ic_launcher_background.xml`
       (adaptive background — a color or gradient vector)

3. Rebuild + reinstall: `cd android && ./gradlew assembleJak1Debug` then install.

The app **label** ("Jak & Daxter") and the **package id**
(`org.opengoal.gk.jak1`) are independent of the icon — changing the icon does
not affect either. Do not change the package id (it would break installs/saves).
