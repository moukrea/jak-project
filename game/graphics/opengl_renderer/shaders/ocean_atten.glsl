// water-ocean-mesh (verdict C du 17/09) — L'ATTENUATION DE HOULE DE NAUGHTY DOG, EN UN SEUL
// EXEMPLAIRE.
//
// POURQUOI CE CHUNK EXISTE. Meme raison que `ocean_layer_a.glsl` : la clipmap DEPLACE ses
// sommets avec cette loi, et la sonde de houle MESURE l'amplitude que cette loi laisse a la
// surface livree. Deux transcriptions independantes deriveraient, et la grandeur publiee
// cesserait de decrire ce que l'owner voit sans que rien ne rougisse. Un seul texte, deux
// lecteurs : `ocean_recharged.vert` (ce qui est DESSINE) et `ocean_wave.frag` (ce qui est
// MESURE).
//
// LA SOURCE, mot pour mot. `run_L15_vu2c` transforme le sommet PORTANT SA HAUTEUR par la matrice
// de l'ocean near (vf08..vf11) puis prend `eleng.xyz` du resultat (OceanNear_PS2.cpp:1181-1216) :
// la rotation de cette matrice est celle de la camera, donc orthonormale, et la longueur en
// espace camera EST la distance monde de la camera au sommet. Puis
//   `mulw.w  vf22, vf20, vf05.w`   t = d * constants.w
//   `miniw.w vf22, vf22, vf00.w`   t = min(t, 1)
//   `subw.w  vf28, vf00, vf22.w`   f = 1 - t
//   `mulw.y  vf28, vf28, vf28.w`   y = A * f
// (OceanNear_PS2.cpp:1224-1250). La constante est `(-> arg0 constants)` w, posee a 0.000010172526
// par `ocean-near-setup-constants` (ocean-near.gc:34) : 1/98304, soit 1/24 m en unites GOAL.
// Au-dela de 24 m de la camera, l'ocean de Naughty Dog est PLAT.

float ocean_nd_dist(vec3 vert_world, vec3 cam) {
  return length(vert_world - cam);
}

float ocean_nd_atten(float d) {
  return 1.0 - min(d * 0.000010172526, 1.0);
}
