# Installer sur Android

Ce guide vous fait installer **Jak & Daxter** sur votre téléphone ou votre tablette
Android, pas à pas. Aucune compétence technique n'est nécessaire : suivez les étapes
dans l'ordre, une action à la fois.

> **Il faut posséder le jeu.** L'application ne contient aucune donnée du jeu : celles-ci
> viennent d'une copie PS2 que vous devez posséder légalement.

## Ce qu'il vous faut

- Un téléphone ou une tablette **Android 64 bits (ARM64)**, sous **Android 10 ou plus récent**.
- Deux fichiers à télécharger (voir ci-dessous).
- Une manette Bluetooth (facultatif) — sinon, une manette tactile s'affiche à l'écran.

## Étapes

1. Sur votre téléphone, ouvrez la page des téléchargements :
   [https://github.com/moukrea/jak-builds/releases](https://github.com/moukrea/jak-builds/releases)

2. Téléchargez le fichier de l'application : **`app-jak1-android-arm64.apk`**
   (il arrive dans vos « Téléchargements »).

3. Téléchargez aussi le fichier des données du jeu : **`jak1_assets.zip`**
   (environ 1 Go — laissez le téléchargement se terminer avant de continuer).

4. Ouvrez le fichier **`app-jak1-android-arm64.apk`** depuis vos « Téléchargements »
   pour lancer l'installation.

5. Si Android affiche un message sur les « sources inconnues », **autorisez l'installation**
   (Android bloque par défaut les applications qui ne viennent pas de son magasin ;
   c'est normal ici).

6. Une fois installé, ouvrez l'application **Jak & Daxter**.

7. Au tout premier lancement, un écran de choix apparaît. Touchez le bouton
   **`CHOOSE ASSETS FOLDER`** (« choisir le dossier des données »).

8. Le sélecteur de dossiers d'Android s'ouvre. Choisissez un dossier existant, ou créez-en
   un (par exemple dans la mémoire interne du téléphone), puis touchez
   **« Autoriser »** (ou **« Utiliser ce dossier »**).

9. L'application propose ensuite le bouton **`EXTRACT ASSET ARCHIVE (ZIP)`**
   (« extraire l'archive des données »). Touchez-le.

10. Choisissez le fichier **`jak1_assets.zip`** que vous avez téléchargé à l'étape 3.

11. Laissez l'extraction se faire. Une barre de progression s'affiche (environ 1 Go,
    quelques minutes selon le téléphone). **Ne fermez pas l'application** pendant ce temps.

12. Quand l'extraction est terminée, **le jeu se lance tout seul**. C'est prêt : jouez !

## Bon à savoir

- **Vos sauvegardes et vos réglages** sont rangés dans le dossier que vous avez choisi,
  dans un sous-dossier `jak1/`. Vous pouvez le sauvegarder ou le copier sans risque.
- **Pour mettre à jour le jeu**, installez simplement le nouveau fichier `.apk` par-dessus
  l'ancien : votre dossier de données n'est pas touché, vos sauvegardes restent.
- Sur les lancements suivants, si l'application affiche un bouton **`RETRY <dossier>`**,
  touchez-le : Android demande parfois de reconfirmer l'accès au dossier.
- **Textures personnalisées** (facultatif) : déposez une image `.png` portant le nom d'une
  texture d'origine (par exemple `sand-01.png`) dans le sous-dossier `custom_assets/`, puis
  activez **« Load custom assets »** dans le menu des options « Recharged » du jeu.

## Si ça ne marche pas

- **L'application refuse de s'installer.** Ouvrez les réglages d'Android et autorisez
  l'installation d'applications depuis votre navigateur ou votre gestionnaire de fichiers
  (celui d'où vous avez ouvert le `.apk`), puis recommencez l'étape 4.
- **L'extraction s'est arrêtée en cours de route.** Relancez l'application et refaites
  l'étape 9 (`EXTRACT ASSET ARCHIVE`) : elle repart proprement.
- **Écran noir au tout premier démarrage.** Fermez l'application et rouvrez-la une fois.
