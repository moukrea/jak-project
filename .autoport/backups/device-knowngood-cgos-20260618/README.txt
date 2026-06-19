KNOWN-GOOD arm64 CGO/DGO set for org.opengoal.gk.jak1 (Redmi eae4df44).
Provenance: /tmp/f1c-arm64-iso (F1c phase build, 2026-06-11 20:35), internally consistent.
This EXACT 28-file set boots clean to the Jak&Daxter title screen on device
(verified 2026-06-18). It is the device runtime restore artifact after the
Gcine-camfov boot-CGO-rebuild regression bricked the phone.
RESTORE: push all 28 to files/iso_data/jak1/ via run-as cp as a CONSISTENT SET.
DO NOT mix with TIT.DGO/boot CGOs from other builds (mixing => frame-180 sparticle SIGILL).

2026-06-19 (Ghalo): TIT.DGO replaced with the Ghalo-fixed arm64 build
(sha 13641655da23c193..., from out/jak1-arm64-full/iso/TIT.DGO). It carries the
Gndlogo ND-logo halo suppression (done?-gated village + sun-fade) AND re-gates the
Gsce SCE static-screen spawn to SCEI so it does NOT re-trigger the frame-180
enter-state SIGILL on these f1c boot CGOs. PROVEN on device eae4df44: boots clean to
a textured title flythrough (tris=558463 @ frame 1200), 0 crash signatures, intro-logo
halo_excess_frac 0.289 -> 0.0008. The pristine f1c (June-11) TIT.DGO (sha bd63f35c...)
is preserved at .autoport/backups/f1c-tit-orig/TIT.DGO. The other 27 files are still
the f1c June-11 build. This f1c-boot-CGOs + Ghalo-TIT.DGO set is the new device
known-good; it is a PROVEN-safe overlay, not an unverified mix.
