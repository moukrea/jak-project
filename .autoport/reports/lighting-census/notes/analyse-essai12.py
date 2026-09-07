from pathlib import Path
import hashlib, re, json, importlib.util
import numpy as np
r=Path('.autoport/reports/lighting-census'); n=r/'notes'
spec=importlib.util.spec_from_file_location('compare', '.autoport/tools/refset_compare.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
files=sorted(p for p in (n/'essai11-avant12/refset-actual').glob('*.png') if re.fullmatch(r'(origine|origine-lumiere|recharged)-h[0-9]{2}\.png', p.name))
assert len(files)==24
rows=[]
for old in files:
    new=r/'refset-actual'/old.name
    game,hour=old.stem.rsplit('-h',1)
    a=m.load(old); b=m.load(new); orig=m.load(Path('.autoport/refset')/game/f'h{hour}.png')
    assert a.shape==b.shape==orig.shape
    d=np.abs(a-b).max(axis=2); refd=np.abs(orig-b).max(axis=2)
    ys,xs=np.nonzero(refd)
    outside=(refd>0).copy(); outside[13:73,285:316]=False
    rows.append(dict(image=old.name,sha_equal=hashlib.sha256(old.read_bytes()).digest()==hashlib.sha256(new.read_bytes()).digest(),versus_essai11_maxdiff=int(d.max()),versus_essai11_diffpx=int((d>0).sum()),versus_reference_maxdiff=int(refd.max()),versus_reference_diffpx=int((refd>0).sum()),reference_bbox=[int(xs.min()),int(ys.min()),int(xs.max()),int(ys.max())] if len(xs) else None,outside_roi=int(outside.sum())))
(n/'legacy-comparisons-essai12.json').write_text(json.dumps(rows,indent=2)+'\n')
log=(r/'proof-engine.log').read_bytes().decode('utf-8','replace')
roi=[s for s in log.splitlines() if s.startswith('REFSET-ROI ') and 'capture=1 ' in s]
(n/'roi-capture1-essai12.log').write_text('\n'.join(roi)+'\n')
nonzero=[s for s in roi if re.search(r'rgb_changed=[1-9]',s)]
(n/'roi-capture1-rgb-nonzero-essai12.log').write_text('\n'.join(nonzero)+'\n')
cases=re.findall(r'^REFSET case index=(\d+) layer=(\S+) name=(\S+)',log,re.M)
assert [int(c[0]) for c in cases]==list(range(672))
assert sum(c[1]=='historical' for c in cases)==564
assert sum(c[1]=='supplement-v1' for c in cases)==108, set(c[1] for c in cases)
(n/'plan-essai12.tsv').write_text('\n'.join('\t'.join(c) for c in cases)+'\n')
summary=dict(png_count=len(rows),sha_equal=sum(x['sha_equal'] for x in rows),outside_roi=sum(x['outside_roi'] for x in rows),origine_h00=next(x for x in rows if x['image']=='origine-h00.png'),gl_invalid_operation_count=log.count('GL_INVALID_OPERATION'),gl_invalid_enum_count=log.count('GL_INVALID_ENUM'),gl_invalid_value_count=log.count('GL_INVALID_VALUE'),roi_capture1_lines=len(roi),roi_capture1_rgb_nonzero=len(nonzero),case_count=len(cases))
(n/'summary-essai12.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
