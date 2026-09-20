// ================================ LE CHAMP DE VENT DE L'HERBE ================================
// SPEC refonte-herbe, section 8.
//
// CE TEXTE EST LU PAR DEUX COMPILATEURS. Le pilote GLSL le splice dans `grass.vert`
// (Shader.cpp), et le C++ l'`#include` dans une portee qui declare son contrat
// (GrassBakeCore.cpp). L'outil hors ligne qui MESURE le vent mesure donc le texte que le
// pilote compile, pas une copie libre de deriver — c'est le montage de `grass_shade.glsl`.
// `breeze.glsl` et son jumeau C++ `breeze_offset()` sont, eux, DEUX textes tenus a la main :
// c'est le regime inferieur, et on ne le reproduit pas.
//
// Contraintes d'ecriture : pas de swizzle (`.x/.y/.z` seulement), pas de `const`, aucune
// declaration de fonction, rien qui ne soit dans common/util/glsl_compat.h.
//
// CONTRAT D'ENTREE (a declarer dans la portee appelante AVANT le #include) :
//   vec3  gw_base   position monde de la RACINE du brin, unites GOAL (4096 = 1 m)
//   float gw_time   secondes
//   float gw_phase  aleatoire par brin, 0..1
//   float gw_yaw    lacet du brin, radians (ne sert QUE au regime remplace)
//   float gw_on     1 = loi de cet item ; 0 = LA LOI REMPLACEE, rejouee a l'identique
// SORTIES (declarees par l'appelant, ecrites ici) :
//   float gw_w0     deflexion normalisee du champ a la RACINE
//   float gw_w1     deflexion normalisee vue par la POINTE : LE MEME champ, RETARDE
//   float gw_dx     cap du deplacement de CE brin, composante x (unitaire)
//   float gw_dz     cap du deplacement de CE brin, composante z (unitaire)
//   float gw_amp    facteur d'amplitude du regime courant
// L'appelant compose : deplacement = mix(gw_w0, gw_w1, u) * u*u * gw_amp * H, le long de
// (gw_dx, 0, gw_dz), ou u va de 0 a la racine a 1 a la pointe.
//
// POURQUOI LE REGIME REMPLACE VIT ICI. Le bras d'ablation du shader et le bras « avant » de
// la mesure lisent alors LE MEME TEXTE : personne ne mesure une recopie de l'ancien code, et
// `gw_on = 0` rend, au bit pres, ce que `grass.vert` faisait avant cet item.
//
// POURQUOI DEUX ANCRES DE TEMPS, ET PAS UNE AMPLITUDE PLUS GRANDE. Un brin SE COURBE, il ne
// pivote pas. On evalue le meme champ a `gw_time` et a `gw_time - 0,21 s`, et l'appelant
// interpole le long de la tige : la pointe joue l'onde de la racine EN RETARD. A un instant
// donne, la forme du brin n'est donc pas l'homothetie d'une flexion unique — c'est la
// grandeur qui separe cette loi de celle que l'owner a refusee deux fois sur le feuillage.
// Cout : deux sin(vec3) + deux sin scalaires par sommet, l'ordre de grandeur de l'ancien.

  // ---- (0) LE REGIME REMPLACE. UN sinus, flexion le long du lacet ALEATOIRE du brin. ----
  // C'est exactement l'ancienne ligne de grass.vert : un seul sinus a 1,7 rad/s, une phase
  // par brin qui balaie tout le cercle, et une composante spatiale a 45 deg figes. Aucun cap,
  // aucune rafale, aucun retard : la pointe et la racine jouent la meme onde au meme instant.
  float gw_old = sin(gw_time * 1.7 + gw_phase * 6.2831853
                     + (gw_base.x + gw_base.z) * 0.00035);

  // ---- (1) LE CAP. UN SEUL pour tout le champ, et il derive lentement. ------------------
  // Deux composantes lentes, ~170 s et ~570 s : l'herbe d'un bout a l'autre de la zone se
  // couche dans la meme direction, qui tourne sans qu'on voie jamais l'instant ou.
  float gw_head = 0.70 + 0.45 * (0.70 * sin(gw_time * 0.037)
                               + 0.30 * sin(gw_time * 0.011 + 1.70));

  // ---- (2) LA PROJECTION : elle fait VOYAGER l'onde, sur un axe FIXE. ------------------
  // L'AXE DE VOYAGE NE TOURNE PAS, ET CE N'EST PAS UN DETAIL DE GOUT. Projeter la position sur
  // un cap QUI TOURNE fait balayer la phase spatiale a une vitesse PROPORTIONNELLE A LA
  // DISTANCE A L'ORIGINE DU MONDE : a 200 m, une derive de cap de 0,013 rad/s deplace deja la
  // projection de 2,6 m/s, ce qui ajoute plusieurs rad/s aux bandes et fait SCINTILLER la
  // pointe — d'autant plus loin qu'on s'eloigne de l'origine. Mesure : le pas image a image
  // passait a 0,23 hauteur de brin, pour un plafond de 0,06. L'onde voyage donc le long du cap
  // MOYEN ; seul le cap du DEPLACEMENT derive, et lui ne multiplie aucune coordonnee.
  float gw_s = (gw_base.x * sin(0.70) + gw_base.z * cos(0.70)) * 0.000244140625;   // metres

  // ---- (3) LA PHASE DE TOUFFE, PAR L'ESPACE. -------------------------------------------
  // La donnee d'instance ne porte AUCUN identifiant de touffe (GrassInstance : 16 flottants,
  // tous pris). La coherence vient donc de la POSITION : trois ondes obliques de ~2,5 m,
  // incommensurables, font un champ de phase lisse. Deux brins d'une meme touffe (~0,3 m
  // d'ecart) y lisent presque la meme valeur — ils bougent ENSEMBLE ; deux touffes voisines
  // (~1,2 m) en lisent des valeurs differentes — elles ne bougent PAS PAREIL. Le dernier
  // terme, minuscule, est le grain par brin : dans une touffe, personne n'est un clone.
  float gw_px = gw_base.x * 0.000244140625;
  float gw_pz = gw_base.z * 0.000244140625;
  vec3 gw_n = sin(vec3(2.31, -1.28, 0.78) * gw_px
                + vec3(0.86, 1.97, -2.44) * gw_pz
                + vec3(0.0, 2.10, 4.30));
  float gw_ph = 0.84 * gw_n.x + 0.756 * gw_n.y + 0.672 * gw_n.z
              + 0.36 * (gw_phase - 0.5);

  // ---- (4) LES DEUX ANCRES DE TEMPS. ---------------------------------------------------
  // TOUT le champ est retarde pour la pointe, LA RAFALE COMPRISE. Une bourrasque atteint la
  // pointe APRES la racine : c'est la meme verite physique que le retard des bandes. Laisser
  // l'enveloppe de rafale commune aux deux ancres remettait un facteur multiplicatif IDENTIQUE
  // a decalage nul dans les deux series, et la correlation croisee qui mesure le retard
  // s'effondrait dessus : 11,8 ms mesures pour 147 attendus. Le defaut etait dans la loi.
  float gw_t0 = gw_time;
  float gw_t1 = gw_time - 0.21;

  // ---- (5) LE FRONT DE RAFALE. ---------------------------------------------------------
  // Une BANDE qui traverse le champ le long de l'axe de voyage. Le cube fait un FRONT, pas une
  // sinusoide : long calme, bourrasque breve. ~62 m a ~9 m/s = une rafale toutes les 6,9 s.
  float gw_g0 = 0.5 + 0.5 * sin((gw_s - gw_t0 * 9.0) * 0.1013);
  float gw_g1 = 0.5 + 0.5 * sin((gw_s - gw_t1 * 9.0) * 0.1013);
  float gw_e0 = 0.50 + 0.95 * (gw_g0 * gw_g0 * gw_g0);
  float gw_e1 = 0.50 + 0.95 * (gw_g1 * gw_g1 * gw_g1);

  // ---- (6) TROIS BANDES DE FREQUENCE. --------------------------------------------------
  // 0,088 Hz la houle, 0,271 Hz l'ondulation (l'ANCIENNE frequence : ce qui marchait deja
  // n'est pas jete), 0,668 Hz le frisson. Longueurs d'onde 18 m / 4,4 m / 2,4 m.
  vec3 gw_k = vec3(0.35, 1.43, 2.60);
  vec3 gw_w = vec3(0.55, 1.70, 4.20);
  vec3 gw_a0 = sin(gw_k * gw_s - gw_w * gw_t0 + vec3(gw_ph));
  vec3 gw_a1 = sin(gw_k * gw_s - gw_w * gw_t1 + vec3(gw_ph));
  float gw_n0 = (0.62 * gw_a0.x + 0.30 * gw_a0.y + 0.06 * gw_a0.z) * gw_e0;
  float gw_n1 = (0.62 * gw_a1.x + 0.30 * gw_a1.y + 0.06 * gw_a1.z) * gw_e1;

  // ---- (7) LE CAP DE CE BRIN : le cap commun, plus +/- 12 deg. -------------------------
  // Un champ ou tous les brins partent EXACTEMENT du meme angle est un peigne, pas une
  // prairie. La deviation est assez petite pour que la dispersion angulaire du champ
  // s'effondre quand meme, assez grande pour qu'aucune ligne droite ne se lise.
  float gw_hb = gw_head + 0.42 * (gw_phase - 0.5);

  // ---- (8) LE CHOIX DU REGIME. ---------------------------------------------------------
  gw_w0 = mix(gw_old, gw_n0, gw_on);
  gw_w1 = mix(gw_old, gw_n1, gw_on);
  gw_dx = mix(sin(gw_yaw), sin(gw_hb), gw_on);
  gw_dz = mix(cos(gw_yaw), cos(gw_hb), gw_on);
  gw_amp = mix(0.38, 0.55, gw_on);
