# En vue premiere personne on se retrouve dans la tete de Jak — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

REGRESSION d'un acquis valide le 2026-08-29 (« Pour la vue en premiere personne et la visiere de Keira c'est regle, bien joue »). L'owner, 13/09 : on voit les modeles HD de Jak et Daxter DE L'INTERIEUR en vue premiere personne. Le correctif d'aout existe dans l'historique (`git log -S` sur le masquage premiere personne des modeles HD, `goal_src/jak1/pc/jak-hd.gc`, `Merc2.cpp`) : chercher d'abord QUEL commit l'a defait — pas de temps fixe (`fixed_tick`), interpolation d'animation (`render_pace`, `*anim-interp-on*`), correctif d'etirement HD — avant de le reecrire. CONTRAINTE DE L'OWNER : ne rien casser de ces trois-la.

## Livrable — le contrat, en entier

`firstperson_hd_inside_px` = 0, somme de termes publies SEPAREMENT.
1. LE COUPABLE EST NOMME : publier le commit qui a defait le masquage (bisect sur la grandeur ci-dessous), et la raison.
2. AUCUN PIXEL DU MODELE HD DE JAK OU DE DAXTER N'EST DESSINE EN VUE PREMIERE PERSONNE : compte de pixels ecrits par leurs draws pendant que la vue premiere personne est active, sur une sequence scriptee qui l'active : zero, avec le compte d'images en premiere personne comme denominateur (non nul).
3. RIEN D'AUTRE NE CASSE : le pas de temps fixe, le jitter d'animation et l'etirement HD gardent leurs cles de preuve (reprendre les cles publiees par leurs items et montrer qu'elles gardent leurs valeurs, avant/apres).
4. LE MASQUAGE EST GARDE PAR UN TEMOIN : publier la cle qui dit que le masquage est actif, pour que la prochaine regression rougisse une porte au lieu d'attendre l'oeil de l'owner.
PREUVE : `FEATURE firstperson-hd-hide armed=1 hits=<images en vue premiere personne mesurees>` + la ligne `firstperson_hd_inside_px=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne touche ni au pas de temps fixe, ni a l'interpolation d'animation, ni au correctif d'etirement HD autrement que pour prouver qu'ils tiennent. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

En vue premiere personne (viser), avec les modeles HD : on ne doit voir ni l'interieur de la tete de Jak ni Daxter.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-08-28
> en caméra première personne on se retrouve, quand on utilise les modèles HD, à l'intérieur de la tête de Jak, et on voit aussi le modèle HD de Daxter... d'abord faut corriger le problème et faire comme avec les modèles originaux, les masquer en vue première personne

### 2026-09-13
> on a une régression sur la vue première personne avec les modèles HD de Jak et Daxter, on les voit de l'intérieur, on avait corrigé ça et c'est revenu, faut corriger à nouveau mais attention à rien casser d'autre (Le pas de temps fixe et le jitter des animations+stretch glitch des modèles HD)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

