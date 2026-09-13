> LIS D'ABORD `prompts/item-firstperson-hd-hide-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# En vue premiere personne on se retrouve dans la tete de Jak

## Defaut cite
- 2026-09-13 : « on a une régression sur la vue première personne avec les mo… »

## Cause connue
REGRESSION d'un acquis valide le 2026-08-29 (« Pour la vue en premiere personne et la visiere de Keira c'est regle, bien joue »). L'owner, 13/09 : on voit les modeles HD de Jak et Daxter DE L'INTERIEUR en vue premiere personne. Le correctif d'aout existe dans l'historique (`git log -S` sur le masquage premiere personne des modeles HD, `goal_src/jak1/pc/jak-hd.gc`, `Merc2.cpp`) : chercher d'abord QUEL commit l'a defait — pas de temps fixe (`fixed_tick`), interpolation d'animation (`render_pace`, `*anim-interp-on*`), correctif d'etirement HD — avant de le reecrire. CONTRAINTE DE L'OWNER : ne rien casser de ces trois-la.

## Livrable
`firstperson_hd_inside_px` = 0, somme de termes publies SEPAREMENT.
1. LE COUPABLE EST NOMME : publier le commit qui a defait le masquage (bisect sur la grandeur ci-dessous), et la raison.
2. AUCUN PIXEL DU MODELE HD DE JAK OU DE DAXTER N'EST DESSINE EN VUE PREMIERE PERSONNE : compte de pixels ecrits par leurs draws pendant que la vue premiere personne est active, sur une sequence scriptee qui l'active : zero, avec le compte d'images en premiere personne comme denominateur (non nul).
3. RIEN D'AUTRE NE CASSE : le pas de temps fixe, le jitter d'animation et l'etirement HD gardent leurs cles de preuve (reprendre les cles publiees par leurs items et montrer qu'elles gardent leurs valeurs, avant/apres).
4. LE MASQUAGE EST GARDE PAR UN TEMOIN : publier la cle qui dit que le masquage est actif, pour que la prochaine regression rougisse une porte au lieu d'attendre l'oeil de l'owner.
PREUVE : ` […suite dans le contrat]

## Preuve exigee
`firstperson_hd_inside_px == 0` dans `reports/firstperson-hd-hide/proof.txt`.
Le proof se produit par `lib/proof_run.sh firstperson-hd-hide device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : En vue premiere personne (viser), avec les modeles HD : on ne doit voir ni l'interieur de la tete de Jak ni Daxter..

## Hors perimetre
Ne touche ni au pas de temps fixe, ni a l'interpolation d'animation, ni au correctif d'etirement HD autrement que pour prouver qu'ils tiennent. Tout ce qui n'est pas cet item.
