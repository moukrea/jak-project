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
4. **Cheveux longs, tous personnages concernés** : Keira, Samos, Jak, le méchant (Gol) — FERME,
   pas de discussion par personnage (owner 2026-08-04 : « c'était juste une façon de dire — non,
   on le fait puis c'est tout ! »).
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
- **GATING (owner, obligatoire)** : feature flag de build dédié `--physics` (FLAG_PHYSICS, généré
  par build.sh comme les autres, fan-out flag-universe complet) **ET** exposition menu :
  (a) **toggle ON/OFF complet** dans les menus (désactivation totale possible in-game) ;
  (b) **sélecteur de PRÉCISION à plusieurs degrés** — SÉMANTIQUE PRÉCISÉE PAR L'OWNER (2026-08-04) :
  une échelle coût↔qualité MONOTONE : « au plus bas ça coûte peu ; au max ça coûte beaucoup plus
  mais c'est plus précis, cohérent, etc. — peut-être avec de la vraie simulation de physique ».
  DEUX BORNES NON NÉGOCIABLES :
    - le niveau LE PLUS BAS reste CRÉDIBLE et cohérent (une approximation légère et propre —
      jamais un truc pourri « pour que ça tourne ») ;
    - le niveau LE PLUS HAUT est LE MEILLEUR RÉALISABLE, pensé pour le bon matériel, JAMAIS bridé
      par les contraintes du bas de l'échelle : vraie simulation (pas de temps fin / substeps —
      « pas » au sens TIME STEP —, collisions chaîne-corps, limites angulaires, plus de chaînes
      actives, itérations de contrainte plus nombreuses…).
  Les leviers par niveau (fréquence/substeps de la sim, nombre de chaînes actives, itérations,
  collisions on/off) sont des DONNÉES réglables, pas du code en dur. L'owner ne maîtrise pas le
  domaine et l'assume : c'est au worker de proposer une échelle honnête et à l'owner de juger le
  rendu à chaque niveau. Persistance via *pc-settings* comme les autres réglages. Comme toujours, assets ND =
  pack externe.

## RÈGLES
- PRÉREQUIS : hd-models4 (cycle défauts) accepté par l'owner ; barbe de Samos réparée avant sa physique.
- Preuves : state dumps des chaînes (positions/vitesses bornées, retour au repos, pas de NaN/explosion)
  + compteurs — PAS de campagnes de captures (règle permanente). L'owner juge le rendu en jouant.
- « Rien de fou » : subtil, crédible, cohérent avec l'esprit du jeu.

## EXTENSION OWNER 2026-08-05 ~11:55 — « on ne laisse RIEN sous le tapis ! »
Le périmètre s'élargit, FERME :
1. **ACCESSOIRES** aussi : les lunettes de Keira (sur sa tête), le bun/chignon de Samos (sa bûche),
   et tout accessoire équivalent qui bougerait naturellement (lunettes de Jak sur son front, sacoches,
   pendentifs…) — même mécanique de chaînes, subtilité de mise.
2. **TOUTES LES VARIANTES DE LOOK** : la physique s'applique à CHAQUE look du carousel (primaires ET
   bonus — le Jak J2, le J3 masqué ou non, Keira J3, Daxter pantalon, Young Samos…), pas seulement
   aux looks par défaut. Les paramètres de chaînes sont par-modèle (data-driven), donc chaque variante
   reçoit ses chaînes propres (cheveux différents, accessoires différents).
3. **TOUS LES PNJ à cheveux longs (et compagnie) — Y COMPRIS MAIA** : l'étude de faisabilité
   Maia/archéologue passe de « évaluer sans promettre » à « DANS LE PÉRIMÈTRE » : pour les
   personnages SANS modèle HD, la voie = injection d'os de physique + poids sur le modèle STOCK
   (le pipeline de prep sait déjà fabriquer/injecter des os — même mécanique que l'align). Recenser
   les PNJ concernés (cheveux longs, barbes, accessoires pendants) et les traiter. Si un cas précis
   s'avère réellement impossible, le documenter avec preuve — pas d'abandon silencieux de catégorie.
