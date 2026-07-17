# Installer sur Linux

Ce guide vous fait installer **Jak & Daxter** sur un PC sous Linux, pas à pas. Aucune
compétence technique n'est nécessaire : suivez les étapes dans l'ordre, une action à la fois.

> **Il faut posséder le jeu.** L'application ne contient aucune donnée du jeu : celles-ci
> viennent d'une copie PS2 que vous devez posséder légalement.

## Ce qu'il vous faut

- Un PC **x86-64** avec une carte graphique compatible **OpenGL 4.3 ou plus récent**.
- Deux fichiers à télécharger (voir ci-dessous).
- De préférence **`zenity`** ou **`kdialog`** installé (pour la petite fenêtre de choix de
  dossier). Sans eux, le jeu vous demandera le chemin dans le terminal.

## Étapes

1. Ouvrez la page des téléchargements :
   [https://github.com/moukrea/jak-builds/releases](https://github.com/moukrea/jak-builds/releases)

2. Téléchargez le fichier de l'application : **`app-jak1-linux-x86_64.tar.gz`**.

3. Téléchargez aussi le fichier des données du jeu : **`jak1_assets.zip`**
   (environ 1 Go).

4. Ouvrez un terminal dans le dossier où se trouvent vos téléchargements, puis
   décompressez l'application :

   ```
   tar xzf app-jak1-linux-x86_64.tar.gz
   ```

5. Entrez dans le dossier obtenu :

   ```
   cd app-jak1-linux-x86_64
   ```

6. Lancez le jeu une première fois :

   ```
   ./run.sh
   ```

7. Une fenêtre de choix de dossier apparaît. Choisissez (ou créez) le dossier où vivront
   les données de votre jeu. (Sans `zenity` ni `kdialog`, le terminal vous demande
   simplement de taper un chemin.)

8. Le jeu crée un sous-dossier **`jak1/`** dans ce dossier, vous indique d'y extraire les
   données, puis se ferme. C'est normal.

9. Extrayez les données dans ce sous-dossier `jak1/` (remplacez `<dossier>` par le dossier
   choisi à l'étape 7) :

   ```
   unzip jak1_assets.zip -d <dossier>/jak1
   ```

10. Relancez le jeu :

    ```
    ./run.sh
    ```

    Cette fois, il démarre.

## Bon à savoir

- **Vos sauvegardes et vos réglages** sont rangés dans le sous-dossier `jak1/` que vous
  avez choisi. Vous pouvez le sauvegarder ou le copier sans risque.
- **Textures personnalisées** (facultatif) : déposez une image `.png` portant le nom d'une
  texture d'origine (par exemple `sand-01.png`) dans le sous-dossier `custom_assets/`, puis
  activez **« Load custom assets »** dans le menu des options « Recharged » du jeu.
- **Pour les initiés :** `./run.sh --game-root <dossier>/jak1` lance le jeu directement sur
  le dossier indiqué (celui qui contient `assets/`), sans passer par le sélecteur.

## Si ça ne marche pas

- **Aucune fenêtre de choix n'apparaît** (machine sans écran, session SSH…). Utilisez la
  forme explicite : `./run.sh --game-root <dossier>/jak1`.
- **Bibliothèques 32/64 bits manquantes.** Peu probable : l'application est fournie en
  build statique (elle embarque ses dépendances).
