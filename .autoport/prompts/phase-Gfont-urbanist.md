# Gfont-urbanist — police moderne Urbanist et fin du tout-majuscules

## La demande, mot pour mot (owner 2026-08-28)

> « la font dans le jeu est en all caps, ça me saoule [...] pour moderniser, faudrait remplacer
> les caractères par une font plus moderne, Urbanist. Ça rendra tout l'UI, text prompts, menus,
> sous-titres et compagnie up to modern standards. [...] fini le all caps, let's go font
> moderne. »

## DEJA LIVRE — ne pas le refaire

`recharged_assets/font/` contient l'atlas genere et ses tables :

- `charset_latin.txt` — **181 caracteres**, DERIVES des 31 banques de texte du jeu, jamais
  listes a la main.
- `urbanist-{12,24,48}.png` + `-4bit.png` (quantifie 16 niveaux, ce que le pipeline d'origine
  sait porter) et `urbanist-{12,24,48}.json` : point de code, rect UV, taille, avance, chasse.
- `gen_atlas.py` — tout est reproductible.

## Faits mesures — s'appuyer dessus, ne pas les re-decouvrir

- Les banques portent **475 caracteres distincts, 410 hors ASCII**, et **seulement 11
  minuscules** : le tout-majuscules est dans les DONNEES, pas seulement dans la police.
- Le japonais (`game_custom_text_ja-JP.json`) porte **359 caracteres CJK**. Urbanist ne les a
  pas : **le japonais garde sa police d'origine**, la bascule ne concerne que les 30 langues
  latines.
- **FAUSSE PISTE DEJA ELIMINEE** : les textures `ascii.12lo` / `ascii.12hi` / `ascii.24lo` /
  `ascii.24hi` ne sont PAS minuscules/majuscules. `lo`/`hi` sont les moities de bits d'une
  texture 4 bits rangee dans le tampon de profondeur. Ne pas y retourner.
- Urbanist tel que servi manque `Đ đ Ł ł` ; le sous-ensemble latin-etendu les fournit et le
  generateur bascule par glyphe.

## Ce qui reste

1. Brancher la table UV a la place de `*font12-table*` / `*font24-table*`
   (`goal_src/jak1/engine/gfx/font.gc:40` et `:296`) et etendre la correspondance
   caractere -> glyphe pour que les octets minuscules tombent sur les minuscules.
2. **Verifier d'abord si le chemin 4 bits est encore actif sur PC/Android.** Si oui, livrer les
   atlas `-4bit` ; si non, l'atlas 8 bits donne un bien meilleur antialiasing.
3. Convertir les textes en casse normale, ~670 entrees par langue. **C'est le vrai cout, et il
   est humain** : une conversion automatique casse acronymes et noms propres (« PS2 », « 1ST »).
   Anglais et francais relisibles ; les autres langues demandent de la prudence. Publier la
   regle appliquee et la liste des exceptions.

Licence : Urbanist est sous SIL Open Font License 1.1.
