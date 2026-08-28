# Police Urbanist — atlas de glyphes et tables UV

Demande owner 2026-08-28 : « fini le all caps, let's go font moderne », police **Urbanist**.

## Ce qu'il y a ici

- `charset_latin.txt` — **181 caracteres**, DERIVES des 31 banques de texte du jeu
  (`game/assets/jak1/text/*.json`), jamais listes a la main : union des caracteres reellement
  employes par les 30 langues latines, augmentee des minuscules correspondantes (le passage en
  casse normale les rend necessaires, elles sont aujourd'hui quasi absentes des donnees).
- `urbanist-{12,24,48}.png` — atlas 8 bits. `-4bit.png` = meme atlas quantifie sur 16 niveaux,
  ce que le pipeline d'origine sait porter (la police du jeu est en 4 bits, rangee dans le
  tampon de profondeur).
- `urbanist-{12,24,48}.json` — table par glyphe : point de code, rect UV, taille, avance,
  chasse. C'est le remplacant direct de `*font12-table*` / `*font24-table*` (font.gc:40 / :296).
- `gen_atlas.py` — le generateur. Tout est reproductible depuis les TTF + le charset.

## Faits mesures

- Les banques de texte contiennent **475 caracteres distincts**, dont **410 hors ASCII**.
- **Seules 11 minuscules** y apparaissent : le tout-majuscules est dans les DONNEES, pas
  seulement dans la police.
- Le japonais (`game_custom_text_ja-JP.json`) porte **359 caracteres CJK** a lui seul. Urbanist
  ne les a pas et n'a pas vocation a les avoir : **le japonais garde sa police d'origine**, la
  bascule ne concerne que les 30 langues latines.
- Urbanist tel que servi par Google Fonts manque **4 glyphes** utiles : `Đ đ Ł ł` (polonais,
  bosniaque, croate). Ils sont fournis par le sous-ensemble latin-etendu
  (`urbanist-latin-ext-600-normal.woff2`), et le generateur bascule automatiquement par glyphe.

## Ce qui reste a faire

1. Brancher la table UV a la place de `*font12-table*` / `*font24-table*` et etendre la
   correspondance caractere -> glyphe pour que les octets minuscules tombent sur les minuscules.
2. Convertir les textes en casse normale (~670 entrees par langue). C'est le vrai cout, il est
   humain : une conversion automatique casse les acronymes et les noms propres. La regle
   automatique du generateur de previsualisation est un point de depart, pas une livraison.
3. Verifier si le chemin 4 bits est encore actif sur PC/Android : si oui, l'atlas 8 bits ne sert
   qu'a la previsualisation et il faut livrer le `-4bit`.

Licence : Urbanist est sous SIL Open Font License 1.1.
