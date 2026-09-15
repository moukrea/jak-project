#!/usr/bin/env python3
"""DIRECTIVES v775512c234. Local diagnostic replay, never device proof.
Reuses attempt10 profile command/reader and frozen physical populations verbatim.
"""
import argparse, hashlib, importlib.util, json, pathlib, re, subprocess, sys
N = pathlib.Path(__file__).resolve().parent
ROOT = N.parents[3]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--shader', required=True, type=pathlib.Path)
p.add_argument('--output', required=True, type=pathlib.Path)
a = p.parse_args()
out = a.output.resolve()
if out.parent != N or not out.name.startswith('attempt11'):
    p.error('output must be a new notes/attempt11* directory')
out.mkdir()
sp = importlib.util.spec_from_file_location('preprocess', ROOT/'game/graphics/opengl_renderer/shaders/preprocess.py')
pre = importlib.util.module_from_spec(sp); sp.loader.exec_module(pre)
shader = a.shader.read_text()
(out/'source.frag').write_text(shader)
(out/'fragment.glsl').write_text(pre.to_gles(shader, 'frag'))
(out/'vertex.glsl').write_text(pre.to_gles((ROOT/'game/graphics/opengl_renderer/shaders/ao_blur.vert').read_text(), 'vert'))
summary = {'directives':'DIRECTIVES v775512c234','diagnostic_only':True,
 'shader_sha256':hashlib.sha256(shader.encode()).hexdigest(),
 'gles_shader_sha256':hashlib.sha256((out/'fragment.glsl').read_bytes()).hexdigest(),
 'native_reader_sha256':hashlib.sha256((N/'attempt10-profile-native').read_bytes()).hexdigest(),
 'limitations':['local Intel/Mesa driver; not device validation','archive differences include known inter-driver R8 quantization','one missing profile side remains explicit'], 'modes':{}}
commands = []
def run(cmd, logfile):
    commands.append(cmd)
    with logfile.open('w') as f:
        subprocess.run(list(map(str,cmd)),cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,check=True)
def fnv(data):
    h=14695981039346656037
    for b in data: h=((h^b)*1099511628211)&((1<<64)-1)
    return h
for label, directory in [('ssao','attempt10-04-ssao-after'),('hbao','attempt10-05-hbao-after'),('gtao','attempt10-06-gtao-after')]:
    source = N/directory
    archive, = source.glob('ao-hut-archive-*')
    dest = out/label
    dest.mkdir()
    run([N/'attempt11-blur-replay',archive,out/'vertex.glsl',out/'fragment.glsl',dest],dest/'replay.log')
    for f in archive.iterdir():
        if f.name != 'manifest.txt' and not (dest/f.name).exists(): (dest/f.name).symlink_to(f)
    # This manifest indexes derived local stages solely for the existing reader.
    # Original archive and its proof files stay untouched; it is never a proof.
    rows=[]
    for row in (archive/'manifest.txt').read_text().splitlines():
        match=re.search(r'^stage=(\S+)',row)
        if match and (dest/match[1]).is_file() and not (dest/match[1]).is_symlink():
            row=re.sub(r'fnv1a64=\d+', 'fnv1a64='+str(fnv((dest/match[1]).read_bytes())),row)
        rows.append(row)
    (dest/'manifest.txt').write_text('\n'.join(rows)+'\n')
    (dest/'LOCAL-DERIVED-NOT-DEVICE-PROOF.txt').write_text('Derived local replay; original input archive: '+str(archive)+'\n')
    run([sys.executable,N/'attempt10-profile.py',dest,'--attribution',source/'roi-gpu.json','--qualification',N/'attempt10-contact-patches.json','--native',N/'attempt10-profile-native','--reference-profile',N/'attempt10-03-gtao-before/contact-profiles.json','--output',dest/'contact-profiles.json'],dest/'profile.log')
    result=json.loads((dest/'contact-profiles.json').read_text())
    summary['modes'][label]={'archive':str(archive),'population':result['populations'], 'reference_population_comparison':result['reference_population_comparison'],'stages':result['stages']}
(out/'commands.json').write_text(json.dumps(commands,default=str,indent=2))
(out/'summary.json').write_text(json.dumps(summary,indent=2))
print(out/'summary.json')
for mode,result in summary['modes'].items(): print(mode,json.dumps(result['stages'][-1]))
