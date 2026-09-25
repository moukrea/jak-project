#version 410 core

#ifdef OG_FLIP_PROBE
layout(location = 0) out vec4 color;
uniform int u_floor_probe;
layout(location = 4) out vec4 floor_probe_out;
#else
out vec4 color;
#endif

in vec4 fragment_color;
in vec3 tex_coord;
uniform float color_mult;
uniform float alpha_mult;

uniform vec4 fog_color;
uniform int bucket;

in float fog;

uniform sampler2D tex_T0;

// lighting-ao-indirect (SPEC-refonte-lumiere §4.7 « Eau : ombree comme le reste ») : l'AO
// d'ecran, estimee sur la profondeur de la prepasse (le decor opaque SOUS et AUTOUR de l'eau,
// jamais l'eau elle-meme), multiplie la base cuite de l'eau et sa reflexion d'environnement —
// les deux termes ambiants de ce shader, qui n'a pas de terme direct. Meme unite (8), memes
// uniformes et meme loi que shade.glsl : sao appliquee en LINEAIRE sur une base encodee gamma.
// OFF (u_screen_ao_on == 0) : ao_mul == 1.0 exactement, l'image d'origine est bit-identique.
// L'ocean lointain (bucket 4) precede la prepasse : il ne recoit rien, seul l'ocean proche
// (bucket 63) est ombre.
uniform sampler2D tex_screen_ao;
uniform int u_screen_ao_on;
uniform vec2 u_screen_ao_inv_size;

void main() {
#ifdef OG_FLIP_PROBE
  floor_probe_out = vec4(0.0);
#endif
  vec4 T0 = texture(tex_T0, tex_coord.xy / tex_coord.z);
  float ao_mul = 1.0;
  if (u_screen_ao_on != 0) {
    float sao = clamp(texture(tex_screen_ao, gl_FragCoord.xy * u_screen_ao_inv_size).r, 0.0, 1.0);
    ao_mul = (sao >= 1.0) ? 1.0 : pow(max(sao, 0.0), 1.0 / 2.2);
  }
#ifdef OG_FLIP_PROBE
  // lighting-flipped-faces-everywhere : aucune normale n'entre dans l'ombrage de l'ocean ; la
  // reference est le fragment AVANT AO, le rendu est le meme APRES AO (avant brouillard).
  float fc_ref = dot(fragment_color.rgb * T0.rgb, vec3(0.299, 0.587, 0.114));
#endif
  if (bucket == 0) {
    color.rgb = fragment_color.rgb * T0.rgb * ao_mul;
    color.a = fragment_color.a;
#ifdef OG_FLIP_PROBE
    if (u_floor_probe >= 2) {
      float fc_on = dot(color.rgb, vec3(0.299, 0.587, 0.114));
      floor_probe_out = vec4(fc_on / max(fc_ref, 1e-4), fc_on / max(fc_ref, 1e-4), fc_ref,
                             1.0 + 4.0 * float(u_floor_probe));
    }
#endif
    color.rgb = mix(color.rgb, fog_color.rgb, clamp(fog_color.a * fog, 0.0, 1.0));
  } else if (bucket == 1 || bucket == 2 || bucket == 4) {
    color = fragment_color * T0;
    color.rgb *= ao_mul;
#ifdef OG_FLIP_PROBE
    if (u_floor_probe >= 2) {
      float fc_on = dot(color.rgb, vec3(0.299, 0.587, 0.114));
      floor_probe_out = vec4(fc_on / max(fc_ref, 1e-4), fc_on / max(fc_ref, 1e-4), fc_ref,
                             1.0 + 4.0 * float(u_floor_probe));
    }
#endif
  } else if (bucket == 3) {
    color = fragment_color * T0;
    color.rgb *= ao_mul;
#ifdef OG_FLIP_PROBE
    if (u_floor_probe >= 2) {
      float fc_on = dot(color.rgb, vec3(0.299, 0.587, 0.114));
      floor_probe_out = vec4(fc_on / max(fc_ref, 1e-4), fc_on / max(fc_ref, 1e-4), fc_ref,
                             1.0 + 4.0 * float(u_floor_probe));
    }
#endif
    color.rgb = mix(color.rgb, fog_color.rgb, clamp(fog_color.a * fog, 0.0, 1.0));
  }

  // Alpha is a blend weight, even when RGB has floating-point HDR headroom.
  // Keep the original alpha tests above, then match the normalized target range.
  color.a = clamp(color.a, 0.0, 1.0);
}
