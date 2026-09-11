# La sortie HDR existe aussi sur PC, Windows comme Linux

## Defaut cite
- 2026-09-11 : « ba oui le support HDR sur PC et Linux go ! meme si on a rien pour tester, faut se plug sur ce qu'il faut et zou ! HDR10+ on drop complet alors ! »

## Cause connue
Mesure du 11/09 : `hdr_output.cpp` est compile sur les DEUX plateformes, mais tout ce qui touche a l'ecran — lecture des capacites, demande de marge, bascule de surface — est entre `#ifdef __ANDROID__`. Sur bureau ces fonctions rendent « rien » : il n'y a AUCUN chemin de sortie HDR. L'owner l'avait demande des le 06/09 (« idem sur PC/Linux/Android TV »), ca n'avait jamais ete ouvert. Il n'a aucun ecran HDR sur PC : « meme si on a rien pour tester, faut se plug sur ce qu'il faut ».

## Livrable
`hdr_desktop_defects` = 0. (1) DETECTION : les capacites HDR de l'ecran sont lues sur Windows ET sur Linux, et publiees comme sur Android ; la ligne de menu n'apparait que si un mode est annonce. (2) TRANSPORT : sortie HDR10 (PQ) avec metadonnees STATIQUES (SMPTE2086 + MaxCLL/MaxFALL) ; publier le format retenu, l'espace de couleur reellement obtenu, et la raison de chaque rejet. (3) MEME COURBE QU'ANDROID : l'adaptation au pic annonce et au contenu est le code COMMUN, pas une copie — publier que les deux plateformes appellent la meme fonction. (4) OFF = identique au bit a la sortie SDR actuelle. (5) SANS ECRAN HDR, la preuve est machine : espace de couleur demande et OBTENU, metadonnees effectivement posees, et la courbe exercee a deux pics SIMULES. Ne jamais conclure « ca marche » sur un ecran SDR : dire ce qui est prouve et ce qui attend du materiel. (6) Aucune regression du rendu SDR sur bureau.

## Preuve exigee
`hdr_desktop_defects == 0` dans `reports/hdr-desktop-output/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-desktop-output x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir tant que l'owner n'a pas d'ecran HDR sur PC : la preuve est machine. owner_test=false.

## Hors perimetre
HDR10+ et Dolby Vision sont ECARTES par decision de l'owner du 11/09 : « HDR10+ on drop complet ». Ne pas toucher au chemin Android, qui a son propre item.
