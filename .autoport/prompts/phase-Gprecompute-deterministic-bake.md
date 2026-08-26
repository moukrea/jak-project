# PRE-CALCUL DETERMINISTE — cuire dans les .fr3 ce qui ne depend que des .fr3

## Directive de l'owner (2026-08-26, verbatim)

« tout ce qu'on peut pre-computer devrait l'etre au lieu de prendre du temps CPU/GPU c'est debile.
Ca profitera a tout materiel ! Of course les trucs real time, c'est different, mais ce qui peut etre
fait en aval devrait l'etre ! »

Et, sur la subdivision : « je vois pas pourquoi la subdivision serait la solution [...] c'est
p'tetre un truc en lien au PBR, auquel cas ca devrait etre une option ajustable et pas un truc qui
se fait automatiquement ».

## Ce qui est MESURE, pas suppose (2026-08-26, NVIDIA appareil de test, meme scene `lvl=title`)

| | defaut (`max_rounds=3`) | `subdivrounds=1` |
|---|---|---|
| triangles / frame | 7 700 915 | 65 318 |
| temps de rendu | 82,8 ms | 8,1 - 17,9 ms |
| resolution rendue | 768x432 | 1920x1080 |

Et par niveau charge (`A50-LEVRAM`, village1) : sommets 57,0 Mo, index 7,4 Mo, **tangentes 26,3 Mo**,
textures 10,5 Mo. Les tangentes sont reconstruites a chaque chargement (`reconstruct_tfrag_tangents`,
`TFrag3Data.cpp:430`) puis JAMAIS relues cote CPU — verifie : seuls lecteurs = les deux `glBufferData`
de `LoaderStages.cpp` et `MeshSubdivide` qui les ECRIT.

`village1.fr3` : 11,1 Mo compresse -> 35,0 Mo decompresse, disque 0,06 s, zstd 0,14 s. Le cout n'est
donc PAS l'I/O : il est dans les passes deterministes qui suivent.

## Le travail

1. **Cuire les tangentes dans le .fr3** au moment du build (bump de version fr3 + regeneration de
   l'ensemble). Le runtime les lit, les televerse, et n'a plus rien a reconstruire.
2. **Cuire la pre-subdivision** de la meme facon, OU la sortir du chemin automatique.
3. **Faire du niveau de subdivision une option explicite** (reglage utilisateur + defaut documente),
   pas un comportement impose. Le defaut actuel `max_edge_m=1.6 / max_rounds=3` est un multiplicateur
   de geometrie a deux chiffres applique sans que personne l'ait demande, sur TOUTES les cibles.

## Contraintes

- **Aucun changement du rendu temps reel.** Ce qui sort a l'ecran doit etre identique a iso-reglage.
- Le gain doit etre demontre par une MESURE appariee (meme scene, meme niveau), pas par une capture.
- Profite a toutes les cibles : PC x86, Redmi (Adreno), Honor (Mali), appareil de test (Tegra).
- Les assets HD derives des dumps Jak2/Jak3 restent HORS de l'APK, du binaire et de git.

## PRIORITE 1 — MESURE DU 2026-08-26 : LES TEXTURES HD SONT DECODEES A CHAQUE CHARGEMENT

L'owner avait raison de soupconner « les textures HD rechargees, le PBR ». Mesure sur la appareil de test,
demarrage jusqu'a l'ecran-titre :

- **107 etapes de texture, 11,5 s cumulees. 8 etapes concentrent 94 % du temps** (mediane 6 ms,
  pire 2 072 ms). Ce ne sont pas des textures lentes : ce sont huit BLOCAGES.
- Attribution (`A53-TEXLOOKUP`) : `custom_tex::lookup()` **decode un PNG 2048x2048** par texture
  remplacee — 143 a 273 ms chacun. `vil1-sages-stonewall-01` 2048x2048 = 273 ms.
- Et chaque materiau porte **QUATRE** cartes : `<nom>.png`, `_normal.png`, `_roughness.png`,
  `_height.png`, toutes en 2048x2048 (`custom_assets/jak1/recharged_textures/`, 77 Mo de PNG).
  Quatre decodages par materiau ~= 1 s ; huit materiaux dans village1 ~= 8 s.

Consequence visible, rapportee par l'owner : « le logo apparait bien apres le son qui est sense
etre la au moment de son apparition [...] aucun probleme sur x86, Redmi ou Honor ». Le son part a
l'heure, l'image attend le decodeur PNG.

### Ce qu'il faut faire

Cuire ces textures dans un format **pret a televerser** au moment du pack, pas les decoder au
lancement sur chaque machine :
1. Decodage PNG fait EN AMONT, une fois.
2. De preference en format **compresse GPU** (ASTC/ETC2 sur mobile, BC sur desktop) : le decodage
   disparait ET l'occupation VRAM tombe d'un facteur 4 a 8.
3. Le runtime ne fait plus que lire et televerser.

### Piste ECARTEE, ne pas la refaire

`glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY)` etait appele une fois PAR TEXTURE (requete synchrone).
Corrige (mise en cache par contexte, 3 sites) — mesure APRES correctif : 8 blocages toujours la,
pire cas 2 258 ms. **Ce n'etait pas la cause.** Le correctif reste car il est juste, mais il ne
doit pas etre presente comme un gain.
