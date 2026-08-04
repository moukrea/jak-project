# Grecharged-hd-models4 — HD MODELS M2 : remplacements PRINCIPAUX Daxter / Keira / Samos

## PRÉREQUIS ABSOLU
NE COMMENCE PAS tant que **Grecharged-hd-models3** (M1 = Jak seul, anim-retarget) n'est pas
**owner-accepté** (le HD Jak s'affiche correctement en jeu sur device, verdict de l'œil de l'owner).
M2 réutilise EXACTEMENT le même pipeline que M1 ; tout fix trouvé en M1 (positionnement/culling,
timing des os, ordre matriciel, chargement d'art-group externe) s'applique tel quel ici.

## LA ROADMAP DE L'OWNER (2026-08-03, verbatim consolidé — NE PAS dévier)
Toujours des modèles de **CINÉMATIQUES** (les plus détaillés). Sourcing par personnage :

1. **Daxter** = le modèle des **cinématiques de JAK 3, SANS pantalon**.
   - L'owner a VÉRIFIÉ que Daxter ne change pas de look entre Jak 1, 2 et 3 (il ne gagne un pantalon
     qu'à la toute fin de Jak 3 en cinématique). **Ne perds pas de temps à re-vérifier.**
   - Donc le plus qualitatif pour le Daxter de Jak 1 = cinématique Jak 3 (version SANS pantalon !).
2. **Keira** = le modèle « cinématique » de la **TOUTE PREMIÈRE cutscene de Jak 2**.
   - Après cette première cinématique elle change légèrement (sandales → bottines). La première
     version est donc la plus proche de son look Jak 1, au max de détail.
3. **Samos** = le modèle « cinématique » de **Jak 3** (il ne change pas de look entre les jeux,
   celui du 3 est probablement le plus détaillé).

C'est TOUT pour les remplacements principaux (avec le Jak de M1 : les 4 personnages couverts).
Les looks alternatifs (bonus) sont la phase SUIVANTE (Grecharged-hd-models5), pas celle-ci.

## MÉCANISME (identique à M1 — réutilise, ne réinvente pas)
Par personnage : rip du modèle cinématique (fr3_to_gltf foreground export sur le bon niveau du
decompiler_out de jak2/jak3 — dumps présents : iso_data/jak2 + iso_data/jak3) → prep GLB
(scripts/shell/prep_hd_actor_glb.py, garde le squelette HD) → art-group via build_actor (nom COURT
<16 chars, ex. dax-hd / keira-hd / samos-hd — limite fakeiso) → table k→e par personnage
(scripts/shell/retarget_fill_table.py, avec le driver jak1 correspondant : sidekick pour Daxter, etc.)
→ append merc au fr3 du niveau approprié (hd_merc_swap add ; Daxter=GAME.fr3/COMMON,
Keira/Samos=village1.fr3) → companion process par personnage (généralise jak-hd.gc ; le driver de
Daxter est `sidekick`, ceux de Keira/Samos sont leurs actors respectifs) → réglage/flag existant
(recharged-enhanced-models?).

## RÈGLES QUI S'APPLIQUENT (non négociables)
- **IP Naughty Dog** : assets dérivés jak2/jak3 = pack EXTERNE uniquement, gatés sur les dumps,
  JAMAIS dans l'APK/le binaire/git (recharged_assets/hd_* est gitignoré).
- **PAS de re-rig** (le REPLACE des poids = le « carnage » rejeté). Anim-retarget uniquement.
- Preuve device : le personnage HD est VISIBLE et suit ses animations en VRAI gameplay (l'owner est
  le juge visuel ; pas de « pas de crash » = validé). Ne livre RIEN d'invisible/cursed.
- Écris/adapte le validator de CETTE phase au démarrage (celui référencé est celui de M1).

## PROGRESSION AUTORISÉE (owner protocol) 2026-08-04 09:00 — M1 pré-gaté par le superviseur
M1 (hd-models3) validé + pré-gaté : défauts 5+6 corrigés (owner-confirmés), long jump INNOCENTÉ
(bug overlay tactile toggle-indépendant, piste séparée), l'owner re-vérifie depuis OWNER-VERIFY-QUEUE.md.
CARRY-OVERS dans TON scope (ils font partie de la généralisation multi-personnages) :
1. **Jak INVISIBLE au logo ND** : la suppression Merc2 d'eichar-lod0 s'applique à l'acteur du logo
   alors que le companion ne couvre que *target* → supprimé sans remplaçant. Le fix M4 = la
   suppression ne s'applique QUE quand un companion couvre CET acteur cette frame (per-actor
   coverage), ce qui est exactement le mécanisme dont Daxter/Keira/Samos ont besoin (leurs drivers
   sont des acteurs non-*target*). Règle owner : « le modèle choisi PARTOUT » (logo, cinématiques, jeu).
2. M1 polish encore ouvert (l'owner testera ; rouvrable) : yeux blancs (eye_id), gap cran→cheveux
   (on voit l'intérieur de la tête), visage inanimé (blerc), clipping vêtements. Si tes mécanismes M4
   règlent l'un d'eux au passage (eye_id du pipeline d'append, blerc généralisé), prends-les.

## ============================================================
## VERDICT OWNER 2026-08-04 ~10:5x (build M4 sur son Honor) — CYCLE DÉFAUTS 2 = la barre maintenant
## ============================================================
Les 3 primaires rendent, mais la qualité n'y est pas. Verbatim owner classé par MÉCANISME (il a
lui-même le bon diagnostic : « le transfert par liens de bones entre l'original et la version HD
n'est pas tip top ») :

### A. YEUX / VERRES BLANCS — SYSTÉMIQUE (3 personnages)
- Jak : yeux blancs (connu M1). Keira : yeux blancs. Samos : les VERRES de ses lunettes sont blancs
  au lieu de laisser voir les yeux. => le binding eye_id (texture œil dynamique 0xefffff00|id) manque
  pour TOUS les mercs appendés. UN fix pipeline (append + eye_id correct par personnage) règle les 3.

### B. VISAGES TOTALEMENT IMMOBILES EN CINÉMATIQUE — SYSTÉMIQUE (tous)
- Jak, Keira, Daxter, Samos : visage figé. => les companions ne pilotent AUCUN canal facial (blerc).
  Investiguer le mirror des canaux blerc du driver vers les blend-targets du modèle HD (les modèles
  ciné jak2/jak3 ont leurs propres targets). Si le mapping facial jak1->jak2/3 ne mappe pas,
  documenter honnêtement la limite ET voir ce qui est récupérable (au moins la mâchoire parlante).

### C. GÉOMÉTRIE MANQUANTE — CLASSE RIP/PREP/APPEND (2 cas)
- **Daxter : PAS DE MÂCHOIRE — cursed, dents qui flottent dans le vide** (le même symptôme que le
  vieux re-rig ! le rip/prep du daxter-highres perd le draw de la mâchoire, ou ses verts pèsent sur
  un joint non mappé). PRIORITÉ 1 de ce cycle.
- Jak : gap cran->cheveux (connu M1, on voit l'intérieur de la tête). Même classe : compter les draws
  donor vs appendé, et vérifier les joints des verts de la pièce manquante.

### D. PRÉCISION DU MAPPING k->e — CLASSE LIENS D'OS (3 cas)
- Keira : DOIGTS « cassés » en cinématique (joints de doigts non mappés / mal mappés -> repos).
- Samos : le bas de sa BARBE pointe vers l'avant (joints de barbe non mappés -> pose de repos).
- Jak : clipping vêtements (connu M1). => auditer la table k->e par personnage : lister les joints
  0xFF (non mappés) et leur impact visuel ; les chaînes doigts/barbe/cheveux ont besoin d'un mapping
  ou d'un fallback qui suit le parent mappé le plus proche (PAS le repos world).

### E. RENDU FOURRURE — TRANSPARENCE (1 cas)
- Daxter : on voit AU TRAVERS de sa fourrure (alpha/draw-order/backface du merc appendé).

### F. SOURCING KEIRA — À VÉRIFIER
- Le modèle livré a des BOTTINES, pas des sandales. L'owner : « il est possible que dans la première
  cinématique de Jak 2 elle ait déjà des bottines, mais pas sûr ». => vérifier s'il existe une
  variante sandales dans les rips jak2 (autres niveaux/cutscenes) ; si la 1ère ciné a déjà des
  bottines, le dire à l'owner (le modèle actuel est alors le bon) ; sinon sourcer la bonne.

Positif owner : Keira « la moins buggée », Samos « vraiment pas mal » à part verres/barbe.
ORDRE : C-Daxter (mâchoire, cursed) > A (yeux, un fix pour 3) > D (doigts/barbe/mapping) > E (fourrure)
> B (visages/blerc) > F (sourcing Keira). Preuves device par personnage, l'owner juge.

### CORRECTION OWNER 2026-08-04 ~11:05 sur la classe B (visages) — LA BARRE EST : TOUTES LES ANIMS
« Au minimum la mâchoire qui parle... Non faut TOUTES les animations ! »
=> Le fallback mâchoire-seule N'EST PAS la cible, et « documenter la limite » N'EST PAS une sortie
acceptable pour cette classe. La barre : le visage HD reproduit TOUTES les animations faciales du
driver (blerc/blend-targets complets, yeux compris — la classe A eye_id et la classe B convergent ici).
Investiguer à fond le pipeline facial : comment jak1 anime les visages (blerc channels sur le driver),
ce que portent les modèles ciné jak2/jak3 (leurs propres blend-targets, a priori PLUS riches), et le
mapping canal→target par personnage. Si un canal donné n'a réellement AUCUNE contrepartie dans le
modèle HD, le documenter cas par cas avec la preuve — pas d'abandon de classe entière.
