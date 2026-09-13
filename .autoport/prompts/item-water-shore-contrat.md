# Des vagues tranquilles qui arrivent une a une et remontent le sable — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. La houle ND monte et descend de +/-0,75 m mais aucune vague n'ARRIVE ; le rivage est un masque d'alpha a 4 couleurs, aucune ecume nommee (SPEC 2.1). Une bande d'ecume constante exige une DISTANCE au rivage, pas une profondeur (SPEC 1.3 d3).

## Livrable — le contrat, en entier

Le compagnon <niveau>.waterbake (shore_sdf par jump flood, shore_dir, floor_depth, flow) produit par tools/water_bake depuis la collision croisee avec le fr3, charge a cote du fr3, ignore proprement si absent/perime (waterbake_missing). Vagues GEOMETRIQUES en vertex en 4 phases sur d (houle 40->12 m, cambrure 12->3 m par la raideur Q, deferlement 3->0 m, jet de rive 0->-4 m), plafond 0,30 m, periode ~7 s, aucune ecume au large ; trois ecumes ; sable mouille via shade(). SPEC 5.5. Publie shore_wave_amp_max_mm (<=300), shore_runup_max_m (<=4), shore_wave_period_s, shore_band_width_var. PREUVE : `FEATURE water-shore armed=1 hits=<vagues arrivees a d=0 (comptees au deferlement)>` + la ligne `waterbake_sdf_coverage_pct=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-shore"), jamais armed(), et n'en ecris pas un second. CONTRAT SURFACES MEUBLES (prompts/SPEC-surfaces-meubles.md section 10) : publier chaque image la phase du jet de rive en UN scalaire (slot par image, jamais un pointeur), lisible par la coque de sable, et la cle `shore_phase_published=1` ; la coque LIT shore_sdf au bake et cette phase au runtime, elle n'ecrit jamais dans le .waterbake.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de tempete, pas de vague au-dessus de 0,30 m. La borne |visuel - jeu| <= 0,45 m reste publiee.

## Ou l'owner regardera

la plage de Sandover (beach) : des vagues calmes qui arrivent, se cambrent, deferlent en ecume et lechent le sable avant de se retirer

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-09
> faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se jettent

### 2026-09-09
> pour la mer, j'attends quand même des vagues sur le rivage, on voit bien l'eau monter et descendre dans le jeu, on perçois que c'est plus par contrainte technique qu'ils ont pas mi de vagues que par choix. ça justifiera l'écume et ça aura un effet Waouw. bien sûr on est pas sur des vagues énormes et un tempête, faut rester cohérent la mer a l'air tranquille, donc les vagues sont tranquilles

### 2026-09-09
> bah je valide, beau boulot !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

