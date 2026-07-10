Build de PLAYTEST jak1 — herbe 3D « Recharged » (default ON) sur le niveau d'entraînement (Rocher du Geyser).

## Cette itération : LE bug de culling / désinstanciation en bougeant est corrigé À LA RACINE (vérifié en mouvement sur ta Redmi)

Ton blocage n°1 — « en bougeant, des zones entières disparaissent / des zones qui chargent pas / du pop-in », sur la vraie herbe 3D **ET** les cards — est réglé pour de bon.

**Ce qui n'allait pas (vraie cause) :** l'herbe était placée *autour de la caméra* (fenêtre de 64 m) et le champ n'était re-calculé que par sauts de 20 m, avec une densité re-jugée à chaque recalcul selon la distance à la caméra. Résultat exact : le sol au-delà de 64 m n'avait pas d'herbe tant que tu n'avais pas marché (« zones qui chargent pas »), un nouveau champ apparaissait d'un coup tous les 20 m (« pop-in »), et un chunk devenu plus loin perdait ses brins (« des chunks se désinstancient malgré la proximité »). Les correctifs précédents (« nearest-first / cap 220k ») ne touchaient aucune de ces 3 causes — d'où le bug qui persistait.

**Le fix :** l'herbe est maintenant placée **UNE SEULE FOIS au chargement du niveau, sur TOUT le niveau, indépendamment de la caméra**, et elle **ne bouge plus jamais** en marchant. Le LOD (brins près / cards au milieu / rien au loin) se fait entièrement dans le shader d'après la caméra en direct, par-dessus un champ toujours complet. Donc : plus aucune zone qui disparaît, qui ne charge pas, ni de pop-in.

**Preuve objective (en mouvement) :** rendu instrumenté pour logger, à chaque frame et en marchant, le nombre de « chunks » à portée vs réellement dessinés. Sur toute la marche : **DROPPED = 0 sur 100 % des frames** (chaque chunk à portée est toujours dessiné), et 283–335 chunks que l'ancien code aurait lâchés restent en place. (screenrecord en mouvement + log par-frame à l'appui.)

## Autres retours de ta liste
- **Herbe plus longue / plus fournie** : brins ~2× plus hauts et plus larges qu'avant (lecture plus dense/luxuriante), l'herbe couvre tout le sol « herbe » sans trous.
- **Grass cards à distance** : elles s'affichent maintenant au loin (avant, la fenêtre de 64 m faisait qu'il n'y avait rien à placer plus loin).
- Cards = touffes découpées (alpha-cut), pas des rectangles, et elles ondulent au vent comme les brins.

## Rappels
- **Toggle** : Graphic Options > Recharged Settings > **RECHARGED GRASS**. Default **ON**. OFF = rendu **stock, identique à l'original** (vérifié par A/B objectif OFF↔ON au même point de vue sur ta Redmi : ON = brins 3D denses ; OFF = texture plate d'origine).
- **Perf (honnête)** : ~27–44 fps herbe ON selon le point de vue (60 fps OFF). Réglable en une constante si tu trouves ça trop lourd.
- Herbe en **couleur plate** (pas encore de texture — c'est voulu à ce stade), écrasement sous Jak (trample), brise par brin.

Dis-moi surtout : **est-ce que des zones disparaissent encore en bougeant ?** Et : densité OK ? longueur OK ? cards crédibles au loin ?
