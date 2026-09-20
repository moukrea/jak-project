// grass-shading (SPEC-refonte-herbe.md, section 7) — LE MODELE DE COULEUR DE L'HERBE,
// EN UN SEUL TEXTE.
//
// POURQUOI CE FICHIER EXISTE. La porte de l'item doit publier l'ecart de luminance entre la
// RACINE et la POINTE d'un meme brin, et entre sa face eclairee et sa face opposee. Ces deux
// grandeurs naissent dans le shader. Les recalculer en C++ pour les mesurer aurait produit un
// MIROIR : deux textes libres de diverger, dont la porte n'aurait mesure que la copie. Ce bloc
// est donc compile DEUX FOIS, a partir du MEME fichier —
//   * par le pilote GLSL, spliced dans `grass.vert` par expand_includes() (et dans le blob GLES
//     d'Android, ou `to_gles_chunk()` le recopie OCTET POUR OCTET — verifie, pas suppose : ses deux
//     seules transformations ne mordent sur rien ici. Attention, elles sont AVEUGLES aux
//     commentaires : ecrire le nom du qualificateur d'interpolation non perspective dans ce
//     bandeau suffisait a faire diverger le blob de ce fichier, et donc l'empreinte publiee par le
//     moteur de celle que la porte calcule) ;
//   * par le compilateur C++, inclus dans `grass_bake::shading_census()` derriere
//     `common/util/glsl_compat.h`, qui fournit `vec3`, `mix`, `clamp`, `dot`, `fract`, `max`.
// Le moteur publie l'empreinte FNV-1a du texte qu'il a REELLEMENT splice ; le recensement
// calcule la sienne sur ce fichier. Un blob GLES perime ou une divergence d'un octet devient un
// defaut compte, pas une surprise a l'ecran.
//
// CONTRAT D'ENTREE (a declarer dans la portee appelante, AVANT le #include) :
//   float gs_t      hauteur locale le long du brin : 0 = racine, 1 = pointe
//   float gs_tint   aleatoire par brin, 0..1
//   vec3  gs_gcol   couleur de sol de la TOUFFE (teintee au bake ; jadis une constante de draw)
//   vec3  gs_light  lumiere cuite servie a ce brin, 0..1 (jadis par triangle, desormais par touffe)
//   bool  gs_card   vrai pour une carte texturee zone-3 (sa couleur vient de ses texels)
//   bool  gs_pal_on   vrai quand l'item grass-blade-variants est arme pour ce brin
//   vec3  gs_pal_root couleur de l'espece a la RACINE (ou au bord gauche si l'axe est transversal)
//   vec3  gs_pal_tip  couleur de l'espece a la POINTE (ou au bord droit)
//   float gs_pal_axis 0 = degrade le long du brin ; 1 = degrade EN TRAVERS du brin
//   float gs_pal_rim  liseret de bord (0 = aucun)
//   float gs_across   position EN TRAVERS du brin : -1 bord gauche, +1 bord droit
//   float gs_across_k force de la modulation en travers, DONNEE DU PROFIL DE BIOME
//   float gs_jit_r    dispersion de teinte par brin, canal rouge (idem : donnee du profil)
//   float gs_jit_b    dispersion de teinte par brin, canal bleu
// SORTIE : `col`, declaree par l'appelant.
//
// Ecrit sans swizzle de couleur (`.x/.y/.z`, jamais `.r/.g/.b`) et sans constructeur implicite :
// c'est le sous-ensemble que les deux compilateurs acceptent a l'identique.

// --- flat color: vertical gradient (dark base -> bright tip) + per-blade tint ---
// OWNER POLISH: more tint variation (wider brightness + a hue jitter so some
// blades are warmer / cooler green).
float tint2 = fract(gs_tint * 7.919 + 0.371);  // decorrelated secondary random
// grass-blade-variants — LA PALETTE EST CELLE DU LIEU (grass_biome_profile.h, SPEC section 18) ;
// l'espece n'en porte qu'un ECART. Desarme, les deux constantes d'avant reviennent : le brin livre
// jusqu'ici est rendu au bit pres.
vec3 base_dark = vec3(0.075, 0.185, 0.040);
vec3 base_light = vec3(0.40, 0.66, 0.20);
if (gs_pal_on) {
  base_dark = gs_pal_root;
  base_light = gs_pal_tip;
}
// LE DEGRADE RACINE->POINTE EXISTE SUR LES SIX ESPECES. Owner, 20/09 20:40 : « aucune impression
// de reliefs sur la plupart ». La cause etait ici : ce site choisissait UN SEUL axe, donc les trois
// especes a axe transversal n'avaient AUCUN degrade le long du brin — mesure sur les sommets emis,
// 0,0 % d'amplitude de luminance, pour 300 brins sur 1000. L'axe transversal devient une
// modulation QUI S'AJOUTE (ci-dessous), il ne remplace plus rien.
col = mix(base_dark, base_light, gs_t);
// LE VOLUME. `gs_across` va de -1 (bord gauche) a +1 (bord droit) : assombrir un bord donne au brin
// plat l'ombre d'un cylindre. C'est le « de gauche a droite » du 20/09 13:45, et c'est ce qui se
// lit comme du relief. La force vient du profil du lieu, pas d'une constante compilee.
if (gs_pal_on && gs_pal_axis > 0.0) {
  float gs_side = gs_across * 0.5 + 0.5;
  col = col * (1.0 - gs_pal_axis * gs_across_k * (1.0 - gs_side));
}
// LISERET DE BORD : une espece (le jonc) porte un bord clair, une autre un liseret discret. C'est
// la troisieme direction de degrade que l'owner a nommee, et elle ne coute aucun sommet.
if (gs_pal_on && gs_pal_rim > 0.0) {
  // Pas `abs` : libc++ (clang/arm64) en declare deja un pour `float`, et l'appel devient ambigu
  // des que ce texte est compile en C++. Le ternaire est le seul sous-ensemble que les DEUX
  // compilateurs lisent pareil — la meme discipline que le reste du chunk.
  float ea = gs_across < 0.0 ? -gs_across : gs_across;
  float ee = clamp((ea - 0.55) / 0.45, 0.0, 1.0);
  ee = ee * ee * (3.0 - 2.0 * ee);
  col = col * (1.0 + 1.10 * gs_pal_rim * ee);
}
col = col * (0.62 + 0.72 * gs_tint);  // wider brightness variation per blade
// La dispersion de teinte par brin est une DONNEE DU LIEU. A 0,50/0,35, ecrits en dur ici, elle
// sortait 3,17 % des sommets de la coque de teinte du biome a elle seule — des especes bien placees
// n'y pouvaient rien. Desarme, les deux valeurs d'avant reviennent.
float hue = tint2 - 0.5;                 // -0.5 .. 0.5
col.x = col.x * (1.0 + gs_jit_r * hue);  // warmer <-> cooler green
col.z = col.z * (1.0 - gs_jit_b * hue);
col.y = col.y * (0.88 + 0.22 * gs_tint);

// OWNER POLISH#4: sample/match the GROUND TEXTURE colour. gs_gcol is the ground tone carried by
// this blade's instance. grass-shading (2026-09-20): it is no longer the average of the ENTIRE
// source draw texture — the bake multiplies it by a tint drawn from the TUFT's own seed and
// darkens it with the tuft's local density, so two neighbouring tufts over the same texture no
// longer share one flat colour. Shift the canonical grass-green toward that ground tone and let a
// little of the literal ground colour bleed in, so the grass never clashes with the texture
// showing through (a bright green blade over sandy/mossy ground would "faire tache").
vec3 gcol = gs_gcol;
vec3 groundRef = vec3(0.24, 0.34, 0.14);  // a canonical grassy-ground average
vec3 harmon = col * clamp(gcol / max(groundRef, vec3(0.04)), vec3(0.55), vec3(1.9));
col = mix(col, harmon, 0.55);  // shift the green toward the ground's tone
col = mix(col, gcol, 0.16);    // a touch of the literal ground colour blends in

// OWNER POLISH#7: match the grass LUMINANCE to the ground albedo so blades are not brighter than
// the ground they grow from (owner: grass "bien plus lumineuse que la texture du sol de partout,
// même aux endroits les plus éclairés"). Pull the grass brightness toward the ground-texture
// brightness while keeping some per-blade variation (hue is preserved — only magnitude is scaled).
float glum = dot(col, vec3(0.299, 0.587, 0.114));
float grlum = dot(gcol, vec3(0.299, 0.587, 0.114));
if (glum > 0.001) {
  float lm = clamp(grlum / glum, 0.45, 1.15);
  col = col * mix(1.0, lm, 0.6);
}

// OWNER POLISH#9 (#1 owner priority): apply the GROUND's ACTUAL baked light — per-channel +
// DYNAMIC. gs_light is the baked colour served to this blade at the CURRENT time of day
// (normalized [0,1]; re-uploaded by update_light() as the day/night cycle advances). *2.0 recovers
// the EXACT factor tfrag/TIE multiply the ground texture by (fragment_color = (palette/255)*2), so
// the grass darkens/brightens EXACTLY like the ground beneath it. grass-shading (2026-09-20): that
// value is now interpolated at the TUFT's barycentric position inside its triangle instead of
// being the triangle centroid's, so the baked light varies WITHIN a triangle.
// ROUND 11: a textured card's colour comes from its TEXELS — v_color carries only the ground's
// dynamic baked light, sampled from the owning WALKABLE lawn tri => brightness-continuous across
// the lip, per time of day.
if (gs_card) {
  col = vec3(1.0);
}
col = col * (gs_light * 2.0);
col = clamp(col, vec3(0.0), vec3(1.5));
