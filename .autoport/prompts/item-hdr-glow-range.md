> LIS D'ABORD `prompts/item-hdr-glow-range-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le halo mesure pour de vrai : la sonde du chantier A n'a jamais tourne, et le cout en cadence n'est pas chiffre

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
RELEVE DU 11/09 SUR LA PREUVE DE `hdr-source-range` (reports/hdr-source-range/proof.txt). La porte du chantier A a tenu sur `hdr_src_clamped_stages` = 0 / 16 sources vues, mais la MOITIE HALO de son propre livrable n'a jamais ete mesuree : `hdr_src_glow_state` = 2, ce que hdr.cpp:695 traduit par « JAMAIS TENTE » ; `hdr_src_glow_frames` = 0, `hdr_src_glow_px` = 0, `hdr_src_glow_overbright_px` = 0. Ce zero-la ne dit pas « pas de depassement », il dit « pas de mesure ». Le site d'appel existe (sprite/GlowRenderer.cpp:667, dernier etage de la chaine de reduction) : il n'est atteint que si le halo DESSINE. La course de preuve n'est donc pas passee par un endroit qui en porte. Owner 11/09 : « c'es […suite dans le contrat]

## Livrable
`hdr_glow_range_defects` = 0, somme de termes publies SEPAREMENT.
1. `hdr_glow_state` dit que la sonde A TOURNE. Les quatre raisons du retour anticipe de `probe_glow` (mesure eteinte, largeur nulle, hauteur nulle, cible trop grande) deviennent quatre valeurs publiees DISTINCTES : un zero ne doit plus jamais pouvoir se lire comme un « pas de depassement ».
2. `hdr_glow_frames` > 0 et `hdr_glow_px` > 0, avec le lieu de la course publie. La preuve passe par un endroit ou le halo dessine vraiment : un feu ou un portail de teleportation (hutte du Sage vert, Sandover Village).
3. `hdr_glow_overbright_px` et `hdr_glow_max_x1000` publies tous les deux. Un halo qui ne depasse jamais 1,0 est un RESULT […suite dans le contrat]

## Preuve exigee
`hdr_glow_range_defects == 0` dans `reports/hdr-glow-range/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-glow-range device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Le halo : les feux et les portails de teleportation — hutte du Sage vert, Sandover Village..

## Hors perimetre
Ne change ni la courbe ni son ancre : c'est le chantier B. Le format du tampon de scene (`hdr_src_scene_fmt` = RGBA8) n'est pas de ce chantier. Aucun appareil code en dur.
