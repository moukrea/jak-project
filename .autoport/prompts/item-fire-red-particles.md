# Les particules rouges au-dessus des feux, allumees ou eteintes

## Defaut cite
- 2026-09-10 : « je sais pas pourquoi, mais que ce soit on ou off, on a un truc louche au dessus des feux, ca fait des particules rouges bizarres, probablement un des tests/debugs qui est reste la et qui maintenant reste... Faut degager ca c'est horrible »

## Cause connue
Aucun cycle n'a etabli de cause. Owner 10/09 sur le Honor : des particules rouges bizarres au-dessus des feux, PRESENTES que la sortie HDR soit allumee ou eteinte — donc sans rapport avec elle. Il soupconne un reste de test ou de debug laisse dans le code.

## Livrable
`fire_debug_particles` = 0 : recenser TOUT ce qui dessine en rouge sur ou au-dessus des feux et qui n'appartient pas au jeu d'origine — sonde, temoin, marqueur de debug, couleur de secours quand une texture manque. Publier la liste et le compte de dessins par image ; il doit tomber a 0. Nommer la cause trouvee : un reste de debug se SUPPRIME, une couleur de secours se corrige a sa source. L'aspect des feux redevient celui d'origine.

## Preuve exigee
`fire_debug_particles == 0` dans `reports/fire-red-particles/proof.txt`.
Le proof se produit par `lib/proof_run.sh fire-red-particles device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : les feux du jeu, par exemple a Sandover : plus aucune particule rouge etrange au-dessus des flammes, sortie HDR allumee comme eteinte.

## Hors perimetre
Ne pas retoucher les particules d'origine ni leur cadence : on retire ce qui n'a rien a faire la, on ne redessine pas le feu.
