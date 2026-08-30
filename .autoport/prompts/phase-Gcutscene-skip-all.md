# Gcutscene-skip-all — passer TOUTES les cinematiques en maintenant cercle

Demande owner mot pour mot : `.autoport/reports/backlog/owner-2026-08-30-soir.txt`, section 2.

## Ce qu'il demande, exactement
- UN geste couvre TOUTES les cinematiques, y compris les CONTEXTUELLES (Geyser Rock),
  que le mecanisme actuel ne couvre pas ;
- geste : MAINTENIR CERCLE deux secondes ;
- indice : icone du bouton + « Skip » / « Passer », LOCALISE, en bas a droite ;
- l'indice apparait des qu'on touche UN bouton pendant une cinematique ;
- cartouche a COINS ARRONDIS autour de l'indice, qui SE REMPLIT sur les deux secondes.

## Etat existant mesure par le superviseur
`skip-movies?` est lu dans `process-taskable.gc:277` ; entree de texte `cutscene-skips`
(#x1501) et indice `pc-text-hint-cutsceneskips` (#x179d) existent deja. Les cinematiques
CONTEXTUELLES n'empruntent pas ce chemin : c'est exactement le trou decrit.

## Premier livrable, avant tout cablage
Un RECENSEMENT de tous les chemins de cinematique du jeu, avec pour chacun : passe-t-il
par `skip-movies?` ou non. Sans ce recensement on recreera le meme trou ailleurs.

## Preuve exigee
    CUTPATHS total=<n> couverts_avant=<n> couverts_apres=<n>
    CUTSKIP scene=<nom> type=<film|contextuelle> saut=<ok|echec>
    CUTHINT apparait_sur_bouton=<0|1> position=<bas-droite> localise=<n langues>
    CUTFILL duree_ms=<...> coins_arrondis=<0|1>
`couverts_apres` doit valoir `total`. Au moins une ligne CUTSKIP avec type=contextuelle
et saut=ok — c'est le cas que l'owner cite (Geyser Rock).
