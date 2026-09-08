import importlib.util,json,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('hdr_batches','.autoport/lib/hdr_batches.py')
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
before=Path('.autoport/reports/lighting-hdr/batches/essai24-projected/20260908T060523-3743175')
after=Path(sys.argv[1]); out=Path('.autoport/reports/lighting-hdr/notes/essai25')
regions={tag:json.loads((p/'owner-regions.json').read_text())['regions'] for tag,p in [('before',before),('after',after)]}
rows=[]
for old in regions['before']:
    new=next((r for r in regions['after'] if (r['actor'],r['view_hour'])==(old['actor'],old['view_hour'])),None)
    if new is None:
        rows.append({'actor':old['actor'],'view_hour':old['view_hour'],'missing_after':True});continue
    rect=[min(old['roi_exclusive'][i],new['roi_exclusive'][i]) if i<2 else max(old['roi_exclusive'][i],new['roi_exclusive'][i]) for i in range(4)]
    row={'actor':old['actor'],'view_hour':old['view_hour'],'common_roi':rect,'arms':{}}
    for tag,root,region in [('before',before,old),('after',after,new)]:
        for arm in ['origine-lumiere','recharged']:
            data=[]
            for sample in region['samples']:
                if sample['arm']!=arm:continue
                path=root/sample['image'];assert h.sha(path)==sample['sha256']
                data.append({'image':str(path),'sha256':h.sha(path),'stats':h.measure(path,rect)})
            row['arms'][tag+'_'+arm]={'samples':data,'mean':{k:sum(s['stats'][k] for s in data)/len(data) for k in ['white','nearwhite','clipped','luma','detail','flat','saturation']}}
    rows.append(row)
out.joinpath('before-after-regions.json').write_text(json.dumps({'purpose':'diagnostic AVANT/APRES, old binary not campaign proof','before':str(before),'after':str(after),'regions':rows},indent=2)+'\n')
for row in rows:
    print(row['actor'],row['view_hour'],row.get('common_roi'))
    for arm,data in row.get('arms',{}).items():print(arm,data['mean'])
