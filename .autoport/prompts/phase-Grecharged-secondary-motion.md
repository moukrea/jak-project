# Grecharged-secondary-motion — physique secondaire (jiggle / chaînes) sur les personnages HD

## LA VISION (owner, 2026-08-04 — assumée et cadrée)
Jak and Daxter est un platformer de teenager où Keira est volontairement sexualisée (hanches larges,
taille fine, poitrine affirmée, sous-vêtements qui dépassent, ventre exposé) — c'est assumé par le jeu
(Daxter la drague, love interest de Jak). Pour le remake, maintenant que Keira est en HD :
**jiggle physics de poitrine** — « rien de fou », un mouvement **naturel et cohérent**, indépendant du
corps, comme ç'aurait été fait à l'époque si la PS2 l'avait permis. Subtilité = la barre ; l'owner juge.

## PÉRIMÈTRE (dans l'ordre de valeur)
1. **Keira (HD)** : poitrine — chaîne(s) de physique subtile.
2. **Samos (HD)** : la barbe — APRÈS résolution de ses défauts (clip + bout vers l'avant, cycle 3).
3. **Jak (HD)** : vraie physique sur les vêtements — col, partie bleue au-dessus du pantalon blanc,
   toutes les lanières de cuir qui pendent, cheveux. (Remplace/complète « l'illusion de physique »
   actuelle des vêtements.)
4. **Cheveux longs, tous personnages concernés** : Keira, Samos, Jak, le méchant (Gol) — à discuter
   par personnage (l'owner tranchera sur pièce).
5. **Maia + l'archéologue** (designs attractifs assumés) : PAS de modèle HD aujourd'hui → évaluer la
   faisabilité honnêtement : leurs squelettes stock n'ont probablement pas d'os de chaîne au bon
   endroit ; options = injection d'os + transfert de poids sur le modèle stock (même mécanique que le
   prep HD), ou attendre un modèle HD. Ne PAS promettre avant l'évaluation.

## MÉCANISME PRESSENTI (réutilise l'infra existante, ne réinvente pas)
- Les companions HD ont déjà la main sur chaque os À CHAQUE FRAME après le retarget (do-joint-math!) :
  c'est exactement l'endroit canonique du secondary motion. Une chaîne ressort/verlet par zone
  (ancre = l'os parent animé ; les enfants suivent avec inertie/amortissement/limites d'angle).
- Si le donor n'a pas d'os dédiés (poitrine) : le pipeline de prep FABRIQUE déjà les squelettes →
  injecter des os de physique + poids au prep (comme l'align), les exclure de la table k→e (pilotés
  par la sim, pas par le driver).
- Paramètres par chaîne (raideur, amortissement, masse, limites) dans un fichier de données, pas en
  dur — pour itérer vite au verdict de l'owner.
- Gate : FLAG dédié ou sous le toggle enhanced-models ; comme toujours, assets ND = pack externe.

## RÈGLES
- PRÉREQUIS : hd-models4 (cycle défauts) accepté par l'owner ; barbe de Samos réparée avant sa physique.
- Preuves : state dumps des chaînes (positions/vitesses bornées, retour au repos, pas de NaN/explosion)
  + compteurs — PAS de campagnes de captures (règle permanente). L'owner juge le rendu en jouant.
- « Rien de fou » : subtil, crédible, cohérent avec l'esprit du jeu.
