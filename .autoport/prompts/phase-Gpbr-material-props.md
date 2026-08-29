# Gpbr-material-props — des proprietes de matiere pour les 172 textures, DANS le depot d'assets

## La demande de l'owner, et son reproche

> « je veux des config de matériaux par matériaux, pas seulement les normales, roughness et height
> en image, mais des PROPRIÉTÉS ! [...] on a des normales pour un mur en pierre taillée et de
> l'herbe par exemple, peut-être qu'on veut pas que la texture de height ait le même impact de
> profondeur »

Et sur l'emplacement :

> « ces props doivent faire partie du repo Recharged assets, pas dans l'APK »

La phase precedente a livre **7 matieres sur 172**, ecrites dans `recharged_assets/materials.txt`
DANS jak-project. C'est faux sur le compte ET sur l'emplacement.

## ETAT MESURE (2026-08-29) — partir de la, ne pas re-mesurer

Depot `moukrea/recharged-assets` :

- **172 matieres**, chacune avec `albedo.png`, `normal.png`, `roughness.png`, `height.png`
  sous `raw/jak1/<tpage>/<texture>/`.
- **172 fichiers de metadonnees deja en place** sous `metadata/jak1/materials/<tpage>/<texture>.json`.
  Ils decrivent les IMAGES (espace colorimetrique, canaux, dimensions, mode alpha) et ne portent
  **AUCUNE propriete de matiere**. La structure existe, il manque le bloc.
- Aucune carte de metallicite, d'occlusion ambiante ni de speculaire : ces trois-la ne peuvent
  venir que d'une decision par matiere.

Le moteur applique deja **dix reglages par matiere**
(`game/graphics/opengl_renderer/loader/CustomTextureReplacements.cpp:824-860`, parses vers :1090) :

    relief   relief_depth   relief_lambda   spec
    rough_nomap   rough_scale   metal_nomap   metal_scale
    reflectance   normal_y

**Rien n'est a ecrire cote moteur pour les appliquer.** Ce qui manque est le REMPLISSAGE et la
LECTURE depuis le depot d'assets.

## PIEGE MEMOIRE — deja paye deux fois, un reboot

**NE JAMAIS faire un `git clone` normal de ce depot.** Le filtre LFS deballe des centaines de
textures au checkout, sature la memoire et TUE LE SHELL. C'est arrive deux fois le 2026-08-29.

La forme qui marche, verifiee, 1,4 Mo :

    GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none --no-checkout <url> rca

Recuperer ensuite les images **par petits lots nommes**, jamais le depot entier. Si `git lfs pull`
ne rend rien (constate : 0 objet, sans erreur), deux voies de repli : les archives de release que
le jeu telecharge deja (`assets.lock.json` porte l'URL du manifeste), ou les textures presentes
sur l'appareil.

## INTERDIT EXPLICITE

**Ne PAS deduire la famille de matiere depuis le NOM du fichier.** L'owner : « la déduction du nom
est complètement teubé ». Il faut REGARDER l'albedo. Une passe de vision sur l'image, pas sur la
chaine de caracteres.

## Le travail

1. **Schema** : un bloc de proprietes dans le fichier de metadonnees de chaque matiere, portant
   les dix reglages du moteur. Le definir une fois, le documenter dans le depot d'assets.
2. **Recuperer les albedos** par lots surs, et les REGARDER pour classer la matiere.
3. **Remplir les 172** avec des valeurs coherentes par famille — pierre taillee, sable, herbe,
   bois, metal, tissu, eau, glace... La profondeur de relief d'un mur de pierre n'est pas celle
   de l'herbe : c'est le test que l'owner citera.
4. **Cote moteur** : lire les proprietes depuis le depot d'assets telecharge, et
   **SUPPRIMER `recharged_assets/materials.txt`** de jak-project.

## Exige pour fermer

1. Les **172** matieres ont un bloc de proprietes. Publier le compte, pas une affirmation.
2. Les valeurs viennent d'un examen de l'ALBEDO. Publier, pour au moins 10 matieres, la famille
   retenue et pourquoi.
3. Deux familles nettement differentes rendent des reliefs **mesurablement** differents sur la
   meme scene. Publier les deux valeurs.
4. `recharged_assets/materials.txt` n'existe plus dans jak-project.
5. Les proprietes sont lues depuis le depot d'assets, prouve par une trace au chargement.

---

# OUTIL FOURNI — comment recuperer les images (2026-08-29)

**`git lfs pull` NE MARCHE PAS sur ce depot : il se BLOQUE.** Il demarre sa file de
telechargement, n'affiche rien, et se fait tuer par le delai. Ce n'est ni le disque, ni les
droits, ni le reseau — l'API du serveur repond, elle, immediatement.

**Utiliser `.autoport/lfs_fetch.sh`**, ecrit et teste le 2026-08-29 : il interroge l'API batch
directement et telecharge fichier par fichier.

    cd <clone>            # obtenu avec GIT_LFS_SKIP_SMUDGE=1 --filter=blob:none --no-checkout
    git checkout HEAD -- raw/jak1/<tpage>/<texture>/albedo.png    # pose le POINTEUR
    REPO_DIR=$(pwd) bash /home/emeric/code/jak-project/.autoport/lfs_fetch.sh \
        raw/jak1/<tpage>/<texture>/albedo.png

Verifie : deux albedos recuperes, 6 Mo chacun, 2048x2048 RGB.

**Budget** : 172 albedos ~ 1 Go, pour 12 Go libres sur le disque. Recuperer PAR LOTS, jamais tout
d'un coup, et effacer au fur et a mesure si la place se tend. Ne PAS recuperer les normales,
rugosites et hauteurs : la classification se fait sur l'ALBEDO seul, c'est 4 fois moins de donnees.

**La cle USB n'est pas une option** : testee le 2026-08-29, elle lit a 122 Mo/s et REFUSE toute
ecriture (erreurs d'E/S du noyau sur chaque secteur). Materiel verrouille.
