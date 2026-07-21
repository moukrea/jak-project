# probe_bake — offline light-probe baker (Grecharged-lightprobes)

`probe_bake` is the desktop CLI that programmatically bakes a level's LOCAL environment-probe grid
from the STOCK fr3 (baked per-vertex time-of-day lighting + collision). It is the offline half of the
light-probe system; the runtime half is `game/graphics/opengl_renderer/LightProbeGrid.{h,cpp}`.

## Build & run
```
cmake --build build --target probe_bake
./build/tools/probe_bake/probe_bake village1        # -> out/jak1/fr3/village1.probes
```
Options: `--cell <m>` grid cell size, `--gain <f>` irradiance gain, `--skygain <f>` sky/ground fill.

## What it does (100% programmatic, no manual placement)
1. Load `<level>.fr3`, unpack tfrag/tie/shrub, read the collision mesh.
2. Explorable AABB from the collision mesh (excludes far LOD/neighbour visual geometry).
3. Auto-place a probe LAYER above every walkable (up-facing) collision surface at ALL heights, plus
   interiors auto-detected by a ceiling ray + low sky openness (inside-box room centers).
4. Per probe per TOD keyframe: CAPTURE the spherical environment by binning the nearest baked-lit
   surface radiance (occlusion) + sky/ground fill — a suns-INCLUDED HDRI of the world.
5. Project to L2 irradiance SH (diffuse, drop-in for the shader `rt_sh_ambient` Y-basis) + keep a
   prefiltered reflection cube at spread anchors.
6. Write `<level>.probes` (zstd, magic/version/level/fr3_size header), round-trip self-verified.

The core (`ProbeBakeCore.{h,cpp}`) is GL-free and compiles into both this tool and the game runtime.
See `.autoport/reports/Grecharged-lightprobes/report.txt` for the village1 bake summary + device proof.
