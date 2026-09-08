from pathlib import Path
import re,json,datetime,hashlib,sys
b=Path(sys.argv[1]);n=Path(__file__).resolve().parent
raw=(b/'engine.log').read_bytes();repins={};samples=[];effective=[];witnesses=[]
def time_of(line):return datetime.datetime.strptime(line[:18],'%m-%d %H:%M:%S.%f')
for line_no,line in enumerate(raw.decode(errors='replace').splitlines(),1):
 if 'REFSET repin-particules case=' in line:
  f=dict(re.findall(r'(\w+)=([^\s]+)',line.split('REFSET repin-particules ',1)[1]));repins[int(f['lf'])]={'line':line_no,'raw':line,'time':time_of(line)}
 elif 'REFSET sample case=' in line:
  f=dict(re.findall(r'(\w+)=([^\s]+)',line.split('REFSET sample ',1)[1]));r=repins.get(int(f['particle_repin_lf']));seconds=(time_of(line)-r['time']).total_seconds() if r else None
  samples.append({'fields':f,'sample_line':line_no,'repin_line':r['line'] if r else None,'wall_seconds':seconds,'minimum10s_observed':seconds is not None and seconds>=10,'raw':line,'repin_raw':r['raw'] if r else None})
 elif 'REFSET effective case=' in line:
  effective.append({'line':line_no,'raw':line,'options':json.loads(line.split(' options=',1)[1])})
 elif 'HDR-OWNER-SPRITE {' in line:
  e=json.loads(line.split('HDR-OWNER-SPRITE ',1)[1])
  if e.get('layer')=='portal_disc':witnesses.append({'line':line_no,'event':e})
(n/'timing-and-witnesses.json').write_text(json.dumps({'engine_sha256':hashlib.sha256(raw).hexdigest(),'samples':samples,'effective':effective,'portal_witnesses':witnesses},indent=2)+'\n')
for s in samples:print(s['fields']['case'],s['fields']['sample'],'age',s['fields']['particle_age'],'wall',s['wall_seconds'],'lines',s['repin_line'],s['sample_line'])
print('portal_witnesses',len(witnesses))
