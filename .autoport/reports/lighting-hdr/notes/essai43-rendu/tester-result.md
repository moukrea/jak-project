# Résultat tester — DIRECTIVES v3909a9767c

Build gk incrémental unique : 12,27 s, rc 0 ; repack isolé : 28,68 s, rc 0 ; installation : 22,74 s.
APK SHA256 `5d3d6a416c12f690c51537f7102caf433a1131d1617c252f754d28bf74bc37c8`.
Lib SHA256 `0f1a5b25e21ebb4ac4e790abe7f10d6624989ba7c6fb21b07ac26b23e801ec7c`.
Les 28 CGOs et le bundle livré sont identiques au build essai43 ; aucun build GOAL/iso/configure.

Portail : 401 s, 4 captures, 1 paire à h12, crash 0, 4620 frames, erreurs 0.
Attentes après purge ON : 55,171/110,809 s ; OFF : 42,753/84,917 s, toutes supérieures à 10 s.
21 entrées du manifeste vérifiées SHA256 ; 48 événements natifs analysés.
Défaut qualité conservé : excess.clipped 207, quality_bad 1 ; aucune validation owner.

Extérieur : 164 s, 12 captures, 3 paires à h0/12/18, crash 0, 1620 frames, erreurs 0, quality_bad 0.
37 entrées du manifeste vérifiées SHA256 ; 120 événements natifs analysés.
Les attentes courtes extérieures ne permettent aucun jugement de portail.

Aucune erreur de compilation/lien GLSL ou programme absent trouvée par les motifs archivés.
Les deux runs recensent 53 programmes, RGBA8 et RGBA16F, fallback 0 et tous hdr_cfg_bad à 0.
PNG refset limités à 320×180 ; événements natifs conservés séparément. Aucune région manquante assimilée à une réussite.
Les deux preuves gardent hdr_owner_regressions_passed=0 et hdr_tonemap_defects=4.

Settings restaurés exactement : SHA256 78108670e26658496f33a2a0dc50c45fe16a0f2e59c774ea70499c7fefb52fd6.
Propriétés debug.opengoal non vides : aucune ; préférence realtime-lighting?=#f conservée.
PID normal final 8310 observé stable 12 s. Aucun verrou .deploy-in-progress restant.
APK/lib/settings/28 CGOs de l’appareil revérifiés après les deux runs et identiques.
Audit détaillé : final-audit.json ; preuves originales copiées intactes dans chaque dossier.
