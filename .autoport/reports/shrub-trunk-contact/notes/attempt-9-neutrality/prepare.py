import pathlib,re,subprocess,hashlib
D=pathlib.Path(__file__).parent
R='game/graphics/opengl_renderer/shaders/'
def original(n): return subprocess.check_output(['git','show','602cd72eb7:'+R+n],text=True)
def expand(s): return re.sub(r'^\s*#include "([^"]+)"\s*$',lambda m:expand(original(m[1])),s,flags=re.M)
for name in ['shrub','tfrag3','etie','etie_base']:
 s=original(name+'.vert')
 decl='\n#ifdef OG_SHRUB_CONTACT_PROBE\nout vec3 probe_pre_contact;\nout vec3 probe_post_contact;\nflat out uint probe_vertex_index;\n#endif\n'
 s=s.replace('void main() {',decl+'\nvoid main() {')
 if name=='shrub':
  s=s.replace('  if (u_shrub_contact_on == 1)', '#ifdef OG_SHRUB_CONTACT_PROBE\n probe_pre_contact = wpos; probe_vertex_index = uint(gl_VertexID);\n#endif\n  if (u_shrub_contact_on == 1)')
  s=s.replace('  vec3 vert = wpos', '#ifdef OG_SHRUB_CONTACT_PROBE\n probe_post_contact = wpos;\n#endif\n  vec3 vert = wpos')
 else:
  v='sway_pos' if name=='tfrag3' else 'position_sway'
  line=f'  vec3 {v} = tie_contact_apply(position_in, tie_sway_apply(position_in, tie_sway_in));'
  assert line in s
  s=s.replace(line,'#ifdef OG_SHRUB_CONTACT_PROBE\n probe_pre_contact = tie_sway_apply(position_in, tie_sway_in); probe_vertex_index = uint(gl_VertexID);\n#endif\n'+line+'\n#ifdef OG_SHRUB_CONTACT_PROBE\n probe_post_contact = '+v+';\n#endif')
 s=expand(s).replace('#version 410 core','#version 300 es\nprecision highp float;\nprecision highp int;\nprecision highp sampler2D;').replace('SCISSOR_ADJUST','(512.0 / 448.0)').replace('HEIGHT_SCALE','1.0')
 for mode in [0,1]:
  t=s.replace('#version 300 es','#version 300 es\n#define OG_SHRUB_CONTACT_PROBE') if mode else s
  p=D/f'{name}-{mode}.vert';p.write_text(t)
  print(p.name,hashlib.sha256(t.encode()).hexdigest())
