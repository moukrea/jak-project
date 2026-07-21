# LightProbeGrid — runtime LOCAL light-probe consumer (Grecharged-lightprobes)

`LightProbeGrid.{h,cpp}` is the runtime half of the light-probe system (the offline half is
`tools/probe_bake` + `ProbeBakeCore`). It loads a level's baked `<level>.probes` grid and feeds the
4 world shaders (tfrag3 / etie_base / shrub / tie_wind) a LOCAL irradiance-volume ambient + a
prefiltered reflection cube, replacing the GLOBAL analytic SH where the grid covers a fragment.

## Per frame
- Blend the 8 baked TOD keyframes -> the current time-of-day using the scene's `itimes` weights.
- Upload the current-TOD SH as 4 dense RGBA8 `GL_TEXTURE_3D` bands (DC + L1), affine-encoded so
  hardware trilinear between valid cells is exact; validity rides in the DC alpha for a clean
  analytic fallback at the grid boundary.
- Select the reflection cube of the anchor nearest the camera and upload it (`GL_TEXTURE_CUBE_MAP`,
  mipmapped) — sampled by the shaders' `u_rt_probe_cube` for PBR IBL / metal / water reflections.

## Composition (energy-consistent, no double-count of the sun)
The probe base already contains the suns (baked HDRI), so the shader modulates it by the moving
shadow and scales the additive analytic sun to a small delta — the dynamic layer only adds moving
shadows + a crisp highlight + specular reflections. All gated behind `u_rt_probe_on` (default OFF)
inside `#ifdef OG_PBR` => probes OFF == the accepted directional-ambient path, byte-identical.

Device A/B props: `debug.opengoal.rt.probe` / `.probrefl` / `.probqual` / `.probstr`. Menu rows:
LOCAL PROBES, PROBE REFLECTIONS, PROBE QUALITY (Recharged Settings).
