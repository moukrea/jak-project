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
