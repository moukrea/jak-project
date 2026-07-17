**Refonte build & packaging (pilier build-system, P1→P4)** : nouveau format de release — un paquet applicatif par plateforme + l'archive d'assets, générés par la nouvelle CLI `./build.sh <cible> --package`.

- **`app-jak1-android-arm64.apk`** — l'app Android (moteur + tout le custom du port : CGO/DGO arm64, textes, packs custom). Premier lancement : choix du dossier, puis **extraction de `jak1_assets.zip` directement dans l'app** (bouton EXTRACT ASSET ARCHIVE). Nouvel arbre `<dossier>/jak1/{assets, custom_assets, saves, settings.ini}` — réglages dans un `settings.ini` lisible, textures custom par simple dépôt de `.png` dans `custom_assets/`.
- **`app-jak1-linux-x86_64.tar.gz`** — le jeu PC Linux : `./run.sh` ouvre un sélecteur de dossier au premier lancement (ou `./run.sh --game-root <dossier>`).
- **`app-jak1-windows-x86_64.zip`** — le jeu PC Windows : double-clic sur `run.bat`, sélecteur de dossier natif au premier lancement. Binaires compilés en CI GitHub (non testés sur machine physique — retours bienvenus).
- **`jak1_assets.zip`** — les données du jeu (inchangées d'une version à l'autre) : uniquement la donnée dérivée du disque PS2, zéro fichier du port. À extraire dans `<dossier>/jak1/` (ou via le bouton d'extraction Android).
- Manifestes `.manifest.txt` joints : contenu exact + sha256 de chaque paquet.

Guides d'installation pas-à-pas (Android / Windows / Linux) : https://github.com/moukrea/jak-project/tree/autoport/android-port-ci/docs

Builds par défaut « propres » : uniquement les features validées (herbe Recharged précalculée + ombres, occlusion ambiante, textures custom). Les chantiers en cours (HUD recharged, HD models, overhang, Vulkan) sont exclus du binaire ET des menus, activables uniquement à la compilation par feature flags.
