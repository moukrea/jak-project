# Cutover Honor — nouveau layout `<racine>/jak1/` (Grecharged-buildsys-firstboot)

Procédure écrite pour le Honor de l'owner. **Exécutée uniquement à sa demande** (owner:
"Pour mon Honor tu me demanderas via ADB de récupérer les sauvegardes et de virer
l'ancienne app pour réinstaller le build propre"). Le Redmi (eae4df44) suit la même
procédure, exécutée par le harnais.

Aucune migration automatique n'existe (choix owner) : l'ancien arbre `OpenGOAL/jak_1/`
et l'ancien `pc-settings.gc` sont abandonnés. Seules les **sauvegardes** (memory cards,
format binaire inchangé) sont transportées à la main. Les réglages des menus sont à
refaire une fois (ils vivent désormais dans `<racine>/jak1/settings.ini`, format INI).

## 0. Pré-requis
- Le Honor branché en USB, débogage ADB activé, écran déverrouillé.
- Le nouveau build : `app-jak1-android-arm64.apk` + `jak1_assets.zip` (sortis de
  `./build.sh android-arm64 --package`, voir `out/artifacts/`).

## 1. Récupérer les sauvegardes de l'ancienne app
Les saves peuvent être à deux endroits selon le mode dans lequel tournait l'app :
```bash
S=<serial-honor>
mkdir -p /tmp/honor-saves
# a) arbre externe (mode externe, le plus probable)
adb -s $S pull /storage/emulated/0/OpenGOAL/jak_1/saves /tmp/honor-saves/external || true
# b) stockage interne (ancien mode interne)
adb -s $S exec-out run-as org.opengoal.gk.jak1 sh -c \
  'cd files/.config/OpenGOAL/jak1 2>/dev/null && tar cf - saves' > /tmp/honor-saves/internal.tar || true
```
Vérifier qu'au moins un des deux contient des fichiers `*.bin` (memory cards) avant de
continuer. **Ne pas passer à l'étape 2 sans une copie vérifiée.**

## 2. Virer l'ancienne app et l'ancien arbre
```bash
adb -s $S uninstall org.opengoal.gk.jak1
adb -s $S shell rm -rf /storage/emulated/0/OpenGOAL
```

## 3. Installer le build propre
```bash
adb -s $S install -i com.android.vending out/artifacts/app-jak1-android-arm64.apk
```
(Si le téléphone affiche un dialogue d'installation, valider à l'écran.)

## 4. Premier démarrage — picker natif
Lancer l'app. Elle demande l'accès "Tous les fichiers" puis ouvre le sélecteur de
dossier natif : choisir l'emplacement voulu (ex. la racine du stockage → l'app crée
`OpenGOAL/jak1/{assets, custom_assets, saves}`). Puis extraire `jak1_assets.zip`
via l'écran d'extraction de l'app (ou le pré-pousser :
`adb -s $S push <extrait>/. /storage/emulated/0/OpenGOAL/jak1/assets/`).

## 5. Remettre les sauvegardes dans le nouvel arbre
```bash
adb -s $S push /tmp/honor-saves/external/. /storage/emulated/0/OpenGOAL/jak1/saves/ 2>/dev/null || true
# ou depuis la copie interne :
# tar xf /tmp/honor-saves/internal.tar -C /tmp/honor-saves && adb push /tmp/honor-saves/saves/. /storage/emulated/0/OpenGOAL/jak1/saves/
```

## 6. Vérifier
- Relancer l'app : elle doit démarrer **sans re-prompter** (racine mémorisée).
- `adb -s $S shell head -1 /storage/emulated/0/OpenGOAL/jak1/settings.ini` → `[settings]`.
- Charger une partie depuis les memory cards restaurées.
- Régler les menus une fois (langue, options graphiques…) → les choix persistent dans
  `settings.ini` (modifier → quitter → relancer → toujours appliqués).

## custom_assets (bonus)
Déposer un PNG nommé comme une texture d'origine dans
`/storage/emulated/0/OpenGOAL/jak1/custom_assets/` et activer « LOAD CUSTOM ASSETS »
dans les options : la texture remplace l'originale au chargement suivant.
