#!/usr/bin/env python3
"""DIRECTIVES v775512c234: local GLSL synthetic comparisons; no device proof."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,subprocess
n=Path(__file__).resolve().parent
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--shader',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
out=a.output.resolve()
if out.parent!=n or not out.name.startswith('attempt11'):p.error('new notes/attempt11* output required')
out.mkdir()
r=n.parents[3]/'game/graphics/opengl_renderer/shaders';sp=importlib.util.spec_from_file_location('preprocess',r/'preprocess.py');pre=importlib.util.module_from_spec(sp);sp.loader.exec_module(pre)
for label,path,stage in [('reference',n/'attempt11-reference.frag','frag'),('candidate',a.shader,'frag'),('vertex',r/'ao_blur.vert','vert')]:
 data=path.read_bytes();(out/(label+'.source')).write_bytes(data);(out/(label+'.glsl')).write_text(pre.to_gles(data.decode(),stage))
cmd=[str(n/'attempt11-invariants'),str(out/'vertex.glsl'),str(out/'reference.glsl'),str(out/'candidate.glsl')]
with (out/'invariants.log').open('w') as f:run=subprocess.run(cmd,cwd=n.parents[3],stdout=f,stderr=subprocess.STDOUT)
(out/'run.json').write_text(json.dumps({'directives':'DIRECTIVES v775512c234','diagnostic_only':True,'command':cmd,'returncode':run.returncode,'sha256':{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in out.glob('*.source')}},indent=2))
print(out/'invariants.log');raise SystemExit(run.returncode)
