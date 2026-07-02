# `collection` flavor — the multi-game "Recharged Jak-pot" container

Phase Glauncher-collection (autoport 2026-07-02).

This flavor builds the COLLECTION APK: `org.opengoal.gk.collection`, launcher
label **"Jak and Daxter: The Recharged Jak-pot"**, its own placeholder launcher
icon (`res/mipmap-*`). It boots to a selection menu (text rows, usable by touch
and by gamepad/D-pad) listing the bundled games; picking one unpacks that game's
assets and launches it.

The set of games is **asset-driven**: whichever `<game>_assets.zip` archives are
staged under `assets-bundled/bundle/` at build time. Today only jak1 assets
exist, so this flavor ships empty; **STEP-1** for a real collection is to stage
two or more per-game bundles here (see `assets-bundled/bundle/.gitkeep`).

Detection can be dry-run without building:
`(cd android && ./gradlew printGameDetection -PdetectDir=/path/to/two-zip-dir)`.
