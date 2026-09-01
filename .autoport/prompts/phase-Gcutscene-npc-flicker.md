PNJ QUI APPARAISSENT / DISPARAISSENT PENDANT LES CINEMATIQUES — OWNER 2026-08-31.

  « le problème des modèles des PNJ qui apparaissent, disparaissent et réapparaîssent
    plusieurs fois pendant les cinématiques est revenu ! c'est pas la première fois que ça
    se produit, ça me saoule un peu ! »

CE QUI COMPTE LE PLUS ICI : « EST REVENU » ET « PAS LA PREMIERE FOIS ».
  Ce defaut a deja ete corrige au moins une fois et il est RE-APPARU. Une correction qui
  ne tient pas est le signe que la cause n'avait pas ete atteinte : on avait supprime le
  symptome. Le mandat n'est donc PAS « le faire disparaitre a nouveau », c'est :
    a) retrouver la ou les corrections precedentes de ce meme symptome et dire pourquoi
       elles n'ont pas tenu ;
    b) poser une garde de NON-REGRESSION qui echoue si le symptome revient, faute de quoi
       il reviendra une troisieme fois.
  Sans (b), ce chantier ne vaut rien : c'est deja la deuxieme fois que l'owner le signale.

FAITS DONNES :
  - ce sont les MODELES DE PNJ, pas Jak ni Daxter ;
  - PLUSIEURS cycles apparition/disparition pendant UNE meme cinematique ;
  - c'est visuel ; il ne mentionne pas d'impact sur le deroulement.

LIENS POSSIBLES A INSTRUIRE, SANS LES PRESUPPOSER :
  - Gjak1-crate-collision a etabli que la NAISSANCE D'UN ACTEUR est conditionnee a la
    VISIBILITE CAMERA. Pendant une cinematique la camera saute d'un cadrage a l'autre :
    un PNJ sorti du champ pourrait etre defait puis refait a chaque coupe. C'est la meme
    famille de mecanisme, sur un autre objet.
  - Ghd-skin-origin-stretch traite un autre defaut intermittent des modeles HD.
  Verifier si les PNJ concernes sont des modeles HD ou d'origine : si c'est HD seulement,
  la chaine de reciblage est en cause ; si c'est les deux, c'est la visibilite.

PREUVE EXIGEE :
    NPCFLICK scene=<nom> pnj=<nom> cycles=<n> hd=<0|1>
    NPCPRIOR correction=<phase> pourquoi_pas_tenu=<...>
    NPCGUARD nom=<garde> echoue_si=<...>
    NPCOK scenes=<n> pnj_suivis=<n> cycles=0
Verifie : >= 3 scenes couvertes ; NPCPRIOR renseigne (les corrections passees NOMMEES) ;
NPCGUARD present ; NPCOK avec cycles == 0 sur >= 3 scenes.
