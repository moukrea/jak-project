# La clipmap remplace le microcode VU1, la houle reste celle de Naughty Dog — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

17/09 RETOUR OWNER sur c42de2 : « la nouvelle mer ressemble trait pour trait à l'ancienne, sauf que elle est opaque » ; « sur le title screen l'eau est noire » ; « avant cette reprise les vagues ressemblaient plus à des vagues ». La porte de hauteur de jeu a tenu, mais l'alpha a 1 (defaut n°1 du FINDINGS, non traite) est une REGRESSION visible, l'ecran titre noir aussi. 3 essais : d'abord A et B (regressions), puis C. Ne pas toucher a la hauteur de jeu (water_gameplay_height_maxdelta_mm reste a 0).

16/09 ARBITRAGE OWNER : « 2 a » = 3 essais pour corriger les defauts NOMMES dans FINDINGS.txt, dans cet ordre, rien d'autre : (1) ocean_recharged.frag ecrit alpha=1 : restituer l'attenuation ND jusqu'a zero (ocean_recharged.vert:60 / OceanNear_PS2.cpp:1205) ; (2) anneaux qui se recouvrent sans morphing de bord ni culling par les 36 spheres ND (OceanRecharged.cpp:195) ; (3) houle A conservee sans DMA near et sans identite de carte, OFF/ON sans reactivation (OceanRecharged.cpp:723/733/755, OceanNear.cpp:30) ; (4) comparateur raster ND/clipmap par niveau/cellule absent (OceanRecharged.cpp:326) : le construire, c'est lui qui juge 1-3. Chaque defaut corrige = un terme publie ; un terme non mesure compte comme defaut. Ne pas rouvrir les 6 essais precedents : lire leur handoff, repartir de leur code.

LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. L'ocean mid ecrit la profondeur en GL_ALWAYS au bucket 4 AVANT le monde et le near au 63 sans Z (SPEC 2.1) : la profondeur de scene est illisible au dessin. Les 64 frames 32x32 de houle sont LUES par le gameplay a 4 endroits : elles se conservent comme couche A (SPEC 5.2).

## Livrable — le contrat, en entier

Sous recharged_water : buckets 4 et 63 consomment leur DMA sans dessiner ; OceanRecharged dessine la clipmap 3 anneaux (SPEC 5.3) en W2a, couche A captee au DMA near, MEME modulo 32 que ocean-get-height, decoupe par les masques ND. Shading provisoire = l'actuel. OFF = graphe ORIGINE bit-identique. Publie water_visual_excess_mm (<= 450) et gpu_ms_ocean. PREUVE : `FEATURE water-ocean-mesh armed=1 hits=<sommets deplaces>` + `water_gameplay_height_maxdelta_mm=` seule sur sa ligne. S'AJOUTE (refus 10/09) : L'EAU NE SORT PAS DE SON LIT — Forbidden Jungle, la riviere qui prolonge la mer (mini-jeu du pecheur), la houle deborde. Mesurer par niveau et par cellule l'emprise de l'eau DESSINEE contre celle de l'origine : aucun pixel d'eau la ou l'origine n'en dessine pas, excedent publie et nul. Verifier nommement les jonctions mer/riviere.

RETOUR OWNER 17/09 (build c42de2, porte tenue mais REFUSE) — verdicts ajoutes, chacun publie a part dans `water_ocean_owner_defects` :
A. TRANSPARENCE : l'eau n'est plus opaque. Publier l'alpha effectif ecrit par le fragment (min/max sur la surface visible) : max < 1 et attenuation vers zero au bord comme Naughty Dog (ocean_recharged.vert:60 / OceanNear_PS2.cpp:1205) ; un alpha constant a 1 est un defaut.
B. ECRAN TITRE : l'eau n'est pas noire sur l'ecran titre. Publier la luminance moyenne de la mer sur l'ecran titre, comparee a celle du build d'avant la reprise (reference archivee) ; ecart > tolerance = defaut.
C. LES VAGUES RESTENT DES VAGUES : la houle visible n'est pas plus plate qu'avant la reprise. Publier l'amplitude de deplacement vertical et la variance des normales de la surface, meme vue, meme instant de houle, contre le binaire d'avant water-ocean-mesh ; une baisse > 10 % = defaut.
`water_ocean_owner_defects` = A + B + C + (water_gameplay_height_maxdelta_mm != 0), un terme non mesure compte 1. C'est LA porte depuis le 17/09 : la hauteur de jeu seule ne suffit plus.

DECISION 1 DE LA SPEC (1.3), partie non portee (audit 17/09) : TESSELLATION par-dessus la clipmap aux paliers Haut et Ultra, anneau proche raffine x2 a x8 par la tessellation existante (tfrag3_tess.*). Publier le facteur effectif par palier et le nombre de triangles de l'anneau proche, Haut et Ultra contre Bas. A traiter APRES les verdicts A, B, C.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines bit-identiques : master OFF et recharged_water OFF ; tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2). La hauteur de JEU ne bouge pas.

## Ou l'owner regardera

Forbidden Jungle, la riviere qui prolonge la mer (mini-jeu du pecheur) : la houle ne deborde plus du lit. Puis la mer depuis Sandover.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-09
> faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se jettent

### 2026-09-09
> la refonte de l'eau doit pouvoir être toggled off individuellement aussi, ou on retrouve l'eau vanilla.

### 2026-09-09
> bah je valide, beau boulot !

### 2026-09-10
> pour la refonte de l'eau, si j'ai bien compris la t'as remplace l'eau Vanilla par la nouvelle avec les nouvelles vagues... Je sais pas ce qui est attendu mais je peux te dire qu'en l'etat elle est opaque (donc on voit pas les orbes sous l'eau par example), les vagues suivent une seule direction au lieu d'epouser la cote (c'est peut-etre tout voulu ou attendu en l'etat, mais je te fais le feedback)

### 2026-09-10
> la riviere de forbidden jungle sort litteralement de son lit avec les vagues, bizarre ! Je parle de la partie qui prolonge la mer, c'est la ou il y a le mini jeu avec le pecheur

### 2026-09-17
> Alors je sais pas si c'est intentionnel mais la nouvelle mer ressemble trait pour trait à l'ancienne, sauf que elle est opaque.... avant cette reprise les vagues ressemblaient plus à des vagues et le build que je teste (celui de 6h20 et quelques) sur le title screen l'eau est noire (c'est bon une fois en jeu) évidemment qu'elle ne sort plus du lit de la rivière qui se jette dans la mer de forbidden jungle vu que c'est exactmeent pareil que l'eau du jeu original sauf qu'elle est opaque...

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

