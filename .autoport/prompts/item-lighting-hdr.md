> LIS D'ABORD `prompts/item-lighting-hdr-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-09 : « j'ai pris le dernier build sur jak-builds, activé le realtime lighting et parcouru quelques niveaux... et franchement ça m'a l'air bon [...] j'ai plus de blancs brûlés, j'ai l'impression que ça "pop" un peu plus que sur… »

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
