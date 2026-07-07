## WORK ECONOMY (manager/worker delegation)
You are the MANAGER: plan, decide, VERIFY subagent claims yourself. Delegate to autoport-researcher
(asset-pipeline/IO scans), autoport-implementer (edits to spec), autoport-tester (builds/device/
first-boot flows). Parallelize independent runs.

# Phase Grecharged-external-assets — split BINARY from ASSETS + external storage layout (all builds)

## Why (owner 2026-07-07)
Today jak1 (and jak2) builds bundle the FULL extracted-asset package inside the APK/binary — 1.2 GB
per build, re-shipped on every release, while the extracted original assets NEVER change. Useless
churn: releases are heavy, installs slow, updates re-push identical data.

## Mandate — binary and assets as separate artifacts, game reads from a user-chosen location
1. **Build outputs split** (x86 Windows/Linux AND Android arm64): the final BINARY (apk/exe/elf)
   on one side, the extracted-original-assets in an ARCHIVE on the other (zip/tar; one per game).
   The APK no longer embeds the iso assets (expect APK to drop from ~1.2 GB to tens of MB).
2. **First-boot prompt**: at boot, if no asset location is configured, the game PROMPTS the user for
   where the (decompressed) assets live. Persist the choice; re-prompt only if the path goes invalid.
   Android: a proper picker/flow (SAF or path input); x86: file-dialog or CLI/config prompt.
3. **Android storage permissions** — DO NOT FORGET: reading a user-chosen external location needs
   the right permission model (scoped storage: SAF tree grant, or MANAGE_EXTERNAL_STORAGE /
   READ_EXTERNAL_STORAGE per API level; manifest + runtime request + graceful deny handling).
4. **Directory layout at the chosen destination** (per game, and shared by the future Collection
   build — jak_1 / jak_2 / jak_3 subfolders):
     <chosen>/jak_1/assets/         <- extracted original assets (the archive decompressed here)
     <chosen>/jak_1/saves/          <- SAVES + CONFIGS written here (configs may sit beside saves)
     <chosen>/jak_1/custom_assets/  <- player-dropped texture packs (OpenGOAL texture replacements)
   Same shape for jak_2/ and jak_3/. The game for jak N looks up <chosen>/jak_N/assets; writes
   saves/settings under <chosen>/jak_N/saves.
5. **Custom assets toggle**: "LOAD CUSTOM ASSETS" ON/OFF in Graphics Options > Recharged Settings
   (persisted, default OFF). ON = OpenGOAL's texture-replacement path reads <chosen>/jak_N/
   custom_assets/ (map to the existing custom_assets/texture_replacements support).
6. **Migration/compat**: on first run after update, if the old embedded/app-private assets exist,
   offer to use/move them (don't brick existing installs — the owner's device has saves to keep).

## Verify (device eae4df44 + x86)
- Android: APK built WITHOUT embedded iso assets (report the size delta) + separate asset archive
  artifact produced; fresh install prompts for asset location; grant flow works; game boots to title
  from <chosen>/jak_1/assets; saves land in <chosen>/jak_1/saves (create a save, verify the file).
- Custom-assets toggle: with a test texture in custom_assets/, ON shows it in-game, OFF shows stock.
- x86: same split + prompt flow; boots from a chosen dir (link finish: logo + title).
- No regression when assets are in place (gameplay smoke). deploy_verify adapted to the split.

## Report (`.autoport/reports/Grecharged-external-assets/report.txt`)
`RESULT: EXTERNAL ASSETS <apk-size-before>-><after>` — the split mechanics, prompt UX (both
platforms), permission model used, layout created, saves relocation, custom-assets toggle proof
(ON/OFF screencaps), migration path, what's deferred. Honest partial OK (e.g. x86 first, Android
next attempt) — label it.

## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched (menu rows in pc/ only); OFF/default
paths keep current behavior working; .autoport/gold READ-ONLY; full consistent builds; don't lose the
device's existing saves.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.

## PROMOTED + jak2 requirement (owner 2026-07-07)
jak2's assets ALREADY exceed the AGP 2GB cap — the build currently DROPS non-English VAGWADs and
Gjak2-render added a temporary ENG-fallback. This phase REPLACES those workarounds: the external
asset archive carries the COMPLETE asset set (ALL language VAGWADs; FR audio restored on jak2), and
the APK/binary carries none. Apply to jak1 AND jak2 (jak3/Collection-ready). Remove the ENG-fallback
stopgap (or keep it only as a graceful-degradation path when a language file is genuinely absent).
