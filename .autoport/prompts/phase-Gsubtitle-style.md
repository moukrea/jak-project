# Gsubtitle-style — sous-titres : blanc plein + vraie ombre portee floue

Demande owner mot pour mot : `.autoport/reports/backlog/owner-2026-08-30-soir.txt`, section 1.

## Ce qu'il demande, exactement
- le NOM du locuteur en debut de ligne GARDE sa couleur et son leger degrade ;
- le RESTE de la ligne passe en BLANC PLEIN ;
- l'OMBRE (nom ET ligne) n'est plus le texte redessine decale en noir plein, mais une
  vraie ombre portee avec un LEGER FLOU — plus moderne et plus lisible ;
- PERIMETRE STRICT : « faut pas que ca change le reste des textes ». Seuls les
  SOUS-TITRES bougent.

## Piege anticipe
L'ombre actuelle est un second passage de dessin du meme texte : elle vit probablement
dans le chemin commun a TOUS les textes. Isoler le chemin sous-titres AVANT de toucher
quoi que ce soit, sinon le perimetre est viole sans que rien ne le signale.

## Preuve exigee
    SUBCOLOR nom_rgb=<...> nom_degrade=<0|1> ligne_rgb=<...>
    SUBSHADOW type=<duplique|ombre-floue> rayon_flou=<px> opacite=<f>
    SUBSCOPE textes_hors_sous_titres_modifies=<n>
La derniere DOIT valoir 0 : recenser les sites de dessin de texte et prouver qu'aucun
autre n'a change (comparaison au bit sur les autres chemins).
