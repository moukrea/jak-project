> LIS D'ABORD `prompts/item-hdr-glow-range-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le halo mesure pour de vrai : la sonde du chantier A n'a jamais tourne, et le cout en cadence n'est pas chiffre

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
RELEVE DU 11/09 SUR LA PREUVE ET LES SIGNALEMENTS DE `hdr-source-range` (reports/hdr-source-range/proof.txt et FINDINGS.txt).
LE FAIT CENTRAL : sur 10 560 images d'appareil et 8 573 images x86 — dont un teleport dans village1 — `GlowRenderer::flush()` (GlowRenderer.cpp:859) est sorti sur `!m_next_sprite` A CHAQUE FOIS. Pas UN sprite de halo n'a ete soumis. D'ou `hdr_src_glow_state` = 2, que hdr.cpp:695 traduit par « JAMAIS TENTE », et 0 image, 0 pixel, 0 depassement. Ce zero ne dit pas « pas de depassement » : il dit « pas de mesure ». Le chemin du halo — sonde plus cinq reductions, 2,18 Mo — n'est couvert par AUCUNE porte d'AUCUN item, et AUCUNE scene connue du harnais ne l'exerce. Il peut […suite dans le contrat]

## Livrable
`hdr_glow_range_defects` = 0, somme de termes publies SEPAREMENT.
1. LA COUVERTURE D'ABORD, pas le depassement. Publier `hdr_glow_flush_calls` et `hdr_glow_sprites_submitted` sur toute la course. Etablir si ce chemin est ATTEIGNABLE sur ce portage, et nommer ce qui l'alimente. S'il ne l'est pas, c'est CA la reponse de l'item : on la publie chiffree, on ne va pas chercher une scene qui n'existe peut-etre pas. Ne pas confondre avec le halo que l'owner VOIT sur les feux et les portails — s'il est dessine par un autre chemin, dire lequel.
2. `hdr_glow_state` dit que la sonde A TOURNE ou POURQUOI elle n'a pas tourne. Les quatre raisons du retour anticipe de `probe_glow` (mesure eteinte, largeur n […suite dans le contrat]

## Preuve exigee
`hdr_glow_range_defects == 0` dans `reports/hdr-glow-range/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-glow-range device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Le halo : les feux et les portails de teleportation — hutte du Sage vert, Sandover Village..

## Hors perimetre
Ne change ni la courbe ni son ancre : c'est le chantier B. Le format du tampon de scene (`hdr_src_scene_fmt` = RGBA8) n'est pas de ce chantier. Aucun appareil code en dur.
