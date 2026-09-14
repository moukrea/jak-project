#!/usr/bin/env python3
"""Transfer only this attempt's measurement edits onto the original reference.
Run after attempt-9-prepare-reference.py; fails on ambiguous context.
"""
from pathlib import Path
import subprocess,difflib,re,shutil,json,hashlib
R=Path('/home/emeric/code/jak-project'); T=Path('/home/emeric/code/jak-shrub-reference-602cd')
BASE='f3341b2953'; REF='602cd72eb7'; notes=R/'.autoport/reports/shrub-trunk-contact/notes'
def gittext(rev,p):return subprocess.check_output(['git','show',f'{rev}:{p}'],cwd=R).decode()
def transfer(p,old,new,target):
 # Reverse edit order prevents overlapping context changes.
 ops=difflib.SequenceMatcher(None,old.splitlines(True),new.splitlines(True),autojunk=False).get_opcodes()
 a=old.splitlines(True);b=new.splitlines(True)
 for tag,i,j,x,y in reversed(ops):
  if tag=='equal':continue
  if i==j==0:
   target=''.join(b[x:y])+target;continue
  found=None
  for c in range(5,0,-1):
   for left,right in ((c,c),(c,0),(0,c)):
    before=''.join(a[max(0,i-left):i]);after=''.join(a[j:j+right]);remove=''.join(a[i:j]);pat=before+remove+after
    if pat and target.count(pat)==1:
     found=(pat,before+''.join(b[x:y])+after);break
   if found:break
  if not found:raise RuntimeError((p,tag,repr(''.join(a[i:j])),repr(''.join(b[x:y]))))
  target=target.replace(*found,1)
 return target
files=['game/graphics/opengl_renderer/GrassRenderer.cpp','game/graphics/opengl_renderer/shaders/grass.vert','game/graphics/opengl_renderer/background/foliage_wind.cpp']
# Work on original copies; the three files have no prior instrumentation overlay.
for p in files:
 (T/p).write_text(transfer(p,gittext(BASE,p),(R/p).read_text(),gittext(REF,p)))
# Shrub manager LUT blobs depend on new rows: exclude these from current delta then add
# a native-shape observation separately below. Keep input-tape changes only.
p='game/graphics/opengl_renderer/background/Shrub.cpp';cur=(R/p).read_text()
cur=re.sub(r'\n  +if \(autoport_proof::feature_is\(kTrunkItemId\)\) \{\n(?:.*\n)*?  +\}', '',cur)
target=transfer(p,gittext(BASE,p),cur,(T/p).read_text())
if '#include "game/system/autoport_proof.h"' not in target:target='#include "game/system/autoport_proof.h"\n'+target
marker='                   contact_lut.data());';assert target.count(marker)==1
target=target.replace(marker,marker+'''
      if (autoport_proof::feature_is("shrub-trunk-contact")) {
        shrub_contact_probe::archive_blob("shrub", lev_data->level_name, -1, l_tree, "native-row0",
            contact_lut.data(), n_mat * 4 * sizeof(float));
        shrub_contact_probe::archive_blob("shrub", lev_data->level_name, -1, l_tree, "contact-anchor",
            contact_lut.data() + n_mat * 4, n_mat * 4 * sizeof(float),
            shrub_contact_probe::InputMapping::Contact);
      }''')
marker='                  tree.wind_texels.data());';assert target.count(marker)==1
target=target.replace(marker,marker+'''
  if (autoport_proof::feature_is("shrub-trunk-contact")) {
    shrub_contact_probe::archive_blob("shrub", m_level_name, -1, &tree - m_trees.data(),
        "native-row0", tree.wind_texels.data(), n_mat * 4 * sizeof(float));
  }''');(T/p).write_text(target)
p='game/graphics/opengl_renderer/loader/LoaderStages.cpp';s=gittext(REF,p)
s='#include "game/graphics/opengl_renderer/background/shrub_contact_probe.h"\n#include "game/system/autoport_proof.h"\n'+s
marker='                         GL_RGBA, GL_FLOAT, contact_anchors.data());';assert s.count(marker)==1
s=s.replace(marker,marker+'''
            if (autoport_proof::feature_is("shrub-trunk-contact")) {
              shrub_contact_probe::archive_blob("tie", data.lev_data->level->level_name,
                  geo, &in_tree - in_trees.data(), "contact-anchor", contact_anchors.data(),
                  contact_anchors.size() * sizeof(contact_anchors[0]),
                  shrub_contact_probe::InputMapping::Contact);
            }''');(T/p).write_text(s)
# Runtime source files are copied, never corrected geometry/Loader classes.
for p in ['game/system/shrub_proof_inputs.h','game/system/shrub_proof_inputs.cpp','game/graphics/opengl_renderer/background/shrub_contact_probe.h','game/graphics/opengl_renderer/background/shrub_contact_probe.cpp','game/graphics/opengl_renderer/background/shrub_contact_archive.h']:
 shutil.copyfile(R/p,T/p)
# Shader compiler: original plus ONLY contact/grass defines and TF varyings.
p='game/graphics/opengl_renderer/Shader.cpp';s=gittext(REF,p);cur=(R/p).read_text()
start=cur.index('  const bool contact_probe =');end=cur.index('  constexpr int len',start)
s=s.replace('  constexpr int len',cur[start:end]+'  constexpr int len',1)
start=cur.index('  if (contact_probe) {',cur.index('  m_program = glCreateProgram();'));end=cur.index('  glLinkProgram(m_program);',start)
s=s.replace('  glLinkProgram(m_program);',cur[start:end]+'  glLinkProgram(m_program);',1)
start=cur.index('  if (grass_probe) {',cur.index('  glLinkProgram(m_program);'));end=cur.index('  shade_proof::note_program_linked',start)
s=s.replace('  shade_proof::note_program_linked',cur[start:end]+'  shade_proof::note_program_linked',1)
s='void grass_proof_register_program(unsigned int colour, unsigned int measure);\n'+s
if '#include "game/system/autoport_proof.h"' not in s:s='#include "game/system/autoport_proof.h"\n'+s
(T/p).write_text(s)
p='game/graphics/opengl_renderer/OpenGLRenderer.cpp';s=gittext(REF,p);s='#include "game/graphics/opengl_renderer/background/shrub_contact_probe.h"\n'+s
marker='  g_current_renderer = "dispatch-buckets post";';assert s.count(marker)==1;s=s.replace(marker,'  shrub_contact_probe::archive_tick();\n'+marker);(T/p).write_text(s)
for p in ['game/CMakeLists.txt','android/CMakeLists.txt']:
 s=gittext(REF,p)
 marker='        system/autoport_proof.cpp' if p.startswith('game/') else '    "${JAK_ROOT}/game/system/autoport_proof.cpp"'
 extra='        system/shrub_proof_inputs.cpp\n        graphics/opengl_renderer/background/shrub_contact_probe.cpp' if p.startswith('game/') else '    "${JAK_ROOT}/game/system/shrub_proof_inputs.cpp"\n    "${JAK_ROOT}/game/graphics/opengl_renderer/background/shrub_contact_probe.cpp"'
 assert s.count(marker)==1;s=s.replace(marker,marker+'\n'+extra);(T/p).write_text(s)
patch=subprocess.check_output(['git','diff','--binary'],cwd=T)
(notes/'attempt-9-reference-instrumentation.patch').write_bytes(patch)
manifest={p:hashlib.sha256((T/p).read_bytes()).hexdigest() for p in subprocess.check_output(['git','diff','--name-only'],cwd=T).decode().splitlines()}
(notes/'attempt-9-reference-overlay-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('reference_overlay_files='+str(len(manifest)))
