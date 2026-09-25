# Le vieux reglage « rt-light » disparait comme le veut la SPEC : telephone et PC eclairent par le meme chemin

## Defaut cite
- 2026-09-25 : « Bah logiquement oui puisqu'il faut se conformer à la spec dans l'idée, si ça collide pas avec un truc déjà prévu, go »

## Cause connue
Signale par le worker de lighting-local-lights (reports/.../FINDINGS.txt) : `game/graphics/opengl_renderer/background/background_common.cpp:2856`, le sous-reglage rt-light (SPEC-refonte-lumiere §7.3 : RETIRE ; lignes 288-302 : `recharged_rt_light_enable` par defaut false, u_rt_light_on choisit entre les composites A, B, C, D) vaut 0 sur le telephone et 1 au bureau (`light_census_gate_nonzero_u_rt_light_on` = 0 sur 22 016 poussees appareil contre 42 160/42 160 x86). C'est ce qui a tenu les lampes eteintes 3 essais ; tout chantier d'eclairage calibre au bureau mesure un composite que le telephone ne prend pas. Verifier d'abord qu'aucun item ouvert ne prevoit deja ce retrait (aucun trouve le 25/09).

## Livrable
1. Retirer rt-light (reglage, uniforme u_rt_light_on, branche morte D) : le composite ne depend plus que du maitre Recharged / eclairage recharge, identique telephone et PC.
2. OFF de l'eclairage recharge reste bit-identique a l'origine (SPEC §7.3).
3. UNE grandeur : `rt_light_toggle_defects` = lectures restantes de rt-light/u_rt_light_on dans le code + ecart de composite choisi entre la course telephone et la course PC ; doit valoir 0.
4. Les acquis d'eclairage deja valides (lighting-bake, lighting-regimes) restent verts.

## Preuve exigee
`rt_light_toggle_defects == 0` dans `reports/lighting-rt-light-toggle-removed/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-rt-light-toggle-removed x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
