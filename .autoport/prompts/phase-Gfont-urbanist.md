# Gfont-urbanist — un rendu de texte MODERNE A COTE, pas une torsion de l'ancien

## DECISION D'ARCHITECTURE DE L'OWNER, 2026-08-28 — elle remplace le brief precedent

> « Plutôt que bidouiller le système de fonts existant et de le tordre dans tous les sens...
> Pourquoi pas plutôt en faire un tout nouveau à côté bien propre ? Avec des textures haute
> résolution pour les glyphs, un alignement qui se base sur ce que la font fait vraiment, un
> kerning idem... Ça nous permettrait de pouvoir le toggle on/off en settings recharged pour
> basculer entre l'affichage de texte original (menus, hints, subtitles) et le nouveau plus
> moderne basé sur Urbanist ! Beaucoup plus clean je pense »

**L'approche « adapter la table existante » est ABANDONNEE.** Ce qui suit dit pourquoi, avec les
mesures qui l'ont montre — toutes faites le 2026-08-28.

## Pourquoi l'ancien systeme ne peut pas porter le besoin

1. **La grande police est PHYSIQUEMENT incapable d'ecrire en minuscules.** Ses 26 cellules a-z
   contiennent des KANJI (撃 賢 湖 口 行...). Il n'y a rien a « brancher » : il faut de toute
   facon un nouvel atlas.
2. **Elle n'a pas d'avance par glyphe.** `*font24-table*` donne l'avance CONSTANTE 24,0 pour tous
   les caracteres. Aucun kerning n'existe nulle part.
3. **Elle est en 4 bits, rangee dans le tampon de profondeur** via une relocation PS2
   (`setup-font-texture!`, format `mt4hl`, textures `ascii.12lo/12hi/24lo/24hi` — `lo`/`hi` sont
   des MOITIES DE BITS, pas la casse). Plafond : 16 niveaux d'antialiasing.
4. **Les trois defauts vus par l'owner viennent tous de ces hypotheses** : alignement par groupe
   de lettres, espacement constant, et une conversion de casse qui ne peut pas s'afficher.

## Ce qui est deja livre et REUTILISABLE tel quel

`recharged_assets/font/` :
- `charset_latin.txt` — 181 caracteres DERIVES des 31 banques de texte du jeu.
- `urbanist-{12,24,48}.png` (8 bits) + `.json` : par glyphe, point de code, rect UV, largeur,
  hauteur, **avance** et **haut de boite**. 73 avances distinctes, 16 hauteurs de boite.
- `Urbanist-700.ttf` (graisse validee par l'owner) + `gen_atlas.py`, tout reproductible.
- `.autoport/design/font-metrics-proof.png` : la meme phrase rendue avec et sans les metriques.
  **Le nouveau rendu doit egaler la ligne du BAS.**

Cout memoire d'un atlas 8 bits 2048x1024 : **2,0 Mo**. A comparer aux 744 Mo du jeu — non
significatif. Ne pas sacrifier la qualite pour ca.

## Ce qu'il faut construire

Un chemin de rendu de texte SEPARE, qui ne touche pas l'ancien :

1. **Atlas haute resolution en 8 bits**, hors du tampon de profondeur, avec un vrai alpha.
2. **Positionnement a la ligne de base**, depuis le `by` de chaque glyphe — pas le haut de
   cellule.
3. **Avance par glyphe**, depuis `adv` — pas un pas constant.
4. **Kerning** : ajouter les paires au generateur (`gen_atlas.py` lit deja le TTF, FreeType
   expose les paires). Publier le nombre de paires retenues.
5. **Bascule dans les reglages « recharged »**, comme le `master-toggle` existant : texte
   d'origine ou texte moderne. **Par defaut : moderne** (c'est la demande de l'owner), l'original
   reste disponible.

## PORTEE MESUREE — le vrai risque

**135 appels a `draw-string`** dans jak1, repartis ainsi :

    23  pc/subtitle.gc          22  engine/debug/anim-tester.gc
    12  engine/debug/menu.gc    11  engine/ui/hud-classes.gc
     8  pc/progress-pc.gc        7  pc/util/pc-pad-utils.gc
     6  engine/game/main.gc      4  pc/debug/anim-tester-x.gc

**Une bascule qui ne couvre pas tous les sites est pire que pas de bascule** : l'utilisateur
verrait deux polices en meme temps. Les sites de DEBUG (anim-tester, menu) peuvent rester sur
l'ancien chemin — le dire explicitement plutot que de l'oublier.

**Second risque, a mesurer avant de livrer** : des metriques differentes REFLOWENT le texte. Les
boites de dialogue, les lignes de sous-titres et les colonnes de menu sont dimensionnees pour
l'ancienne avance constante. Publier, pour les ecrans les plus denses, la largeur rendue avant et
apres, et signaler tout depassement de boite.

## Exige pour fermer

1. Le rendu moderne egale `font-metrics-proof.png` ligne du bas — aligne, espace correctement.
2. La bascule fonctionne dans les deux sens sans redemarrage, et **la liste des sites couverts et
   non couverts est publiee**.
3. Le nombre de paires de kerning est publie.
4. Aucun depassement de boite sur les ecrans denses ; les largeurs avant/apres sont publiees.
5. **La sortie ANDROID du texte est regeneree** (`out/jak1-android-text/`) : c'est un chemin de
   sortie distinct de `out/jak1/iso/`, il etait perime du 11 aout et c'est ce qui a fait voir du
   tout-majuscules a l'owner sur le Redmi alors que son portable etait correct. Prouver par la
   DATE ET LE CONTENU du fichier embarque dans l'APK.
6. Publier la liste des langues encore en majuscules : seules 7 ont un `game_case_text_*.json`
   (de-DE, en-GB, en-US, es-ES, fr-FR, it-IT, ja-JP).
