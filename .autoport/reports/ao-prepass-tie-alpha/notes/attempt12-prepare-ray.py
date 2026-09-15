from pathlib import Path
n=Path(__file__).resolve().parent
s=(n/'attempt11-reference.frag').read_text()
pos=s.index('  // Noyau centre')
s=s[:pos]+'''  // Locate a continuous concave fold inside THIS blur support. Four consecutive
  // depth texels define the two one-sided planes and their subpixel intersection.
  // The centre must belong to the receiving plane; distant surface changes cannot
  // supply a boundary. Limit normal diffusion by distance to that intersection.
  float stride = length(u_dir * u_depth_size);
  vec2 unit_dir = u_dir / max(stride, 1.0);
  float support = 2.0 * stride;
  float radius = support;
  float receiving_slope = zslope / max(stride, 1.0);
  if (u_edge_reject > 0.5) {
    for (int k = -10; k < 10; ++k) {
      if (float(k) < -support || float(k) >= support) continue;
      vec2 uv = tex_coord + float(k) * unit_dir;
      float za = texture(u_depth, uv - unit_dir).r;
      float zb = texture(u_depth, uv).r;
      float zc = texture(u_depth, uv + unit_dir).r;
      float zd = texture(u_depth, uv + 2.0 * unit_dir).r;
      float sm = zb - za;
      float sp = zd - zc;
      float bend = sp - sm;
      if (min(min(za, zb), min(zc, zd)) <= 1e-6 ||
          bend <= 0.25 * (abs(sm) + abs(sp)) + 1e-5 ||
          max(max(abs(sm), abs(sp)), abs(zc-zb)) > 0.02 * min(zb, zc)) continue;
      float t = (zb + sp - zc) / bend;
      if (t < 0.0 || t > 1.0) continue;
      float crease = float(k) + t;
      float plane_slope = crease > 0.0 ? sm : sp;
      float plane_centre = crease > 0.0 ? zb - sm * float(k)
                                       : zc - sp * float(k + 1);
      float tolerance = (abs(float(k)) + 3.0) / 16777215.0;
      if (abs(d0 - plane_centre) > tolerance) continue;
      if (abs(crease) < radius) {
        radius = abs(crease);
        receiving_slope = plane_slope;
      }
    }
  }

'''+s[pos:]
s=s.replace('    vec2 tuv = tex_coord + u_dir * off;', '''    float sample_offset = off * stride * (radius / max(support, 1.0));
    vec2 tuv = tex_coord + unit_dir * sample_offset;''')
s=s.replace('    float rz = abs(td - (d0 + zslope * off));', '''    float predicted_depth = radius < support ? d0 + receiving_slope * sample_offset
                                              : d0 + zslope * off;
    float rz = abs(td - predicted_depth);''')
(n/'attempt12-ray.frag').write_text(s)
