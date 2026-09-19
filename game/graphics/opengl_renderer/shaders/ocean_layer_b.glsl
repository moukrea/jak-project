// water-ocean-mesh (reprise du 19/09, SPEC-refonte-eau §5.2 couche B) — LES ONDES QUI S'AJOUTENT
// A LA HOULE CUITE.
//
// POURQUOI. La couche A est la table 32 x 32 de Naughty Dog : une seule periode de 96 m, relue
// par le gameplay, donc INTOUCHABLE. Elle ne porte qu'une ondulation tres longue. La SPEC confie
// le detail a une couche B : « 4 a 8 ondes de Gerstner de faible amplitude ». C'est ce chunk.
//
// VERTICALES SEULES. Une vraie Gerstner deplace aussi le sommet en XZ ; ici cela ferait sortir la
// surface de son masque de plan d'eau, cellule par cellule, et rouvrirait exactement le refus du
// 10/09. On garde la forme de crete (crete resserree, creux aplati) sans le deplacement
// horizontal : `s * 0.75 + 0.25 * s * |s|`, qui vaut +-1 aux extremes donc n'ajoute pas un
// millimetre a l'amplitude annoncee.
//
// L'ANTI-REPLIEMENT EST DANS LA FONCTION. Les trois anneaux de la clipmap echantillonnent a
// 0,75 m, 3 m et 36 m. Une onde de 2,5 m dessinee au pas de 36 m ne se replie pas en bruit : elle
// s'eteint, par un fondu sur le rapport longueur d'onde / pas. C'est pourquoi le pas de l'anneau
// est un ARGUMENT et non une constante — la sonde de houle passe le pas de l'anneau qui dessine
// vraiment le point qu'elle mesure.
//
// LES AMPLITUDES ET LES LONGUEURS SONT CELLES DE LA SPEC (§5.2) : « 2..8 ondes de Gerstner,
// lambda 6 a 30 m, somme des amplitudes <= 0,25 m au large ». Six ondes, 75 / 55 / 42 / 30 / 20 /
// 15 mm, somme 237 mm ; longueurs 7 / 11 / 6,5 / 17 / 9 / 29 m. 1 m = 4096 unites GOAL. La
// pulsation suit la dispersion en eau profonde w = sqrt(g k) : deux ondes de longueurs
// differentes ne defilent pas a la meme vitesse, sans quoi la somme garde une periode visible.

const int OCEAN_B_WAVE_COUNT = 6;

float ocean_layer_b(vec2 world_xz, float t, float ring_step) {
  // x = amplitude (m), y = longueur d'onde (m), zw = direction unitaire
  const vec4 kB[6] = vec4[6](vec4(0.075, 7.0, 0.92388, 0.38268),
                             vec4(0.055, 11.0, 0.38268, 0.92388),
                             vec4(0.042, 6.5, -0.70711, 0.70711),
                             vec4(0.030, 17.0, 0.98079, -0.19509),
                             vec4(0.020, 9.0, 0.19509, 0.98079),
                             vec4(0.015, 29.0, -0.50000, -0.86603));
  float h = 0.0;
  for (int i = 0; i < OCEAN_B_WAVE_COUNT; i++) {
    float lambda_m = kB[i].y;
    float lambda = lambda_m * 4096.0;
    // Moins de quatre sommets par longueur d'onde : l'onde n'est plus resolvable par cet anneau.
    float fade = clamp(lambda / (4.0 * ring_step) - 1.0, 0.0, 1.0);
    if (fade <= 0.0) {
      continue;
    }
    float k = 6.28318531 / lambda;
    float w = sqrt(9.81 * 6.28318531 / lambda_m);  // rad/s, dispersion en eau profonde
    float s = sin(dot(vec2(kB[i].z, kB[i].w), world_xz) * k + t * w);
    h += kB[i].x * 4096.0 * fade * (s * 0.75 + 0.25 * s * abs(s));
  }
  return h;
}
