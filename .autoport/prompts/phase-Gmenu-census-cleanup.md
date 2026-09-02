# Gmenu-census-cleanup — recenser le menu et en sortir ce qui n'a rien a y faire

Questions de l'owner, 2026-08-31 :
  « je vois que des options sont un peu chelou ou carrement inutilisées... recharged assets
    VS HD texture pack ? WTF. Modern Materials c'est quoi ? PBR test preset et PBR isolate
    c'est quoi ? »

## Deja etabli par le superviseur
Deux de ces entrees sont marquees DEBUG DANS NOTRE PROPRE SOURCE
(`goal_src/jak1/engine/ui/text-h.gc`) :
  ligne 825 : « Gpbr-fusion REOPEN #3 (DEBUG, removable): PBR TEST PRESET »
  ligne 836 : « Gpbr-fusion REOPEN #10 (DEBUG, removable): PBR ISOLATE »
Ce sont nos outils de mise au point, laisses dans le menu du JOUEUR. Le mot « removable »
etait deja ecrit a cote ; personne ne les a retires.

## A faire
1. RECENSER toutes les lignes du menu Recharged et publier, pour chacune : ce qu'elle
   fait en une phrase comprehensible, si elle est REELLEMENT branchee (un reglage qui ne
   change rien est aussi un defaut), et si sa place est devant un joueur.
2. RETIRER du menu joueur tout ce qui est marque DEBUG. Les garder derriere le menu de
   debogage si on en a encore besoin.
3. TRANCHER le doublon « Recharged Assets » / « HD Texture Pack » : soit ils font deux
   choses differentes et il faut les NOMMER pour, soit c'est un doublon et il en reste un.
4. « Modern Materials » : le nommer pour ce qu'il fait, ou le fondre dans le reglage PBR
   dont il depend.

L'owner a par ailleurs rouvert la refonte des menus en disant « pas fini du tout » : ce
recensement en est le prealable, il dit ce qu'il y a a ranger.

## Format des marqueurs
    MENUCENSUS lignes=<n> branchees=<n> mortes=<n> debug=<n>
    MENUROW nom=<libelle> fait=<une phrase> branchee=<0|1> place_joueur=<0|1>
    MENUDEBUG retirees_du_menu_joueur=<n> restantes=<n>
    MENUDOUBLON verdict=<doublon-fusionne|deux-choses-renommees> details=<...>
Verifie : MENUCENSUS present ; autant de lignes MENUROW que `lignes` ; MENUDEBUG avec
`restantes == 0` ; MENUDOUBLON tranche ; et zero ligne MENUROW avec branchee=0 laissee
devant le joueur.
