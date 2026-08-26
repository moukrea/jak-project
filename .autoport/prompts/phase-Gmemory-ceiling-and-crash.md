# PLAFOND MEMOIRE — CHARGEMENT INTERMINABLE ET CRASH

> **INTERDICTION ABSOLUE — L'APPAREIL DE TEST EST LE REDMI `eae4df44`, ET LUI SEUL.**
> Le SEUL appareil autorise est `eae4df44`. Toute autre machine est **HORS LIMITES**. Aucune commande
> adb vers elle : ni `connect`, ni installer, ni lancer, ni lire un log, ni un `keyevent`.
> RIEN. L'owner l'a exige plusieurs fois le 2026-08-26, la derniere en majuscules.
> Si un script du depot vise un autre appareil, **le corriger vers `eae4df44`**, ne pas l'executer.
> Cet interdit ne se leve QUE sur la parole explicite de l'owner.
> Le defaut traite ici est UNIVERSEL : mesures identiques sur les deux machines
> (122,1 Mo par niveau, ~1 300 Mo de RSS). Le Redmi suffit entierement.


**TOP PRIORITE owner, 2026-08-26.** La phase des seins de Keira est MISE EN PAUSE pour celle-ci.

## Ce que l'owner constate (verbatim)

- « le logo apparaît bien après le son qui est sensé être là au moment de son apparition (donc on le
  voit jamais casser au travers de l'écran noir avec le halo lumineux comme c'est prévu dans le jeu,
  alors qu'aucun problème sur x86, Redmi ou Honor... C'est je crois le pire truc honnêtement. »
- « ça crash quand je charge la partie (black screen avec la musique en fond... puis crash) »
- « Nouvelle partie... La cinématique commence avec le fond visuel violacés et la voix de Samos...
  puis ça crash. »
- « l'appareil de test est aussi BEAUCOUP plus puissante que la PS2 sur laquelle on a pas de pop-in ni de
  longs chargements, je vois pas pourquoi ça devrait ramer du cul sur l'appareil de test »
- « je pense qu'il y a un truc qu'on gère très mal et régler le soucis sur l'appareil de test devrait
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
- Un correctif qui aide l'appareil de test doit aider ou etre neutre pour x86 / Redmi (Adreno) / Honor (Mali).
- Assets HD derives des dumps Jak2/Jak3 : jamais dans l'APK, le binaire ou git.

## LEVIER MESURE LE 2026-08-26 : LIBERER LES SOMMETS CPU (−68 % PAR NIVEAU)

Le plus gros poste des 122,1 Mo qu'un niveau garde en RAM est `unpacked.vertices` : **57,0 Mo**.
Ces sommets sont **deja televerses dans le GPU**. Essai realise et MESURE sur le Redmi :

    A54-VERTFREE lev=village1 libere=57.0MB
    memoire du niveau : 122,1 Mo  ->  38,9 Mo      (avec la liberation des tangentes deja en place)

Soit **−68 % par niveau**, et ~166 Mo repris sur les deux niveaux du cache — l'ordre de grandeur
qui manque exactement a l'appareil de test (elle meurt vers 1 200 Mo pour ~2 946 Mo de RAM totale).

### L'obstacle est leve, il reste le SEQUENCEMENT

Les seuls lecteurs de `unpacked.vertices` apres chargement sont les trois mesures de densite UV du
chemin PBR. **Elles sont deja memorisables** : un cache existe desormais dans
`background_common.{h,cpp}` — `uv_density_store(lev, systeme, tex_idx, densite, echantillons)` et
`uv_density_forget_level(lev)`, avec `measure_uv_density_{tfrag,tie,shrub}` qui consultent le cache
en premier. Mesurer au chargement, memoriser, puis liberer.

### PIEGE — deux fonctions mentent sur leur nom (erreur commise, ne pas la refaire)

`Shrub::update_load()` et `Tie3::load_from_fr3_data()` **ne sont PAS des fonctions de chargement**
malgre leur nom : le RENDERER les appelle quand il decouvre le niveau, donc APRES la fin du
chargement. Liberer les sommets a la fin de `Loader::update` (au moment ou le niveau entre dans
`m_loaded_tfrag3_levels`) casse le rendu — mesure : `A42-TFTREE ... draws=80 tris=0 drawn=0/80`
puis `sig=11`.

Il faut donc liberer APRES ces deux consommateurs. Une piste : que le DERNIER consommateur libere
lui-meme (compteur par niveau ; quand `Shrub::update_load` et `Tie3::load_from_fr3_data` ont tourne
pour ce niveau, les sommets partent). `TFragment::handle_initialization` lisait aussi les sommets
pour la densite UV — le cache le couvre desormais.

**NE PAS toucher aux INDEX** : `TFragment` passe `tree.unpacked.indices.data()` au rendu a CHAQUE
frame (le moteur reconstruit ses index par visibilite, comme la PS2). Seuls les SOMMETS partent.

### Preuve attendue
- `A50-LEVRAM` avant/apres sur le meme niveau (reference : 122,1 -> 38,9 Mo).
- RSS du jeu en regime et en pic, sur l'appareil de test, avant/apres.
- `A42-TFTREE` doit montrer `tris` et `drawn` NON NULS : c'est le controle qui a attrape la casse.
- Zero `sig=11` sur un demarrage complet jusqu'a une partie chargee.
