# LoaderActivity completion spec — external asset flow (phase Grecharged-external-assets)

Scope: ONLY `android/app/src/main/java/org/opengoal/gk/LoaderActivity.java` (small helper
classes in the same package allowed). No commits. Match existing code style.

Contracts already in the tree (read them first):
- `MainActivity.java`: reads SharedPreferences file `"recharged_assets"`, keys `asset_root`
  (the chosen base folder, String) and `asset_mode` (`"external"` or `"internal"`). External
  mode: gameRoot = `<asset_root>/jak_N` (underscore form, see its `gameFolder()`), requires
  `<gameRoot>/assets/iso` non-empty, else bounces back to LoaderActivity with boolean intent
  extra `org.opengoal.gk.ASSET_ROOT_INVALID`.
- APK assets (slim default): `bundle/<game>_cgo.zip` (FLAT entries: `*.CGO`, `*.DGO`,
  `*COMMON.TXT`) + `bundle/<game>_cgo.manifest.properties` (`version=`, `file_count=`,
  `raw_bytes=`). Old self-contained builds instead have `bundle/<game>_assets.zip` (+ its
  manifest) with entries `iso_data/<game>/...` and `fr3/...`.
- Asset archive the user provides (zip they pick): entries `iso/...`, `fr3/...`,
  `recharged_assets/...` — extract as-is under `<gameRoot>/assets/`.
- AndroidManifest already declares MANAGE_EXTERNAL_STORAGE + legacy READ/WRITE (maxSdk).
- Device target: Android 12 (API 31); also support API 29-30 code paths.

## A. CGO pack unpack (all modes, first step per game)
`unpackCgoPackIfNeeded(game)`: stream `assets/bundle/<game>_cgo.zip` →
`<filesDir>/cgo/<game>/<entryName>` (entries are flat). Stamp file
`<filesDir>/.cgo_pack_stamp_<game>` with the manifest `version=`, written LAST; skip when
current. Per-entry CRC32 + final file_count check, mirroring `unpackBundleIfNeeded`.
Prefer refactoring a shared streaming-unpack helper (source InputStream, entry→File mapper,
progress callback) used by both; a parallel method is acceptable if the refactor is risky.
If the cgo zip asset is absent (old bundled build), return silently.

## B. Boot decision (rework `beginUnpackAndLaunch(game)`)
1. `unpackCgoPackIfNeeded(game)`.
2. mode == external → valid iff `<asset_root>/jak_N/assets/iso` is a readable non-empty dir
   AND storage access held (section D). Valid → launch MainActivity as today. Invalid → show
   the chooser screen with an explanatory banner. Also show that banner when the launch
   intent has extra `org.opengoal.gk.ASSET_ROOT_INVALID`.
3. mode == internal → today's path (`unpackBundleIfNeeded` then launch).
4. mode unset:
   - if `assetExists("bundle/<game>_assets.zip")` → persist mode=internal, take path 3
     (old self-contained builds behave exactly as before, no new UI);
   - else → chooser screen (fresh slim install, or update with internal files present).
Whenever asset_root/asset_mode are persisted, also write `<filesDir>/asset_root.txt`:
either the absolute per-game root (`<asset_root>/jak_N`) or the literal line `internal`
(adb tooling reads this file).

## C. Chooser screen
Reuse the existing dark menu UI pattern (title + vertical buttons, D-pad/gamepad nav via the
existing onKeyDown/onGenericMotionEvent machinery, touch clicks). Short explanation text:
assets live in a folder the user picks; one folder serves all games (jak_1, jak_2, jak_3
subfolders). Options:
1. "CHOOSE ASSETS FOLDER" → ensure storage access (D) → `Intent.ACTION_OPEN_DOCUMENT_TREE`
   via startActivityForResult. Convert the returned tree URI to a plain path with
   `DocumentsContract.getTreeDocumentId(uri)`: `primary:REST` → `/storage/emulated/0/REST`;
   `primary:` → `/storage/emulated/0`; `XXXX-XXXX:REST` → `/storage/XXXX-XXXX/REST`; anything
   else → open the manual dialog (option 2) prefilled. Validate File isDirectory+canRead,
   persist asset_root + mode=external, continue at E.
2. "TYPE PATH MANUALLY" → AlertDialog with EditText prefilled `/storage/emulated/0/OpenGOAL`;
   ensure storage access (D); mkdirs() if missing; validate; persist; continue at E.
3. "USE INTERNAL ASSETS" — shown only when `<filesDir>/iso_data/<game>` is a non-empty dir
   (existing installs) → persist mode=internal → boot path B.3.

## D. Storage access helpers
`hasStorageAccess()`: API>=30 → `Environment.isExternalStorageManager()`; API<=29 →
`checkSelfPermission(READ_EXTERNAL_STORAGE) == GRANTED`.
`requestStorageAccess()`: API>=30 → startActivityForResult of
`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` with `package:` URI (fallback to
`Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION` on ActivityNotFoundException), re-check
on result/onResume; API<=29 → `requestPermissions({READ,WRITE}, code)`. If the user declines:
show "STORAGE ACCESS REQUIRED — RETRY" on the chooser screen and wait for another explicit
tap; never auto-loop the Settings screen; never crash.

## E. After an external root is chosen
mkdirs `<root>/jak_N/assets`, `<root>/jak_N/saves`, `<root>/jak_N/custom_assets`. If
`<root>/jak_N/assets/iso` is missing/empty, second menu:
- "COPY INSTALLED ASSETS TO FOLDER" (only when `<filesDir>/iso_data/<game>` exists):
  background thread + the existing progress UI. Copy `files/iso_data/<game>/*` EXCEPT
  `*.CGO`/`*.DGO` → `assets/iso/`; `files/out/<game>/fr3/*` → `assets/fr3/`;
  `files/recharged_assets/*` → `assets/recharged_assets/` (if present). Then saves:
  `files/.config/OpenGOAL/<game>/saves/**` → `<root>/jak_N/saves/**` (preserve subdirs) and
  `files/.config/OpenGOAL/<game>/settings/**` → `<root>/jak_N/saves/settings/**`. COPY only,
  never delete originals. Buffered streams; progress by file count. Then validate → launch.
- "EXTRACT ASSET ARCHIVE (ZIP)" → `ACTION_OPEN_DOCUMENT` (mime application/zip +
  EXTRA_MIME_TYPES including application/octet-stream) → stream
  `getContentResolver().openInputStream(uri)` through the unpack helper into
  `<root>/jak_N/assets/` (entries `iso/`, `fr3/`, `recharged_assets/` as-is; canonical-path
  containment guard; running count/MB progress; no manifest count available). Then the saves
  copy from the previous bullet runs too, when internal saves exist and `<root>/jak_N/saves`
  is empty. Validate → launch.
- "CONTINUE ANYWAY" → validate (assets/iso non-empty) → launch, else stay with a
  "assets not found at <path>" banner.

## Verify
`cd android && ./gradlew :app:compileJak1DebugJavaWithJavac` must pass. Report a diff stat,
a walkthrough of: fresh install, existing-internal update, invalid-root re-prompt, declined
access, old bundled build — and any deviation from this spec.
