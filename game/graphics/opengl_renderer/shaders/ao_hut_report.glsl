// Proof-only replay outputs. Regular rendering uses u_hut_report=0.
// Counts are integer bytes (not normalized ratios); causes can overlap.
uniform int u_hut_report;
vec4 hut_reject = vec4(0.0); // offscreen, sky, beyond radius, below min radius
vec4 hut_other = vec4(0.0); // bias/horizon, above-plane, degenerate slice, candidates
vec4 hut_broad_reject = vec4(0.0);
vec4 hut_broad_other = vec4(0.0); // bias, above-plane, accepted, candidates
vec4 hut_terms = vec4(0.0); // un-gated occ, gated occ, fade, final AO
void hut_finish(vec3 N) {
  if (u_hut_report == 1) {
    bool valid = !any(isnan(N)) && !any(isinf(N)) && dot(N, N) > 0.0;
    color = valid ? vec4(N * 0.5 + 0.5, 1.0) : vec4(0.0);
  }
  if (u_hut_report == 2) color = hut_reject / 255.0;
  if (u_hut_report == 3) color = hut_other / 255.0;
  if (u_hut_report == 4) color = hut_broad_reject / 255.0;
  if (u_hut_report == 5) color = hut_broad_other / 255.0;
  if (u_hut_report == 6) color = hut_terms;
}
