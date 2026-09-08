from pathlib import Path
import hashlib,json
n=Path(__file__).resolve().parent
pairs=[('sky96',n.parent/'essai39/sky'),('portal96',n.parent/'essai40/portal-final')]
out={'DIRECTIVES':'v708c60642a','purpose':'diagnostic before/after from sealed measured summaries; old binaries are not current proof','comparisons':[]}
for name,old in pairs:
 new=n/name
 paths=[old/'image-region-summary.json',new/'image-region-summary.json']
 if not all(p.exists() for p in paths):
  out['comparisons'].append({'case':name,'status':'absent_new_measurements'});continue
 rows=[json.loads(p.read_text()) for p in paths]
 keys=lambda r:(r['layer'],r['hour'],tuple(r['roi']))
 cases=sorted(set(keys(r) for data in rows for r in data))
 result={'case':name,'sources':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths],'regions':[]}
 for key in cases:
  entry={'layer':key[0],'hour':key[1],'roi':key[2]}
  for label,data in zip(['before','after'],rows):
   arms={r['arm']:r for r in data if keys(r)==key}
   if set(arms)!={'recharged','origine-lumiere'}:
    entry[label]={'status':'noncomparable_or_absent_roi'};continue
   on,off=[arms[a]['mean'] for a in ['recharged','origine-lumiere']]
   entry[label]={'samples':{a:r['samples'] for a,r in arms.items()},'on':on,'off':off,'on_minus_off':{k:on[k]-off[k] for k in on}}
  result['regions'].append(entry)
 out['comparisons'].append(result)
(n/'before-after.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(out,indent=2))
