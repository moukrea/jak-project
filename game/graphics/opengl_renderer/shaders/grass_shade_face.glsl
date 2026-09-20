// grass-shading (SPEC-refonte-herbe.md, section 7) — LA FACE ECLAIREE ET LA FACE OPPOSEE.
//
// « une differenciation face eclairee / face opposee par la normale du brin dans le plan ».
// Un brin est un ruban : son plan est tendu par son axe de largeur et la verticale, donc sa
// NORMALE est sa direction d'avancee horizontale (`fwdv.xz`, le meme lacet qui porte sa courbure
// et son vent). Les deux faces du MEME ruban recoivent donc des eclairements opposes, et c'est
// `gl_FrontFacing` — la seule grandeur qui distingue les deux cotes d'un triangle — qui choisit.
// Sans ce terme, un brin est un aplat quel que soit l'angle sous lequel on le regarde.
//
// LE CAP DU SOLEIL EST UNE CONSTANTE STYLISEE, PAS UNE DIRECTION DE JEU. La lumiere cuite
// (`gs_light`) porte deja l'heure du jour par LIEU ; ce terme-ci ne fait que separer les deux
// faces d'un meme brin, avec une amplitude bornee et declaree. Direction artistique : stylise,
// pas photorealiste (SPEC section 7, derniere ligne).
//
// MEME TEXTE POUR LES DEUX COMPILATEURS (voir l'en-tete de `grass_shade.glsl`) : le pilote GLSL le
// splice dans `grass.frag`, le C++ l'inclut dans `grass_bake::shading_census()` derriere
// `common/util/glsl_compat.h`. La porte mesure donc l'ecart que le pixel recoit, pas une copie.
//
// CONTRAT D'ENTREE (a declarer AVANT le #include) :
//   vec2  gs_fwd_xz  direction d'avancee horizontale du brin (cos/sin de son lacet), unitaire
//   float gs_side    +1 pour la face avant (gl_FrontFacing), -1 pour la face opposee
// SORTIES (a declarer AVANT le #include) :
//   float gs_face_dot  le produit scalaire brut, -1..1 — c'est lui que le recensement publie
//   float gs_face_mul  le facteur multiplicatif a appliquer a la couleur

const vec2 GRASS_SUN_XZ = vec2(0.6, 0.8);  // cap stylise du soleil, projete au sol (unitaire)
const float GRASS_FACE_AMP = 0.22;         // AMPLITUDE DECLAREE : l'ecart entre les deux faces
                                           // d'un meme brin vaut au plus 2*AMP = 44 % de sa
                                           // luminance. Au-dela, la porte compte un defaut.
gs_face_dot = dot(gs_fwd_xz, GRASS_SUN_XZ);
gs_face_mul = 1.0 + GRASS_FACE_AMP * gs_side * gs_face_dot;
