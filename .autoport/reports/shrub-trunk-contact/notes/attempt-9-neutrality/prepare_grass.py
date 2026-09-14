exec(open(__file__.replace('prepare_grass','prepare')).read().split('for name in')[0])
s=pathlib.Path(R+'grass.vert').read_text();s=expand(s).replace('#version 410 core','#version 300 es\nprecision highp float;\nprecision highp int;').replace('SCISSOR_ADJUST','(512.0 / 448.0)').replace('HEIGHT_SCALE','1.0')
for mode in [0,1]:
 t=s.replace('#version 300 es','#version 300 es\n#define OG_GRASS_CONTACT_PROBE') if mode else expand(original('grass.vert')).replace('#version 410 core','#version 300 es\nprecision highp float;\nprecision highp int;').replace('SCISSOR_ADJUST','(512.0 / 448.0)').replace('HEIGHT_SCALE','1.0')
 (D/f'grass-{mode}.vert').write_text(t);print('grass',mode,hashlib.sha256(t.encode()).hexdigest())
