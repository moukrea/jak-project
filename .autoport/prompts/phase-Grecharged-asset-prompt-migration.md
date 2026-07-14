## ONE TASK at a time — runs right after overhang7. Verify via the OWNER'S REAL flow (fresh install-over).

# Phase Grecharged-asset-prompt-migration — the first-boot prompt the owner asked for never fires on upgrades

## Owner report (2026-07-14, verbatim — HONOR, latest slim APK from GitHub + assets extracted to a folder)
"Au démarrage, ça m'a pas du tout demandé où sont les assets... Ça faisait partie de la demande...
J'imagine que ça a réutilisé les assets qui étaient packagés avant... Ça devrait faire une migration
après prompt (migration des sauvegardes + suppression des assets qui étaient avant packagés avec l'APK)"

## The gap
Grecharged-external-assets DELIBERATELY kept existing installs in internal mode with ZERO UI ("internal
assets detected -> keeps today's behavior silently"). The owner explicitly wanted: on upgrade of an
old self-contained install, PROMPT for the asset location, and offer a MIGRATION = saves copied to the
chosen external root + the old internal packaged assets DELETED (frees ~1.6 GB of app-private storage).
CONSEQUENCE TODAY: his HONOR silently runs STALE internal assets — none of the data-side features
(HD overlay, new grass bakes) ever reach it. This gap invalidates his HONOR testing.

## Mandate
1. LoaderActivity upgrade path: when a slim APK boots over an install that has internal assets AND no
   persisted external choice -> SHOW the asset-location prompt (same chooser as fresh installs):
   options = USE INTERNAL (exactly today's behavior) / CHOOSE EXTERNAL FOLDER. Never silent again.
2. If external chosen: accept an already-extracted folder (validate layout/version), MIGRATE saves
   (copy, verify, never clobber existing external saves), then DELETE the internal packaged assets
   (iso_data/fr3 data only — NEVER saves, NEVER user config) only AFTER the external root is verified
   bootable. Show freed space. A failed/cancelled migration leaves everything intact.
3. Remember the choice (existing persistence); external-root-invalid fallback flow unchanged.
4. Verify on the Redmi via the owner flow: seed a fake "old install" state (internal assets + no choice),
   install-over the slim APK, prove the prompt fires, run BOTH branches (internal keeps working;
   external migrates saves + deletes internal data + boots from external, sha-checked), saves intact
   end-to-end both ways. Screenshots of the prompt + logcat evidence.
Report RESULT + both-branch proof. Max: max_turns 2400, max_retries 5.
