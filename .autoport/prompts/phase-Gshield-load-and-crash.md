# SHIELD — CHARGEMENT INTERMINABLE ET CRASH AU CHARGEMENT DE NIVEAU

**TOP PRIORITE owner, 2026-08-26.** La phase des seins de Keira est MISE EN PAUSE pour celle-ci.

## Ce que l'owner constate (verbatim)

- « le logo apparaît bien après le son qui est sensé être là au moment de son apparition (donc on le
  voit jamais casser au travers de l'écran noir avec le halo lumineux comme c'est prévu dans le jeu,
  alors qu'aucun problème sur x86, Redmi ou Honor... C'est je crois le pire truc honnêtement. »
- « ça crash quand je charge la partie (black screen avec la musique en fond... puis crash) »
- « Nouvelle partie... La cinématique commence avec le fond visuel violacés et la voix de Samos...
  puis ça crash. »
- « la SHIELD est aussi BEAUCOUP plus puissante que la PS2 sur laquelle on a pas de pop-in ni de
  longs chargements, je vois pas pourquoi ça devrait ramer du cul sur la SHIELD »
- « je pense qu'il y a un truc qu'on gère très mal et régler le soucis sur la SHIELD devrait
  bénéficier toutes les targets de test actuelles »

Il a RAISON : le Tegra X1 n'est pas plus faible que le Redmi. Ne jamais repondre « la machine est
petite ».

## DEFAUT 1 — le logo arrive apres son signal sonore (MESURE, cause identifiee)

Demarrage jusqu'a l'ecran-titre : **107 etapes de texture, 11,5 s cumulees, dont 8 etapes = 94 % du
temps** (mediane 6 ms, pire 2 072 ms). Ce ne sont pas des textures lentes, ce sont 8 BLOCAGES.

Attribution mesuree (`A53-TEXLOOKUP`, instrumentation posee dans `LoaderStages.cpp`) :
`custom_tex::lookup()` **decode un PNG 2048x2048** par texture remplacee, 143 a 273 ms chacun. Et
chaque materiau porte QUATRE cartes (`<nom>.png`, `_normal`, `_roughness`, `_height`), toutes en
2048x2048 (`custom_assets/jak1/recharged_textures/`). ~1 s par materiau, ~8 materiaux dans village1.

**Le decodage PNG au lancement est la cause.** Correctif attendu : cuire ces textures en amont dans
un format pret a televerser (idealement compresse GPU : ASTC/ETC2 mobile, BC desktop). Le runtime ne
doit plus que lire et televerser. Voir la phase `Gprecompute-deterministic-bake` qui suit.

## DEFAUT 2 — crash au chargement de niveau (MESURE, cause NON identifiee)

Le processus meurt **au premier plan, sans aucun signal** (`ActivityManager: Process
org.opengoal.gk.jak1 has died: fg TOP`, pas de SIGSEGV, pas de tombstone) : c'est le
`lowmemorykiller`. Derniere ligne moteur avant la mort :
`NOTE: coming out of blackout on next frame, doing all loads now...`

Chiffres :
- RSS du jeu : ~940-990 Mo en regime, pics mesures a 1 212-1 234 Mo pendant un chargement.
- RAM totale de l'appareil : 2 946 Mo. Swap zram : 512 Mo, **41 Mo libres** (sature).
- Par niveau (`A50-LEVRAM`, village1) : sommets 57,0 | index 7,4 | tangentes 26,3 | textures 10,5 |
  merc 3,5 | collision 6,9 = **111,5 Mo**, tombe a 85,2 apres liberation des tangentes (fait).
- **NON EXPLIQUE : deux blocs anonymes de 150,32 Mo chacun, entierement residents** (smaps,
  `scudo:secondary`). Ce ne sont ni les tampons fr3 (village1 : 11,1 Mo compresse -> 35,0
  decompresse), ni les donnees merc (3,5 Mo), ni les cartes PBR (qui ne gardent que des ids GL).
  **300 Mo sur ~950 : c'est le plus gros levier connu et il faut l'identifier.**

## Pistes ECARTEES — ne pas les refaire

- `glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY)` appele par texture : corrige (3 sites), mesure APRES
  correctif = 8 blocages toujours la, pire 2 258 ms. **Pas la cause.**
- Reduire le cache de niveaux de 3 a 2 (`LEVEL_TOTAL` -> `LEVEL_MAX`) : aucun gain memoire (pic
  847 contre 850) et **REGRESSION** — geometrie evincee relue, 7,7 M triangles/frame, ecran noir.
  Annule.
- La pre-subdivision (`debug.opengoal.mesh.subdivrounds`) : vrai gain de PERFORMANCE (ecran-titre
  7 700 915 -> 65 318 triangles, 82,8 -> 8,1 ms, 768x432 -> 1920x1080) mais **ne corrige ni le
  crash ni le logo tardif**, et penalise identiquement les cibles qui n'ont pas le probleme.
- Le manque de RAM comme explication suffisante : REFUSE par l'owner, a raison. La PS2 tenait dans
  32 Mo. Chercher ce qu'on gere mal, pas ce qui manque.

## Contraintes

- Toute conclusion doit s'appuyer sur une MESURE nommant sa scene, jamais sur une capture.
- Un correctif qui aide la Shield doit aider ou etre neutre pour x86 / Redmi (Adreno) / Honor (Mali).
- Assets HD derives des dumps Jak2/Jak3 : jamais dans l'APK, le binaire ou git.
