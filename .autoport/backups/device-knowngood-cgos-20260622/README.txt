KNOWN-GOOD arm64 CGO/DGO set for org.opengoal.gk.jak1 (Redmi eae4df44).
Phase: Gconsolidate-deploy (2026-06-22).

Provenance: FRESH, internally-consistent full build from HEAD (f59138559) via
.autoport/build_arm64_full_consistent.sh ( (make-group "iso" :force #t), obj cache
wiped first ). Staged from out/jak1-arm64-full/iso. goalc rebuilt both backends from
HEAD first (arm64 + x86).

This 28-file set is BYTE-IDENTICAL to the prior Gconsolidate proven-good build
(KERNEL.CGO 6973a44f, GAME.CGO daa22d53, ENGINE.CGO 1703f786, TIT.DGO d67028b8),
because goal_src and goalc are unchanged since that build. That prior build was
deployed and proven on device eae4df44 to boot title -> NEW GAME -> intro cinematic
-> gameplay (frame 11160, 0 crash sigs), with the menu/sun/3D-particles/stars
rendering. See .autoport/reports/Gconsolidate-deploy/consolidate.txt for THIS phase's
fresh-build device boot->gameplay proof.

WHY THIS REPLACES THE June-11 (20260618) BACKUP AS THE RESTORE SOURCE:
The June-11 set is the f1c data set (GAME.CGO 2b49f4ae, KERNEL.CGO 63d7707c,
ENGINE.CGO 1cb1343f, TIT.DGO 13641655-overlay). It PREDATES the data-resident fixes
that live inside the CGO/DGO data (not libgk):
  - GAME.CGO / ENGINE.CGO : menu widescreen-widen (progress/video-h, *video-parms*),
                            Gcine-camfov, Gcine-cut merc-blend-shape, etc.
  - KERNEL.CGO            : gstate.gc frame-180 enter-state fix (Gspark).
  - TIT.DGO               : Gndlogo + Ghalo + Gtitle-pixelmatch (title-obs.gc).
Restoring the June-11 set REVERTED those data fixes on every restore (the
stale-backup deployment regression: owner saw the bunched menu again, etc.).
This 20260622 set carries all data fixes AND boots clean (the f1c-only boot
constraint was lifted by the Gspark frame-180 fix). It is the new restore source.

RESTORE: push all 28 to files/iso_data/jak1/ via run-as cp as a CONSISTENT SET
(do NOT mix CGO/DGO from different builds). restore_knowngood_device.sh SRC points here.

FALLBACK: the June-11 set is KEPT at .autoport/backups/device-knowngood-cgos-20260618
(do NOT delete) as a last-resort bootable fallback.
