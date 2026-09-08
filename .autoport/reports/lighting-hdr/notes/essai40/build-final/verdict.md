DIRECTIVES v708c60642a
Candidat final avec exclusion HUD installé, sans relance jeu.
Tests GPU ciblés huit cas PASS ; détail test-verdict.md, alpha_gpu.log failures=0 ; audit signature et 3 appels explicites dans hud-call-audit.json.
Builds rc/durées : [('android.log', 0, 17.71), ('repack.log', 0, 69.92)]
Lib SHA256 32d5e7e2e9f427d8ae87a41a0b5f400e3eb07b77c88d3f06ceabd02bc79229ea identique build/APK/Redmi.
APK SHA256 883014b77b6fe30e09c8652d6a99f15dab5d12b4a84ebc7e44a144f5a77166f0 identique isolé/Redmi.
Packs, CGO appareil, settings et APK public inchangés ; sources suivies inchangées durant build.
Verrou run.py PID 4181548 nettoyé à la sortie. Identité device-identity.json ; commandes et rc commands.json.
Non prouvé : scène jeu et image OFF complète. Aucun proof_run, validateur ou relance exécuté.
