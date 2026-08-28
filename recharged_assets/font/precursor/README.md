# Alphabet precurseur — atlas et table, traces depuis la planche de correspondance

Demande owner 2026-08-28 :

> « pour que le texte Precursor soit cohérent en dessous, on pourrait très bien avoir une font
> Precursor qui ait les glyphs correspondants à la LANGUE dont "Loading..." est affiché ! Donc en
> français on aurait "CHARGEMENT" en Precursor sous "Chargement..." [...] les fonts disponibles en
> ligne n'ont pas une licence claire, donc on doit la faire nous même. »

## Ce qu'il y a ici

- `source-precurian-latin.png` — la planche de reference fournie par l'owner (1607x1181).
- `glyphs/A.png` .. `glyphs/Z.png` — les **26 glyphes** decoupes un par un, detoures a leur encre.
- `precursor-atlas.png` — atlas 512x512, 8 bits, meme format que l'atlas Urbanist.
- `precursor.json` — meme schema que `urbanist-*.json` : point de code, rect UV, largeur, hauteur,
  avance. **Le meme moteur de rendu consomme les deux sans cas particulier.**

## Comment il a ete produit

Segmentation automatique de la planche : seuil sur l'encre NOIRE (les etiquettes latines sont
grises et tombent d'elles-memes), detection des 4 bandes de glyphes par profil horizontal, puis
decoupe en colonnes avec fusion des morceaux distants de moins de 40 px — plusieurs glyphes ont
des points detaches qui appartiennent a la meme lettre.

Verification : **4 bandes trouvees, 8 + 8 + 8 + 2 colonnes, soit exactement 26 glyphes A-Z**,
sans ecart entre le nombre de colonnes detectees et le nombre de lettres attendues.

## RESERVE HONNETE sur l'avance

La planche est une **grille de presentation** : elle ne porte aucune metrique d'avance d'origine.
L'avance livree est une CONVENTION : `largeur du glyphe + 0,30 x em`. Elle est reglable et n'a
aucune autorite. Si l'owner trouve le mot trop serre ou trop lache, c'est ce seul nombre a changer.

## Usage prevu

Le mot latin est translittere lettre par lettre, puis la ligne entiere est mise a l'echelle pour
egaler la largeur MESUREE du texte localise au-dessus. Preuve : `.autoport/design/precursor-proof.png`

    Loading...      largeur 210 px  ->  LOADING     echelle 0,483
    Chargement...   largeur 310 px  ->  CHARGEMENT  echelle 0,554
    Cargando...     largeur 255 px  ->  CARGANDO    echelle 0,562

La largeur de la ligne precurseur egale celle du texte latin dans les trois cas, ce qui est
exactement ce que l'owner demandait.

## Limites connues

- **26 lettres, rien d'autre.** Pas de chiffres, pas d'accents. « CHARGEMENT » passe ; une langue
  dont le mot porte un accent (par ex. l'espagnol « CARGANDO » n'en a pas, mais d'autres si) devra
  se rabattre sur la lettre non accentuee. A trancher langue par langue.
- Les langues non latines (japonais) n'ont pas de translitteration evidente : prevoir un repli.
