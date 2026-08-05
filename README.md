<p align="center">
  <img width="500" height="100%" src="./docs/img/logo-text-colored-new.png">
</p>

<p align="center">
  <a target="_blank" rel="noopener noreferrer" href="https://github.com/moukrea/jak-project/actions/workflows/port-ci.yaml"><img src="https://github.com/moukrea/jak-project/actions/workflows/port-ci.yaml/badge.svg?branch=autoport/android-port-ci" alt="Port CI" style="max-width:100%;"></a>
</p>

# Jak & Daxter sur Android, Windows et Linux

Ce projet fait tourner **Jak & Daxter : The Precursor Legacy** (le jeu PS2 de 2001)
**directement sur votre téléphone Android ou votre PC**, comme un vrai jeu natif.

Ce n'est **pas un émulateur** : le code original du jeu a été reconstruit puis recompilé
pour les processeurs modernes (x86-64 pour PC, ARM64 pour Android). Résultat : le jeu
tourne à 60 images par seconde, y compris sur un téléphone de milieu de gamme.

C'est un fork (une version dérivée) du projet [OpenGOAL](https://github.com/open-goal/jak-project),
qui a fait ce travail de reconstruction pour PC. Ici on y ajoute :

- 🤖 **Le portage Android** — le gros morceau : un compilateur ARM64 complet, un rendu
  OpenGL ES, les manettes Bluetooth, les écrans tactiles… Le jeu s'installe comme
  n'importe quelle application.
- 🌿 **Les améliorations « Recharged »** — de l'herbe dense sur les terrains, de
  l'occlusion ambiante (des ombrages plus naturels), des ombres améliorées, le
  remplacement de textures par les vôtres… Chaque amélioration est validée visuellement
  contre le jeu original.
- 📦 **Des versions prêtes à installer** — une application par plateforme, plus une
  archive d'assets, et c'est tout.

> [!IMPORTANT]
> **Il faut posséder le jeu.** Ce projet ne contient aucune donnée du jeu original.
> Les données (graphismes, sons, niveaux…) proviennent d'une copie PS2 du jeu que vous
> devez posséder légalement.

---

## 🎮 Jouer

Vous n'avez **rien à compiler**. Il vous faut deux fichiers, puis 10 minutes :

| Fichier | À quoi il sert |
|---|---|
| `app-jak1-<plateforme>.apk` / `.zip` / `.tar.gz` | Le jeu lui-même (le « moteur » + tout ce qui est propre à ce port) |
| `jak1_assets.zip` | Les données du jeu (~1 Go), issues du disque PS2 |

Les deux se récupèrent sur la page des versions publiées :
👉 **[Releases jak-builds](https://github.com/moukrea/jak-builds/releases)**

Ensuite, suivez le guide de votre appareil — ils sont écrits pour être suivis pas à pas,
sans aucune connaissance technique :

| Votre appareil | Guide |
|---|---|
| 📱 Téléphone / tablette Android | [docs/install-android.md](docs/install-android.md) |
| 🪟 PC sous Windows | [docs/install-windows.md](docs/install-windows.md) |
| 🐧 PC sous Linux | [docs/install-linux.md](docs/install-linux.md) |

### Où vont mes sauvegardes et mes réglages ?

Au premier lancement, le jeu vous demande de choisir un dossier. Il y crée :

```
<votre dossier>/jak1/
├── assets/          les données du jeu (c'est là qu'on extrait jak1_assets.zip)
├── custom_assets/   vos textures personnalisées (optionnel)
├── saves/           vos sauvegardes
└── settings.ini     vos réglages (un fichier texte lisible)
```

Tout est à un seul endroit, facile à sauvegarder ou à déplacer. Pour remplacer une
texture du jeu, déposez simplement un `.png` portant le même nom que la texture
d'origine dans `custom_assets/` et activez « Load custom assets » dans les options —
détails dans les guides.

---

## 🔨 Compiler soi-même

Pour les curieux et les développeurs. Une seule commande par cible, `./build.sh`,
qui produit à la fois l'application et l'archive d'assets :

| Cible | Doc | Où ça se compile |
|---|---|---|
| Linux x86-64 | [docs/build-linux-x86_64.md](docs/build-linux-x86_64.md) | en local |
| Android ARM64 | [docs/build-android-arm64.md](docs/build-android-arm64.md) | en local |
| Windows x86-64 | [docs/build-windows-x86_64.md](docs/build-windows-x86_64.md) | binaires via CI GitHub, empaquetage local |
| macOS ARM64 | [docs/build-macos-arm64.md](docs/build-macos-arm64.md) | CI GitHub (meilleur effort) |

Les **feature flags de build** (`--recharged-hud`, `--grass-overhang`, `--hd-models`,
`--physics` — physique de mouvement secondaire (jiggle/chaînes) sur les modèles HD, exige
`--hd-models` —, `--vulkan-support`, ou `--yolo` pour tout) permettent d'inclure des fonctionnalités
encore en chantier : une fonctionnalité non demandée est **absente du binaire et des
menus**. Le build par défaut, sans flag, ne contient que les améliorations validées.

La règle de tri des deux artefacts est simple : tout ce qui est identique à la sortie
du pipeline OpenGOAL d'origine va dans `jak1_assets.zip` (données pures du jeu) ; tout
ce que ce port modifie ou ajoute va dans l'application. L'archive d'assets ne change
presque jamais — d'une version à l'autre, seul le paquet applicatif est à retélécharger.

---

## 📚 Pour aller plus loin

- [docs/project-overview.md](docs/project-overview.md) — architecture du projet d'origine (anglais)
- [docs/dev/README-upstream-opengoal.md](docs/dev/README-upstream-opengoal.md) — le README du projet OpenGOAL d'origine (anglais)
- [docs/android-honor-cutover.md](docs/android-honor-cutover.md) — procédure de migration d'une ancienne installation Android

## 🙏 Crédits

Tout le travail de décompilation, le compilateur GOAL et le runtime PC viennent du
projet **[OpenGOAL](https://opengoal.dev)** ([open-goal/jak-project](https://github.com/open-goal/jak-project)) —
ce fork n'existerait pas sans eux. Jak & Daxter™ est une marque de Sony Interactive
Entertainment ; ce projet n'est affilié ni à Sony ni à Naughty Dog.
