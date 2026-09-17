# SPEC — REFONTE DU HUD DE JAK 1 (« HUD rechargé »)

Owner, 17/09/2026 (ticket JAK-43, mots verbatim dans le backlog) : relance du HUD rechargé, parqué le
09/07. « c'est une refonte du HUD plus moderne ». Cette spec est courte : les assets existent, le
comportement de référence est celui du jeu d'origine.

## 1. Contrat
1. Le HUD rechargé se juge contre CETTE spec, jamais contre l'essai de juillet (DIRECTIVES « Refonte »).
2. ÉTEINT = HUD d'origine, bit-identique. Le réglage vit dans Options > Recharged ; par défaut ALLUMÉ
   quand le maître Recharged est allumé (owner : « je veux le relancer »).
3. Chaque élément rechargé occupe la position exacte de l'élément d'origine qu'il remplace.
4. « les comportements de clignotement/affichage soient identiques à l'original (du moins dans un
   premier temps) » : apparition, disparition, clignotements, cadences, vidage de jauge = ceux du jeu
   d'origine, mesurés sur les mêmes événements.
5. Les polices sont déjà refaites : ne pas y toucher.
6. Aucune preuve visuelle : chaque chantier publie des grandeurs (positions, angles, périodes, comptes
   d'appels). Les captures servent d'illustration sur le ticket, jamais de porte.

## 2. Assets (dans `recharged_assets/`, à cuire dans le build et l'APK)
- Cœur : `jak_heart_0.png`, `jak_heart_33.png`, `jak_heart_66.png`, `jak_heart_100.png`. « du coeur
  vide au coeur plein, faut remplacer l'asset entier à chaque fois ».
- Jauge d'éco : `jak_gauge_empty.png` (base), `jak_gauge_{blue,red,yellow}_full.png` (pleines, par
  éco), `jak_gauge_{blue,red,yellow}_end.png` (embouts, par éco).
- Copies owner des mêmes images : `.autoport/owner-feedback/recharged-hud-jak1/`.

## 3. Le cœur
Santé de Jak → 4 paliers : 100 %, 66 %, 33 %, 0 %. À 33 % : `jak_heart_33` CLIGNOTE par-dessus
`jak_heart_0`, à la cadence du clignotement d'origine. Le mappage santé → palier est publié sur toute
la plage de santé.

## 4. La jauge d'éco
Base vide dessinée ; par-dessus, la jauge PLEINE de l'éco active, MASQUÉE par un secteur (« une sorte
de masque en forme de camembert ») dont l'angle = fraction de remplissage × angle plein ; l'embout de
la couleur active est posé à la frontière du remplissage, tourné pour la suivre. Couleur = éco active.
Le remplissage et le vidage suivent EXACTEMENT la quantité d'éco et sa vitesse de vidage d'origine.

## 5. Les objets en 3D à la place des sprites
« pour la mecamouche du HUD, on utilise la vraie mecamouche du jeu et plus un sprite dégueu, pour
l'orbe, on utilise une vraie orbe […], pour la particule d'éco verte qui flotte à côté du coeur une
vraie particule d'eco verte comme celles qu'on ramasse in game […] et pour la pile d'énergie, idem ! »
Quatre emplacements : mécamouche (vue de face), orbe précurseur, particule d'éco verte, pile d'énergie.
Chaque emplacement dessine le VRAI modèle du jeu (identité du modèle publiée), à la position d'origine,
sans sprite résiduel quand le HUD rechargé est allumé. Coût par image publié.

## 6. Parité des comportements (chantier à part, jugé en dernier)
Journal d'événements du HUD (apparition, disparition, clignotement, flash de dégât, ramassage, vidage)
enregistré sur un rejeu scripté, HUD rechargé ALLUMÉ puis ÉTEINT : mêmes événements aux mêmes images.

## 7. Hors périmètre
Nouvelles polices (faites), nouveaux éléments de HUD, refonte des menus, Jak 2/3.

## 8. Chantiers
hud-heart (§3) · hud-eco-gauge (§4) · hud-3d-pickups (§5) · hud-behavior-parity (§6) · parent
`recharged-hud-jak1` : réglage, ÉTEINT bit-identique, livraison des quatre.
