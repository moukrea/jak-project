# Eteindre une option eteint VRAIMENT ce qui en depend, et l'eclairage a son sous-menu — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Owner 10/09 sur le Redmi : « passer a off une option dans les reglages recharges qui desactive d'autres options qui en dependent... Ne desactive pas les options qui en dependent reellement, elles restent actives dans l'etat ou elles etaient quand elles ont ete grisees ». Il soupconne aussi des reglages actifs sous le master Recharged, et relie explicitement les mauvaises perfs du Redmi a ce defaut. Un grisage qui n'eteint rien rend FAUSSE toute preuve ON/OFF du harnais : OFF doit egaler l'ABSENCE.

## Livrable — le contrat, en entier

`gating_defects` = 0. (1) Aucun site n'agit sans lire sa porte (`gating_ungated_sites`=0). (2) Parent OFF : le compteur d'execution de CHAQUE dependante = 0 sur une course reelle. (3) Master OFF : aucun chemin Recharged execute. (4) Une option masquee garde sa valeur et la retrouve au re-ON (`gating_value_restored`=1). (5) Sous-menu « Recharged Lighting », `gating_menu_parent` publie le parent de chaque ligne. (6) La cadence master OFF ne depend pas de l'etat des options desarmees. S'AJOUTE (refus 10/09) : (7) MASQUER, PAS GRISER : une option dont le parent est eteint DISPARAIT de la page — regle generale, pas seulement l'AO. (8) LIBELLE PORTEUR : chaque ligne affiche sa valeur courante (« Occlusion ambiante : HBAO », « Qualite : Moyen », « Force AO : Defaut ») et ouvrir la ligne PRESELECTIONNE la valeur en cours. (9) VRAI SOUS-MENU : les sous-reglages vivent dans une page a eux, pas en petits choix sous la ligne parente.

## Hors perimetre

Aucune optimisation, aucun changement de rendu. On ne touche pas au contenu des features, seulement a leur porte et a leur place dans le menu.

## Ou l'owner regardera

Options > Recharged : eteins une option dont d'autres dependent — les lignes grisees doivent vraiment cesser d'agir, garder la valeur qu'elles avaient, et l'eclairage doit avoir son sous-menu Recharged Lighting.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-10
> j'ai l'impression que passer a off une option dans les reglages recharges qui desactive d'autres options qui en dependent... Ne desactive pas les options qui en dependent reellement, elles restent actives dans l'etat ou elles etaient quand elles ont ete grisees. On devrait avoir tout un sous menu « Recharged Lighting » avec un toggle global (qui passe vraiment tous les elements a OFF derriere le rideau, et grise les options liees avec en valeur la valeur qu'elles avaient au moment du switch off de la feature complete, mais vraiment desactive) et donc dans ce sous menu le Realtime Lighting, le HDR Output, l'Occlusion Ambiante avec ses propres sous reglages et tout ce qui viendra en lien a la refonte de l'eclairage. Et les perfs sur le Redmi, c'est vraiment mauvais, c'est d'ailleurs ce qui me fait penser que desactiver une option ne desactive pas vraiment ce qui en depend et devient grise. Je me demande meme si certains reglages restent pas actives meme avec le master toggle recharged active d'ailleurs

### 2026-09-10
> ca serait top que ses entrees menu genre soient « Occlusion ambiante: Non/SSAO/HBAO/GTAO » et pas « Occlusion ambiante » sans savoir l'option courante (et selection auto de l'item courant quand on tape dans l'option), pareil pour la Qualite: Faible/Moyen/Eleve et Force AO: Plus faible/Defaut/Plus fort. Et d'ailleurs un vrai sous menu pour ces options plutot que les choix en plus petit en dessous (et les options de qualite et force de l'occlusion ambiante devraient tout simplement etre masquees quand l'occlusion ambiante est off plutot que grise, c'est plus simple a comprendre [...] ca devrait d'ailleurs etre comme ca que ca se comporte pour les autres options qui dependent d'une autre option)

### 2026-09-11
> Validé

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

