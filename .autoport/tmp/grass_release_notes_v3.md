Build de PLAYTEST jak1 — herbe 3D Recharged (default ON), niveau d'entraînement.

**ITÉRATION 11 — VRAI fix des bords (débordement + trous)**
- L'herbe s'arrête désormais PILE au bord des plateformes : plus de brins qui flottent
  au-delà du contour (au-dessus du vide), plus de zones vides / trous près des bords.
- Cause trouvée (les deux symptômes) : (1) l'itér.10 repliait les triangles d'herbe des
  rebords raides dans le comptage d'arêtes, ce qui reclassait ~960 vraies arêtes de bord
  de plateforme (les "épaules") en INTÉRIEUR (bords rim 2107 → 1147) → l'herbe n'était plus
  découpée là et débordait ; (2) l'itér.10 ne faisait que « pencher » les brins près du bord
  (partiel), donc la hauteur/largeur d'un brin pouvait quand même dépasser le bord.
- Fix géométrique GARANTI (plus d'heuristique) : un bord = arête utilisée par UN SEUL triangle
  d'herbe (fusion des rebords retirée → 2107 vrais bords rétablis) ; le shader CLAMPE l'offset
  horizontal total de chaque brin (largeur + courbure + vent + piétinement) à sa distance au
  vrai bord → aucune géométrie ne peut franchir le bord, hauteur pleine conservée (pas de frange
  rasée, pas de trou). Sur device : 2107 bords, 50397 brins clampés au bord.
- Lighting jour/nuit PARFAIT conservé (strictement inchangé) ; culling stable (0 zone qui
  disparaît en bougeant) ; OFF = rendu stock identique.

⚠ PERF (rappel) : l'herbe coûte cher (~18 fps densité 150% par défaut vs ~39 stock ; ça varie
selon la quantité d'herbe à l'écran). Baisse DENSITÉ / DISTANCES dans GRASS SETTINGS si ça
saccade. Un mode « précalculé » (perf à fidélité égale) est prévu au backlog.

Menu : Recharged Settings > GRASS SETTINGS. OFF = stock. APK autonome, base jak1 v9.
