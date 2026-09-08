import json,collections,re,statistics,hashlib,sys
from pathlib import Path
n=Path(__file__).parent;b=Path(sys.argv[1]);m=json.loads((b/'manifest.json').read_text());v=json.loads((n/'composition/composition-events.json').read_text())
bad=[f for f,s in m['files'].items() if not (b/f).is_file() or hashlib.sha256((b/f).read_bytes()).hexdigest()!=s]
groups=collections.defaultdict(list)
for e in v['events']:
 if e.get('actor')==1395 and e.get('refset_sample'):
  s=e['refset_sample'];groups[(e.get('case'),e.get('layer'),s['case'].split('/')[0],int(re.search(r'-h(\d+)',s['case'])[1]),e['stage'])].append(e)
out={'DIRECTIVES':'ve7fcbe0116','batch':str(b),'sealed_files':len(m['files']),'hash_failures':bad,'groups':[]}
for (case,layer,arm,hour,stage),es in sorted(groups.items(),key=lambda x:str(x[0])):
 row={'case':case,'layer':layer,'arm':arm,'hour':hour,'stage':stage,'samples':len(es),'statuses':dict(collections.Counter(e['status'] for e in es)),'mean':{k:statistics.mean(e[k] for e in es if k in e) for k in ['pixels','white','nearwhite','clipped','tonemap_white','tonemap_nearwhite','tonemap_clipped','passed','candidates','projected','visible_roi'] if any(k in e for e in es)}}
 for k in ['mean_rgba','delta_sum_rgba']:
  vs=[e[k] for e in es if k in e]
  if vs:row[k]=[statistics.mean(x[i] for x in vs) for i in range(4)]
 out['groups'].append(row)
(n/'native-summary.json').write_text(json.dumps(out,indent=2)+'\n')
log=(b/'engine.log').read_text(errors='replace');samples={int(s['chain_lf']):s for s in v['samples']};records=[]
for l in log.splitlines():
 if 'HDR-OWNER-SPRITE {' in l:
  e=json.loads(l.split('HDR-OWNER-SPRITE ',1)[1])
  if e.get('actor')==1395:e['sample']=samples.get(e.get('lf'));records.append(e)
(n/'portal-witnesses.json').write_text(json.dumps(records,indent=2)+'\n')
r=json.loads((b/'owner-regions.json').read_text());stats=[]
for reg in r['regions']:
 if reg.get('actor')!=1395:continue
 gs=collections.defaultdict(list)
 for s in reg['samples']:gs[(s['arm'],int(re.search(r'-h(\d+)',s['case'])[1]))].append(s['stats'])
 for (arm,h),vs in gs.items():stats.append({'actor':reg['actor'],'layer':reg.get('layer','all_portal_sprites'),'roi':reg.get('roi_exclusive'),'arm':arm,'hour':h,'samples':len(vs),'mean':{q:statistics.mean(v[q] for v in vs) for q in ['white','nearwhite','clipped','luma','detail','flat','saturation']},'hue_bins_mean':[statistics.mean(v['hue_bins'][i] for v in vs) for i in range(12)]})
(n/'image-region-summary.json').write_text(json.dumps(stats,indent=2)+'\n')
print('sealed_files',len(m['files']),'hash_failures',bad,'samples',len(v['samples']),'events',len(v['events']),'portal_witnesses',len(records),'unattributed_cases',r['unattributed_cases'])
for row in out['groups']:
 if row['stage'].startswith('after'):print(json.dumps(row))

effective=[]
for l in log.splitlines():
 if 'REFSET effective case=' in l:
  case,payload=l.split('REFSET effective case=',1)[1].split(' options=',1);effective.append({'case':case,'options':json.loads(payload)})
others=[e['options']['others'] for e in effective]
(n/'effective-options.json').write_text(json.dumps({'count':len(effective),'nonlighting_others_equal':all(o==others[0] for o in others) if others else None,'records':effective},indent=2)+'\n')
