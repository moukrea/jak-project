KNOWN-GOOD arm64 CGO/DGO set for org.opengoal.gk.jak1 (Redmi eae4df44).
Provenance: /tmp/f1c-arm64-iso (F1c phase build, 2026-06-11 20:35), internally consistent.
This EXACT 28-file set boots clean to the Jak&Daxter title screen on device
(verified 2026-06-18). It is the device runtime restore artifact after the
Gcine-camfov boot-CGO-rebuild regression bricked the phone.
RESTORE: push all 28 to files/iso_data/jak1/ via run-as cp as a CONSISTENT SET.
DO NOT mix with TIT.DGO/boot CGOs from other builds (mixing => frame-180 sparticle SIGILL).
