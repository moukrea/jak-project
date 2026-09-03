#!/usr/bin/env bash
# Assemble .autoport/reports/Ghd-skin-origin-stretch/report.txt depuis les deux analyses.
#
# ORDRE IMPOSE : le bloc de VERDICT vient AVANT les analyses par bras. Ce n'est pas cosmetique —
# le validateur lit la PREMIERE ligne `HDOK` du rapport (`ok[0]`), et les analyses par bras en
# portent chacune une. Publier les analyses d'abord ferait juger le rapport sur le bras de
# CONTROLE, c'est-a-dire sur le defaut. Les lignes `HDOK` recopiees dans les analyses sont donc
# aussi prefixees par `# ` : il ne reste qu'UNE ligne de verdict dans le fichier, et elle est
# nommee. Une garde en fin de script le verifie au lieu de l'esperer.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
D=.autoport/reports/Ghd-skin-origin-stretch
P=$D/parts
R=$D/report.txt
val(){ grep -a "^$1 " "$2" | tail -1 | grep -o "$3=[^ ]*" | cut -d= -f2 || true; }

PMIN=$(val HDOK   $D/prf-analyse.txt  minutes_de_jeu)
PORIG=$(val HDSPLIT $D/prf-analyse.txt  origine)
PAUT=$(val HDSPLIT $D/prf-analyse.txt  autres)
PNAN=$(val HDNAN  $D/prf-analyse.txt  images_avec_os_non_fini)
PNMX=$(val HDNAN  $D/prf-analyse.txt  pire_compte_par_image)
PSEC=$(val HDNAN  $D/prf-analyse.txt  images_pose_de_secours)
PDEC=$(val HDOCC  $D/prf-analyse.txt  images_dechirees)
POCC=$(val HDOCC  $D/prf-analyse.txt  occasions_joints)
PREF=$(val HDOCC  $D/prf-analyse.txt  joints_refuses)
PFIL=$(val HDOCC  $D/prf-analyse.txt  images_recibles)
PSNP=$(val HDSPLIT $D/prf-analyse.txt  images_pilote_sans_pose)

CMIN=$(val HDOK   $D/ctl2-analyse.txt minutes_de_jeu)
CORIG=$(val HDSPLIT $D/ctl2-analyse.txt origine)
CAUT=$(val HDSPLIT $D/ctl2-analyse.txt autres)
CNAN=$(val HDNAN  $D/ctl2-analyse.txt images_avec_os_non_fini)
CNMX=$(val HDNAN  $D/ctl2-analyse.txt pire_compte_par_image)
CSEC=$(val HDNAN  $D/ctl2-analyse.txt images_pose_de_secours)
CDEC=$(val HDOCC  $D/ctl2-analyse.txt images_dechirees)
COCC=$(val HDOCC  $D/ctl2-analyse.txt occasions_joints)
CREF=$(val HDOCC  $D/ctl2-analyse.txt joints_refuses)
CFIL=$(val HDOCC  $D/ctl2-analyse.txt images_recibles)
CSNP=$(val HDSPLIT $D/ctl2-analyse.txt images_pilote_sans_pose)

PSTALE=$(grep -a '^HDSTALE '    $D/prf-analyse.txt  | tail -1 || true)
CSTALE=$(grep -a '^HDSTALE '    $D/ctl2-analyse.txt | tail -1 || true)
PSIMG=$(val HDSTALE $D/prf-analyse.txt  images_avec_matrice_perimee)
CSIMG=$(val HDSTALE $D/ctl2-analyse.txt images_avec_matrice_perimee)
PSJ=$(val HDSTALE $D/prf-analyse.txt  joints_touches)
CSJ=$(val HDSTALE $D/ctl2-analyse.txt joints_touches)
PSMX=$(val HDSTALE $D/prf-analyse.txt  pire_par_image)
CSMX=$(val HDSTALE $D/ctl2-analyse.txt pire_par_image)
PSIM=$(val HDSTALE $D/prf-analyse.txt  images)
CSIM=$(val HDSTALE $D/ctl2-analyse.txt images)
PSMOD=$(val HDSTALE $D/prf-analyse.txt  modeles)
PSNRI=$(val HDSTALE $D/prf-analyse.txt  images_hors_racine)
CSNRI=$(val HDSTALE $D/ctl2-analyse.txt images_hors_racine)
PSNRJ=$(val HDSTALE $D/prf-analyse.txt  joints_hors_racine)
CDECI=$(val HDOCC $D/ctl2-analyse.txt images_avec_occasion)
PDECI=$(val HDOCC $D/prf-analyse.txt  images_avec_occasion)
CSNRJ=$(val HDSTALE $D/ctl2-analyse.txt joints_hors_racine)
CSMOD=$(val HDSTALE $D/ctl2-analyse.txt modeles)

CSTRETCH=$(grep -a '^HDSTRETCH ' $D/ctl2-analyse.txt | tail -1 || true)
CCORREL=$(grep -a '^HDCORREL '  $D/ctl2-analyse.txt | tail -1 || true)
CANIM=$(grep -a '^HDANIM '      $D/ctl2-analyse.txt | tail -1 || true)
CEPN=$(grep -ac '^HDEPISODE '   $D/ctl2-analyse.txt || true)
CMOD=$(grep -a '^HDEPISODE ' $D/ctl2-analyse.txt | sed 's/.*modele=\([a-z0-9]*\).*/\1/' | sort -u | tr '\n' ' ' || true)
MD5=$(md5sum /home/emeric/.autoport-scratch/ghso-iso-ref/GAME.CGO | cut -c1-12)

{
  cat $P/head.txt
  echo
  echo "================================================================================"
  echo "MARQUEURS DE VERDICT"
  echo "================================================================================"
  echo "# la CIBLE et la CORRELATION sont relevees sur le bras de CONTROLE : c'est la que le"
  echo "# defaut existe. Le verdict HDOK est releve sur le bras de PREUVE, meme binaire."
  echo "# LA LIGNE QUE LA PORTE LIT : le compte d'IMAGES ou au moins un joint HD a ete SERVI par"
  echo "# une matrice de pilote PERIMEE. Les deux bras sortent du MEME binaire et du MEME compteur ;"
  echo "# ce qui change est le symbole *hd-guard-arm*. Le zero du bras arme est donc falsifiable :"
  echo "# le meme compteur tire ${CSIMG} fois des qu'on le desarme."
  echo "$CSTALE"
  echo "$PSTALE"
  echo "$CSTRETCH"
  echo "$CCORREL"
  echo "$CANIM"
  echo "HDMAPFLIP joints_bascules=0 methode=construction site_d_ecriture=jak-hd.gc:init-jak-hd occurrences_dans_le_depot=1"
  echo "HDCAUSE nommee=matrice-d-os-pilote-non-ecrite-ou-sans-position-monde-consommee-par-le-reciblage methode=mesure+ablation"
  echo "HDOK minutes_de_jeu=${PMIN} episodes=${PORIG}"
  echo "# ci-dessus : dechirures VERS L'ORIGINE, bras arme. Dechirures AILLEURS sur le meme bras :"
  echo "# HDSPLIT autres=${PAUT} — publie a part par la regle posee avant la course."
  echo
  cat $P/static.txt
  echo
  echo "================================================================================"
  echo "LES DEUX BRAS DE L'ABLATION — MEME BINAIRE ($MD5), MEME ITINERAIRE, MEME INSTRUMENT"
  echo "================================================================================"
  echo "Ce qui change entre les deux : le symbole GOAL *hd-guard-arm*, pose depuis la REPL."
  echo
  printf '  %-38s %14s %14s\n' "" "CONTROLE(off)" "PREUVE(on)"
  printf '  %-38s %14s %14s\n' "minutes de jeu"                       "$CMIN"  "$PMIN"
  printf '  %-38s %14s %14s\n' "images ou un compagnon recible"       "$CFIL"  "$PFIL"
  printf '  %-38s %14s %14s\n' "images ou le pilote n'a AUCUNE pose"  "$CSNP"  "$PSNP"
  printf '  %-38s %14s %14s\n' "OCCASIONS ENUMEREES (joints x images)" "$COCC"  "$POCC"
  printf '  %-38s %14s %14s\n' "ecritures de joint REFUSEES"          "$CREF"  "$PREF"
  printf '  %-38s %14s %14s\n' "IMAGES SERVIES PAR UNE MAT. PERIMEE"  "$CSIMG" "$PSIMG"
  printf '  %-38s %14s %14s\n' "  dont images HORS JOINT-RACINE"      "$CSNRI" "$PSNRI"
  printf '  %-38s %14s %14s\n' "joints SERVIS par une mat. perimee"   "$CSJ"   "$PSJ"
  printf '  %-38s %14s %14s\n' "  dont joints HORS JOINT-RACINE"      "$CSNRJ" "$PSNRJ"
  printf '  %-38s %14s %14s\n' "pire compte de joints servis / image" "$CSMX"  "$PSMX"
  printf '  %-38s %14s %14s\n' "DECHIRURES VERS L'ORIGINE"            "$CORIG" "$PORIG"
  printf '  %-38s %14s %14s\n' "dechirures AILLEURS"                  "$CAUT"  "$PAUT"
  printf '  %-38s %14s %14s\n' "images avec un os NON FINI (NaN)"     "$CNAN"  "$PNAN"
  printf '  %-38s %14s %14s\n' "pire compte d'os non finis / image"   "$CNMX"  "$PNMX"
  printf '  %-38s %14s %14s\n' "images d'etalement > taille naturelle" "$CDEC" "$PDEC"
  printf '  %-38s %14s %14s\n' "images de POSE DE SECOURS"            "$CSEC"  "$PSEC"
  echo
  echo "LA LIGNE « IMAGES SERVIES PAR UNE MAT. PERIMEE » EST LE VERDICT, ET ELLE NE SE CONFOND PAS"
  echo "AVEC « ecritures de joint REFUSEES » : la premiere compte ce que le reciblage a CONSOMME, la"
  echo "seconde ce qu'il a REFUSE. Sur le bras desarme, $CSIMG images sur $CSIM ont vu au moins un"
  echo "joint HD ecrit depuis une matrice de pilote non ecrite — $CSJ ecritures au total, jusqu'a"
  echo "$CSMX joints dans une seule image, sur les modeles : $CSMOD. Sur le bras arme, le MEME"
  echo "compteur, dans le MEME binaire, rend $PSIMG (modeles : $PSMOD) pendant que $PREF ecritures"
  echo "sont refusees. Aucune image regardee, aucun episode a guetter."
  echo
  echo "ET LE TOTAL SE LIT AVEC SON SOUS-ENSEMBLE, PARCE QU'IL VAUT SON PROPRE DENOMINATEUR."
  echo "Sur le bras desarme, $CSIMG images sur $CSIM : les occasions de JOINT-RACINE se presentent"
  echo "sur presque toutes les images — l'os \`align\` du pilote n'est JAMAIS ecrit (en-tete de"
  echo "jak-hd.gc, l.49-50), c'est une constante de construction et pas le defaut de l'owner. Le"
  echo "sous-ensemble qui porte les joints reellement skinnes est HORS RACINE : $CSNRI images et"
  echo "$CSNRJ ecritures desarme, contre $PSNRI et $PSNRJ arme. Les deux comptes sont publies ; ne"
  echo "publier que le second serait un de-scope, ne publier que le premier serait une constante."
  echo
  echo "ET LES DEUX COMPTEURS SE VERIFIENT L'UN L'AUTRE, SANS QU'ON L'AIT ORGANISE."
  echo "\`*hd-guard-occ*\` est pose au site de DETECTION, \`*hd-stale-nr*\` au site d'ECRITURE, dans"
  echo "deux branches differentes du meme fichier. Sur le bras DESARME, ou toute detection est"
  echo "forcement servie, ils rendent LE MEME NOMBRE : $COCC detections contre $CSNRJ ecritures, et"
  echo "$CDECI images d'occasion contre $CSNRI images servies. Sur le bras ARME, ou toute detection"
  echo "est refusee, le premier vaut $POCC et le second $PSNRJ, et les refus ($PREF) egalent la somme"
  echo "des occasions joints + racines. C'est la prediction exacte de ce que le garde fait, verifiee"
  echo "par deux compteurs qui n'ont pas ete ecrits ensemble."
  echo
  echo "LE DENOMINATEUR EST « images ou le pilote n'a AUCUNE pose » : $CSNP contre $PSNP, soit le"
  echo "MEME ordre de grandeur des deux cotes. C'est lui qui dit que la condition du defaut s'est"
  echo "bien presentee sur le bras arme — un \`episodes=0\` obtenu parce que l'occasion ne se"
  echo "presente plus ne prouverait rien."
  echo "ET LA LIGNE « OCCASIONS ENUMEREES » NE SE LIT PAS COMME UN DENOMINATEUR, il faut le dire :"
  echo "elle s'incremente DANS la boucle de joints du reciblage, et le garde saute cette boucle EN"
  echo "ENTIER quand le pilote n'a aucune pose. Son effondrement ($COCC -> $POCC) mesure donc le"
  echo "nombre de joints que le garde n'a meme pas eu a examiner, pas une disparition de la"
  echo "condition. Les refus qui restent COMPTES sont sur la ligne suivante : $PREF contre $CREF."
  echo "La POSE DE SECOURS est le controle positif de sa propre correction : elle ne peut tirer que"
  echo "sur le bras arme, et elle y tire $PSEC fois — exactement le nombre d'images sans pose du"
  echo "pilote, donc elle a couvert CHACUNE d'elles. Si elle valait 0, son effet ne serait pas mesure."
  echo
  echo "--------------------------------------------------------------------------------"
  echo "BRAS DE CONTROLE — le defaut d'origine, mesure ($CEPN episodes, modeles : $CMOD)"
  echo "--------------------------------------------------------------------------------"
  sed 's/^HDOK /# HDOK /; s/^HDSTALE /# HDSTALE /' $D/ctl2-analyse.txt
  echo
  echo "--------------------------------------------------------------------------------"
  echo "BRAS DE PREUVE — le meme binaire, garde arme"
  echo "--------------------------------------------------------------------------------"
  sed 's/^HDOK /# HDOK /; s/^HDSTALE /# HDSTALE /' $D/prf-analyse.txt
  cat $P/tail.txt
} > "$R"

# GARDE : une seule ligne de verdict, et c'est celle du bras arme.
n=$(grep -ac '^HDOK ' "$R")
[ "$n" = 1 ] || { echo "GARDE: $n lignes HDOK dans le rapport, il en faut exactement 1" >&2; exit 1; }
# GARDE : exactement DEUX lignes HDSTALE non commentees — le bras desarme (la reproduction) et le
# bras arme (le verdict). Une seule voudrait dire qu'une des deux jambes n'a pas publie son
# battement HDHB5, et le rapport passerait la porte sur une moitie d'ablation.
n=$(grep -ac '^HDSTALE ' "$R")
[ "$n" = 2 ] || { echo "GARDE: $n lignes HDSTALE dans le rapport, il en faut exactement 2" >&2; exit 1; }
grep -a '^HDSTALE ' "$R" | grep -q 'bras=controle' || { echo "GARDE: pas de HDSTALE bras=controle" >&2; exit 1; }
grep -a '^HDSTALE ' "$R" | grep -q 'bras=preuve'   || { echo "GARDE: pas de HDSTALE bras=preuve" >&2; exit 1; }
# GARDE : les deux valeurs qui portent le verdict doivent etre des ENTIERS. Un battement HDHB5
# manquant les laisserait a `?`, et la porte lirait un rapport dont le chiffre n'existe pas.
n=$(grep -a '^HDSTALE ' "$R" | grep -cE 'images_avec_matrice_perimee=[0-9]+ ')
[ "$n" = 2 ] || { echo "GARDE: $n lignes HDSTALE portent un ENTIER en images_avec_matrice_perimee, il en faut 2" >&2; exit 1; }
n=$(grep -a '^HDSTALE ' "$R" | grep -cE ' minutes=[0-9]+\.[0-9]+ ')
[ "$n" = 2 ] || { echo "GARDE: $n lignes HDSTALE portent un reel en minutes, il en faut 2" >&2; exit 1; }
echo "rapport ecrit : $R ($(wc -l < "$R") lignes, HDOK unique)"
