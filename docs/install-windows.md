# Installer sur Windows

Ce guide vous fait installer **Jak & Daxter** sur un PC sous Windows, pas à pas. Aucune
compétence technique n'est nécessaire : suivez les étapes dans l'ordre, une action à la fois.

> **Il faut posséder le jeu.** L'application ne contient aucune donnée du jeu : celles-ci
> viennent d'une copie PS2 que vous devez posséder légalement.

## Ce qu'il vous faut

- Un PC sous **Windows 64 bits**.
- Deux fichiers à télécharger (voir ci-dessous).
- Une manette (facultatif) — branchez-la avant de lancer le jeu.

## Étapes

1. Ouvrez la page des téléchargements :
   [https://github.com/moukrea/jak-builds/releases](https://github.com/moukrea/jak-builds/releases)

2. Téléchargez le fichier de l'application : **`app-jak1-windows-x86_64.zip`**.

3. Téléchargez aussi le fichier des données du jeu : **`jak1_assets.zip`**
   (environ 1 Go — laissez le téléchargement se terminer).

4. Faites un clic droit sur **`app-jak1-windows-x86_64.zip`**, puis choisissez
   **« Extraire tout… »**. Choisissez un dossier de destination, par exemple
   **`Documents\Jak`**.

5. Ouvrez le dossier ainsi extrait, puis double-cliquez sur **`run.bat`**.

6. Une fenêtre de console (fond noir) s'ouvre, puis un sélecteur de dossier apparaît.
   Choisissez (ou créez) le dossier où vivront les données de votre jeu, par exemple
   **`Documents`**.

7. Le jeu crée alors un sous-dossier **`jak1\`** dans ce dossier, vous indique d'y mettre
   les données, puis se ferme. C'est normal.

8. Faites un clic droit sur **`jak1_assets.zip`**, puis choisissez **« Extraire tout… »**.

9. Comme destination, indiquez le dossier **`jak1`** créé à l'étape 7 (par exemple
   `Documents\jak1`). L'archive contient un dossier `assets`, vous obtiendrez donc
   `Documents\jak1\assets`.

10. Retournez dans le dossier de l'application et double-cliquez à nouveau sur **`run.bat`**.
    Cette fois, le jeu démarre.

## Si Windows affiche un avertissement

Windows Defender SmartScreen peut afficher un avertissement au sujet d'une application
inconnue. Cliquez sur **« Informations complémentaires »**, puis sur **« Exécuter quand
même »**.

## Bon à savoir

- **Vos sauvegardes et vos réglages** sont rangés dans le sous-dossier `jak1\` que vous
  avez choisi. Vous pouvez le sauvegarder ou le copier sans risque.
- **Textures personnalisées** (facultatif) : déposez une image `.png` portant le nom d'une
  texture d'origine (par exemple `sand-01.png`) dans le sous-dossier `custom_assets\`, puis
  activez **« Load custom assets »** dans le menu des options « Recharged » du jeu.
- **Pour les initiés :** `run.bat <dossier>` lance le jeu directement sur le dossier
  indiqué, sans passer par le sélecteur.

## Si ça ne marche pas

- **Aucune fenêtre ne s'ouvre** (ou elle disparaît aussitôt). Lisez le texte de la console :
  il vous indique le dossier manquant à créer ou à corriger.
- **Vous avez un dossier `jak1\assets\assets`** (double `assets`). C'est que vous avez
  extrait l'archive dans `jak1\assets` au lieu de `jak1`. Refaites l'étape 9 en visant le
  dossier `jak1`.
- **La manette n'est pas détectée.** Branchez-la **avant** de double-cliquer sur `run.bat`.
