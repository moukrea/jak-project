## READ FIRST: .autoport/plans/build-system-pillar.md. P3 of the owner's build-system pillar.
# Phase Grecharged-buildsys-firstboot — native pickers, jakN tree, settings.ini, custom_assets, NO migration
Owner (verbatim): "Au premier démarrage, le jeu nous prompt (peu importe l'OS) pour l'emplacement des
fichiers du jeu en utilisant les file browsers natifs respectifs. Le jeu attend une arborescence:
<root>/jak1/{assets/ (de l'archive), custom_assets/ (textures user par nom de fichier), saves/,
settings.ini (toutes les configs des menus)} ; jak2/, jak3/ same deal. Ballec de la rétro-compatibilité
et des migrations. Pour mon Honor tu me demanderas via ADB de récupérer les sauvegardes et de virer
l'ancienne app pour réinstaller le build propre."
Deliverables: (1) first-boot native picker per OS (Android SAF adapt existing; Linux xdg-portal/zenity
with --game-root=<path> CLI fallback for headless/harness — risk R3); (2) the jakN tree (rename jak_1->
jak1, settings move); (3) settings.ini: INI serialization bridge — GOAL pc-settings stays the truth,
INI is write-through persistence parsed at boot (risk R4); (4) custom_assets filename-override loader
(textures first); (5) UPDATE THE ENTIRE DEVICE HARNESS to the new layout (warp/capture/settings scripts
— risk R5, budget it); (6) Redmi cutover: ADB-pull saves -> uninstall+wipe -> clean install -> saves
into the new tree -> boot proof. Honor cutover: written procedure for the owner, executed when HE asks.
NO migration code, NO legacy paths kept. Proofs: fresh-install first-boot video (picker->tree->game),
settings round-trip (menu change -> ini -> reboot -> applied), custom texture override demo, harness
smoke green. Max: max_turns 3000, max_retries 6.
