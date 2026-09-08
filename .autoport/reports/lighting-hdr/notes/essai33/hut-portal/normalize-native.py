import json,collections,statistics,re
from pathlib import Path
n=Path(__file__).parent
v=json.loads((n/'composition/composition-events.json').read_text())
g=collections.defaultdict(dict)
for e in v['events']:
 if e.get('actor')==1395 and e.get('refset_sample'):
  g[(e['lf'],e.get('layer','all_portal_sprites'))][e['stage']]=e
rows=[]
w=[.2126,.7152,.0722]
for (lf,layer),st in sorted(g.items()):
 a=st.get('before_world_sprites');b=st.get('after_world_sprites')
 if not a or not b: continue
 row={'lf':lf,'layer':layer,'case':b['refset_sample']['case'],'before_status':a['status'],'after_status':b['status'],'roi':b.get('roi_exclusive'),'native_roi':b.get('roi_native_exclusive_top_left'),'viewport':b.get('viewport_native'),'pixels':b.get('pixels')}
 row['paired_window_equal']=all(a.get(k)==b.get(k) for k in ['roi_native_exclusive_top_left','viewport_native','framebuffer','pixels'])
 if a.get('mean_rgba') and b.get('mean_rgba'):
  assert row['paired_window_equal']
  row['before_luma_encoded']=sum(w[i]*a['mean_rgba'][i] for i in range(3))
  row['after_luma_encoded']=sum(w[i]*b['mean_rgba'][i] for i in range(3))
  row['delta_luma_per_pixel']=row['after_luma_encoded']-row['before_luma_encoded']
  if b.get('delta_sum_rgba'):
   row['delta_luma_sum_div_pixels']=sum(w[i]*b['delta_sum_rgba'][i] for i in range(3))/b['pixels']
   assert abs(row['delta_luma_per_pixel']-row['delta_luma_sum_div_pixels'])<1e-5
   row['delta_luma_component_bounds']=[sum(w[i]*b[k][i] for i in range(3)) for k in ['delta_min_rgba','delta_max_rgba']]
 rows.append(row)
summary=[]
groups=collections.defaultdict(list)
for r in rows:groups[(r['layer'],re.sub(r'-t\d+$','',r['case']))].append(r)
for (layer,case),rs in sorted(groups.items()):
 fields=['pixels','before_luma_encoded','after_luma_encoded','delta_luma_per_pixel']
 summary.append({'layer':layer,'case':case,'samples':len(rs),'means':{k:statistics.mean(r[k] for r in rs if k in r) for k in fields if any(k in r for r in rs)}})
out={'DIRECTIVES':'ve7fcbe0116','caveat':'Rendu inchangé ; delta de tout le groupe world sprites dans ROI attribuée harddot, pas contribution isolée harddot. Luminance pondérée des valeurs encodées (0.2126 R + 0.7152 G + 0.0722 B), normalisée par pixels ; aucun désencodage OETF ; dimensions ON/OFF peuvent varier.','rows':rows,'summary':summary}
(n/'native-normalized.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(summary,indent=2))
