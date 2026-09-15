from pathlib import Path
import hashlib,json
n=Path(__file__).resolve().parent
out={'directives':'DIRECTIVES v775512c234','diagnostic_only':True,'comparisons':{}}
for label,f in [('attempt11','attempt12-delivered-full-diagnostic.json'),('reflect','attempt12-reflect-full-diagnostic.json'),('contract','attempt12-contract-full-diagnostic.json'),('ray','attempt12-ray-full-diagnostic.json'),('delivery','attempt12-delivery-full-diagnostic.json')]:
 p=n/f;d=json.loads(p.read_text());r={}
 for mode,m in d['modes'].items():
  cmp=m['comparisons']['attempt11-reference']
  r[mode]={'native':d['historical_summary']['modes'][mode]['stages'][-1],
   'full_profile_summary':m['profile']['summary'],'contacts':m['profile']['contacts'],
   'global':cmp['global_image'],'outside_425':cmp['outside_425'],
   'outside_425_by_geometry':cmp['outside_425_by_geometry'],'source_sha256':m['source_sha256']}
 out['comparisons'][label]={'diagnostic':f,'diagnostic_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'modes':r}
# The delivered algorithm matches the pre-attempt11 reference at every archived stage.
eq={}
for mode in ['ssao','hbao','gtao']:
 eq[mode]={}
 for family,count in [('blur',8),('ridge',4)]:
  for i in range(count):
   file=f'{family}-{i}.r8';a=(n/'attempt11-reference'/mode/file).read_bytes();b=(n/'attempt11-a12-delivery'/mode/file).read_bytes()
   eq[mode][file]={'byte_identical':a==b,'sha256':hashlib.sha256(b).hexdigest()}
out['delivery_reference_all_stages']=eq
out['limitations']=['Local Intel/Mesa only. No device proof or owner validation.', 'Native prefix statistics retained unchanged; all missing/censored states remain explicit.', 'Whole-window brightness includes natural interior brightening and is not a global defect verdict.', 'Depth curvature proxies outside425 do not establish semantic identity or physical contact.', 'Complete diagnostics and full-image masks remain in notes; scripts reproduce them.']
(n/'attempt12-comparison.json').write_text(json.dumps(out,separators=(',',':'))+'\n')
for label,c in out['comparisons'].items():
 print(label,[(mode,m['native']['band_pixels'],m['full_profile_summary']['later_drop_samples_on_measurable_sides'],m['global']['changed']) for mode,m in c['modes'].items()])
print('delivery_all36_stages_identical',all(r['byte_identical'] for m in eq.values() for r in m.values()))
