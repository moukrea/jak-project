# Sortir un vrai signal HDR sur les ecrans qui le supportent

## Defaut cite
- 2026-09-10 : « oui l'image doit pas etre plus sombre au global (ce qui etait mon retour) mais gagner en richesse dans les ombres et lumieres, car l'ecran le supporte c'est litteralement le but du HDR d'avoir plus de detail dans les omb… »

## Cause connue
Essai 6 vert (defects=0) mais VACUEUX. Sur le Honor `hdr_out_hdr_sdr_ratio_x1000` = 1000 : getHdrSdrRatio() reste a 1,0, setExtendedRangeBrightness accepte mais le systeme n'accorde aucune marge (isHighBrightnessModeEnabled=false, mSdrToHdrRatioSpline=null). ON = SDR exact, l'owner ne voit AUCUNE difference on/off (10/09). Les verdicts 8 et 9 passent donc par INACTION. Seul `scrgb_linear` a ete essaye ; les caps annoncent aussi `egl:bt2020_pq`, jamais teste sur cet ecran.

## Livrable
`hdr_out_defects` = 0. Verdicts 1-7 (detection, visibilite conditionnelle, vrai interrupteur `hdr_out_forced_on`=0 persistant, un seul tone map, OFF identique au bit a lighting-hdr, auto-config, `hdr_out_menu_parent`=eclairage) : voir SPEC 4.5. (8) `hdr_out_ui_white_nits` >= blanc SDR du systeme : UI, sous-titres, sprites BLANCS. (9) `hdr_out_darkening_pct` <= 5 : la luminance moyenne globale ne baisse pas. (10) `hdr_out_peak_nits` = pic ANNONCE, courbe adaptative prouvee a deux pics, `hdr_out_peak_adaptive`=1. (11) EFFET MESURE, refus 10/09 : l'image ON doit GAGNER EN DETAIL aux deux bouts par rapport a OFF, sur l'ecran reel. Trois grandeurs, chacune un plancher strict : niveaux distincts dans les ombres, niveaux distincts dans les hautes lumieres, et luminance qui DEPASSE le blanc SDR sur les hautes lumieres (`hdr_out_hdr_sdr_ratio_x1000` > 1000). Identique a OFF = DEFAUT au meme titre qu'assombri : 8 et 9 sont vrais par INACTION. Si le mode retenu n'obtient pas la marge, essayer l'autre chemin annonce dans les caps et publier CHAQUE chemin. Preuve sur le Honor.

## Preuve exigee
`hdr_out_defects == 0` dans `reports/hdr-display-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-display-output device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options : une ligne « sortie HDR » qui n'apparait QUE si l'ecran le supporte. Sur ton Honor elle doit etre la ; activee, les hautes lumieres doivent gagner en eclat sans que le reste change de teinte..

## Hors perimetre
Ne pas regresser le SDR livre. Profils HDR distincts autorises, aucune egalite numerique SDR/HDR exigee. Pas de nouveau chemin LDR demande.
