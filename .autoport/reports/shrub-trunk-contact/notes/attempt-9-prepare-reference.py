#!/usr/bin/env python3
"""Reproducible neutral instrumentation overlay; never modifies the live checkout."""
from pathlib import Path
import subprocess, re, hashlib, json
ROOT=Path('/home/emeric/code/jak-project')
REF=Path('/home/emeric/code/jak-shrub-reference-602cd')
REV='602cd72eb7857fdf8059fd1f29265c31447bdb07'
NOTES=ROOT/'.autoport/reports/shrub-trunk-contact/notes'
def original(p):
    return subprocess.check_output(['git','show',f'{REV}:{p}'],cwd=ROOT).decode()
def write(p,s):
    (REF/p).parent.mkdir(parents=True,exist_ok=True)
    (REF/p).write_text(s)
def replace(s,a,b):
    assert s.count(a)==1,(a[:100],s.count(a))
    return s.replace(a,b,1)
# The three TIE shader diffs contain solely measurement varyings.
shaderdir='game/graphics/opengl_renderer/shaders/'
for name in ('tfrag3','etie','etie_base'):
    p=shaderdir+name+'.vert'
    current=(ROOT/p).read_text()
    stripped=re.sub(r'#ifdef OG_SHRUB_CONTACT_PROBE\n.*?#endif\n','',current,flags=re.S)
    assert stripped.replace('\n\n\n','\n\n')==original(p).replace('\n\n\n','\n\n'),p
    write(p,current)
p=shaderdir+'shrub.vert'
s=original(p)
declarations='#ifdef OG_SHRUB_CONTACT_PROBE\nout vec3 probe_pre_contact;\nout vec3 probe_post_contact;\nflat out uint probe_vertex_index;\n#endif\n\n'
s=replace(s,'void main() {',declarations+'void main() {')
s=replace(s,'  if (u_shrub_contact_on == 1) {','#ifdef OG_SHRUB_CONTACT_PROBE\n  probe_pre_contact = wpos;\n  probe_vertex_index = uint(gl_VertexID);\n#endif\n  if (u_shrub_contact_on == 1) {')
s=replace(s,'  vec3 vert = wpos - cam_trans.xyz;','#ifdef OG_SHRUB_CONTACT_PROBE\n  probe_post_contact = wpos;\n#endif\n  vec3 vert = wpos - cam_trans.xyz;')
write(p,s)
# Import precisely the already instrumented draw calls, matched to original GL calls.
for name in ('Shrub','Tie3'):
    p=f'game/graphics/opengl_renderer/background/{name}.cpp'
    s=original(p)
    cur=(ROOT/p).read_text()
    prefix='m_level_name, -1, idx, render_state->frame_idx, ' if name=='Shrub' else 'm_level_name, geom, idx, render_state->frame_idx, '
    inserted=0
    for match in re.finditer(r'shrub_contact_measurement::(draw_elements|multi_draw_elements)\((.*?)\);',cur,re.S):
        args=re.sub(r'\s+',' ',match[2])
        assert args.startswith(prefix)
        glname='glDrawElements' if match[1]=='draw_elements' else 'glMultiDrawElements'
        glargs=args[len(prefix):]
        # Whitespace varies in upstream formatting; only match equal argument tokens.
        pattern=glname+r'\s*\(\s*'+r'\s*'.join(re.escape(t) for t in re.split(r'\s+',glargs.strip()))+r'\s*\);'
        glmatch=re.search(pattern,s)
        if glmatch is None:
            # Multidraw may split after opening paren; compare after dropping whitespace.
            target=re.sub(r'\s+','',glargs)
            glmatch=next((m for m in re.finditer(glname+r'\((.*?)\);',s,re.S) if re.sub(r'\s+','',m[1])==target and not s[m.end():].lstrip().startswith('shrub_contact_probe::')),None)
        else:
            # Repeated calls must each be instrumented once.
            if s[glmatch.end():].lstrip().startswith('shrub_contact_probe::'):
                target=re.sub(r'\s+','',glargs)
                glmatch=next((m for m in re.finditer(glname+r'\((.*?)\);',s,re.S) if re.sub(r'\s+','',m[1])==target and not s[m.end():].lstrip().startswith('shrub_contact_probe::')),None)
        assert glmatch is not None,(name,glname,glargs)
        call=match[0].replace('shrub_contact_measurement::','shrub_contact_probe::')
        s=s[:glmatch.end()]+'\n      '+call+s[glmatch.end():]
        inserted+=1
    s='#include "shrub_contact_probe.h"\n'+s
    write(p,s)
    print(f'{p} probe_draws={inserted}')
# Remaining agent patches and CMake entries are applied after this base overlay.
manifest={}
for p in ('common/custom_data/TFrag3Data.cpp','common/custom_data/Tfrag3Data.h','game/graphics/opengl_renderer/loader/Loader.cpp','game/graphics/opengl_renderer/shaders/tie_sway.glsl','game/graphics/opengl_renderer/shaders/vegetation_contact.glsl'):
    content=(REF/p).read_bytes()
    assert content==subprocess.check_output(['git','show',f'{REV}:{p}'],cwd=ROOT),p
    manifest[p]=hashlib.sha256(content).hexdigest()
(NOTES/'attempt-9-reference-original-manifest.json').write_text(json.dumps({'revision':REV,'unchanged_gameplay_files':manifest},indent=2)+'\n')
print('original_gameplay_manifest=verified')
