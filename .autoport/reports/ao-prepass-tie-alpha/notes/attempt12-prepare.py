from pathlib import Path
n=Path(__file__).resolve().parent
s=(n/'attempt11-reference.frag').read_text()
# Restore historical ridge only: remove the failed attempt11 post-blur extension.
pos=s.index('  // Noyau centre')
s=s[:pos]+'''  // A continuous concave fold is two affine depth planes, not a depth jump.
  // Fit the planes at the support endpoints and require all five taps to agree.
  // Reflect taps crossing their intersection back onto the receiving surface:
  // diffusion has a no-flux boundary there instead of mixing roof and wall AO.
  // Keep the full kernel and filtered input; never restore raw estimator samples.
  float stride = length(u_dir * u_depth_size);
  vec2 unit_dir = u_dir / max(stride, 1.0);
  float za = texture(u_depth, tex_coord - 2.0 * u_dir).r;
  float zai = texture(u_depth, tex_coord - 2.0 * u_dir + unit_dir).r;
  float zb = texture(u_depth, tex_coord + 2.0 * u_dir).r;
  float zbi = texture(u_depth, tex_coord + 2.0 * u_dir - unit_dir).r;
  float sm = zai - za;
  float sp = zb - zbi;
  float bm = za + 2.0 * stride * sm;
  float bp = zb - 2.0 * stride * sp;
  float bend = sp - sm;
  bool fold = u_edge_reject > 0.5 && min(min(za, zai), min(zb, zbi)) > 1e-6 &&
              bend > 0.25 * (abs(sm) + abs(sp)) + 1e-5 &&
              max(abs(za - d0), abs(zb - d0)) <= 0.02 * d0;
  float crease = fold ? (bm - bp) / bend : 0.0;
  fold = fold && abs(crease) < 2.0 * stride;
  // Endpoint slopes are quantized D24 differences. Their extrapolation over the
  // support accumulates at most (2*stride+1) quanta, plus float roundoff.
  float fit_tolerance = (2.0 * stride + 2.0) / 16777215.0;
  for (int tap = -2; tap <= 2; ++tap) {
    float offset = float(tap) * stride;
    float z = texture(u_depth, tex_coord + float(tap) * u_dir).r;
    float predicted = offset < crease ? bm + sm * offset : bp + sp * offset;
    fold = fold && z > 1e-6 && abs(z - predicted) <= fit_tolerance;
  }

'''+s[pos:]
s=s.replace('    vec2 tuv = tex_coord + u_dir * off;', '''    float sample_offset = off * stride;
    if (fold && ((crease > 0.0 && sample_offset > crease) ||
                 (crease <= 0.0 && sample_offset < crease))) {
      sample_offset = 2.0 * crease - sample_offset;
    }
    vec2 tuv = tex_coord + unit_dir * sample_offset;''')
# use actual sampled offset for bilateral prediction in reflected path
s=s.replace('    float rz = abs(td - (d0 + zslope * off));', '''    float predicted_depth = fold ? d0 + (crease > 0.0 ? sm : sp) * sample_offset
                                 : d0 + zslope * off;
    float rz = abs(td - predicted_depth);''')
(n/'attempt12-reflect.frag').write_text(s)
