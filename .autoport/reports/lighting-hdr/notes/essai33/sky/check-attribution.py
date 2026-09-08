import json,collections
from pathlib import Path
n=Path(__file__).parent
records=json.loads((n/'witnesses.json').read_text())['HDR-OWNER-SKY']
counts=collections.Counter()
for r in records:
 key=(str(r.get('tbps')),*(r.get(k) for k in ['alpha_a','alpha_b','alpha_c','alpha_d','alpha_fix']))
 counts[key]+=1
out={'DIRECTIVES':'ve7fcbe0116','sky_witnesses':len(records),'attributions':[{'tbps':k[0],'alpha':list(k[1:]),'count':v} for k,v in counts.items()]}
out['all_clouds_exact']=bool(records) and all(r.get('tbps')==[8096] and tuple(r.get(k) for k in ['alpha_a','alpha_b','alpha_c','alpha_d','alpha_fix'])==(0,2,0,1,0) for r in records)
out['gradient_8064_count']=sum(8064 in r.get('tbps',[]) for r in records)
(n/'attribution-check.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(out,indent=2))
assert out['all_clouds_exact'] and out['gradient_8064_count']==0
