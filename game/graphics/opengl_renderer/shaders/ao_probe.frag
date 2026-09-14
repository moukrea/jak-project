#version 410 core

// lighting-ao-indirect, essai 9 : LA PRIMITIVE PORTABLE DE LA PREUVE.
//
// GLES 3.2 refuse `glReadPixels(GL_DEPTH_COMPONENT, GL_FLOAT)` et `glReadPixels(GL_STENCIL_INDEX)`.
// Cinq des sept termes de `ao_owner_defects` en vivaient : sur l'appareil ils se publiaient
// « non-mesure », c'est-a-dire un defaut nomme. Ce programme les rend mesurables partout, sans
// changer une seule grandeur : il RE-ENCODE ce que le pilote sait deja rendre.
//
//   mode 1 : la profondeur 24 bits de `u_depth`, octet de poids fort dans R. Le tampon se relit
//            par `glReadPixels(GL_RGBA, GL_UNSIGNED_BYTE)`, garanti en GLES 3.2 sur un RGBA8.
//            L'arithmetique est ENTIERE (floor sur des valeurs <= 2^24, exactes en highp) : le
//            deballage rend BIT POUR BIT la valeur du tampon de profondeur, ce que le temoin
//            `ao_depth_export_maxq` verifie sur bureau contre la relecture native.
//   mode 0 : les drapeaux de `shade()` (R = fuite sur le direct, G = l'indirect a recu l'AO,
//            B = chemin exclu) seuillees a 0/255, et la FAMILLE du quad courant dans l'alpha.
//            C'est le test de STENCIL qui choisit les pixels, pas une relecture de stencil.
precision highp float;

in vec2 tex_coord;
out vec4 color;

uniform highp sampler2D u_depth;  // mode 1 : la profondeur a empaqueter
uniform sampler2D u_src;          // mode 0 : la couleur de la sonde
uniform int u_mode;
uniform float u_fam;  // mode 0 : la famille du quad courant (1 = TFRAG, 2 = TIE, 3 = SHRUB)

void main() {
  if (u_mode == 0) {
    vec3 f = texture(u_src, tex_coord).rgb;
    color = vec4(step(0.5, f), u_fam / 255.0);
  } else {
    float d = clamp(texture(u_depth, tex_coord).r, 0.0, 1.0);
    float v = floor(d * 16777215.0 + 0.5);
    float b2 = floor(v / 65536.0);
    float r1 = v - b2 * 65536.0;
    float b1 = floor(r1 / 256.0);
    color = vec4(b2 / 255.0, b1 / 255.0, (r1 - b1 * 256.0) / 255.0, 1.0);
  }
}
