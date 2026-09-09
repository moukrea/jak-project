# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-09 : « mais si t'as pas de téléphone branché... Tu peux quand même faire sous x86 ! Putain tu me saoules ! »
- 2026-09-09 : « J'ai testé un peu sur le Redmi, ça a pas l'air dégueu en vrai, tu peux vérifier mais je pense qu'on est pas mal (à première vue, j'ai pas check tous les niveaux et compagnie) »
- 2026-09-09 : « J'ai l'impression que quand il fait les captures il les fait même si c'est sur un écran de chargement... Et pas en pleine résolution parce que le jeu à le dynamic resolution scaling activé (en tout cas sous x86) du coup ça doit un peu tout casser... »

## Cause connue
REPRISE 09/09 (Claude apres Codex, essai52 x86 : 4 defauts, hutte et ciels manquants). Le REDMI EST BRANCHE : preuve device en premier. Mecanisme des blancs : SPEC §8 item 2. INSTRUMENT SUSPECT (owner 09/09) : captures prises sur ecran de chargement, et sous echelle de rendu dynamique donc pas en pleine resolution — la preuve ne publie ni l'un ni l'autre.

## Livrable
`hdr_tonemap_defects` = 0, somme de verdicts publies un par un, sur du CIEL (>= 3 niveaux exterieurs, ciel >= 15 % de l'image, heures fixes) ET les 5 verdicts deja tenus (saturation <= origine, contraste hautes lumieres >= 95 %, courbe monotone, jeu ORIGINE-LUMIERE, un seul site de compression dans les 3 configs). S'AJOUTENT, sinon toute capture est nulle : (a) `hdr_cap_loading_frames` = 0 — aucune capture pendant un chargement, un blackout ou sans `*target*` vivant, l'etat est lu dans le moteur ; (b) `hdr_cap_dynscale_armed` = 0 et `hdr_cap_render_scale_x100` = 100 — echelle dynamique DESARMEE et pleine resolution pendant chaque capture, publiees par le moteur, pas supposees. Preuve sur le Redmi.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
