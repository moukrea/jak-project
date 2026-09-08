# Read-only analysis of official producer artifacts. No proof writes, no runtime measurement.
from pathlib import Path
import json,hashlib,re,collections,struct,sys,shutil
n=Path(sys.argv[1]);b=Path((n/'batch-path.txt').read_text().strip());m=json.loads((b/'manifest.json').read_text());r=json.loads((n/'restoration.json').read_text());proof=(n/'proof-coverage.txt').read_text();kv=dict(x.split('=',1) for x in proof.splitlines() if '=' in x)
def sha(p):
 with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
errors=[f'missing/hash {p}' for p,h in m['files'].items() if not (b/p).is_file() or sha(b/p)!=h]
identity=json.loads((n.parent/'build/device-identity.json').read_text())
if m['provenance']['binary_sha256']!=identity['lib'] or m['provenance']['installed_sha256']!=identity['lib']:errors.append('binary mismatch')
if m['provenance']['apk_sha256']!=identity['apk']:errors.append('APK mismatch')
restored=(r['original_settings_sha256']==r['restored_settings_sha256']==sha(n/'settings-original.ini')==identity['settings_sha256'] and bool(r['pids'][0]) and r['pids'][0]==r['pids'][1] and not r['nonempty_debug_props'] and all(c['rc']==0 for c in r['calls']))
if not restored:errors.append('restoration mismatch')
counts=collections.defaultdict(collections.Counter);images=json.loads((b/'pixels.json').read_text())['images']
for p,rec in images.items():
 if sha(b/p)!=rec['sha256']:errors.append('pixels hash '+p)
 if struct.unpack('>II',(b/p).read_bytes()[16:24])!=(320,180):errors.append('dimensions '+p)
 arm,view,h,sample=re.fullmatch(r'captures/([^/]+)/(.+)-h(\d+)(?:-t(\d+))?\.png',p).groups();counts[(view,arm)][int(h)]+=1
cmd=json.loads((n/'command.json').read_text());views=cmd[cmd.index('--hdr-vantages')+1].split(',');missing=[]
for v in views:
 for a in ['recharged','origine-lumiere']:
  for h in [0,3,6,9,12,15,18,21]:
   if counts[(v,a)][h]!=2:missing.append({'view':v,'arm':a,'hour':h,'observed':counts[(v,a)][h]})
fields={k:kv.get(k,'absent') for k in ['source','serial','duration_s','crash','frames','hdr_batch_errors','hdr_batch_pairs','hdr_batch_cells','hdr_batch_missing','hdr_batch_quality_bad','hdr_batch_count','hdr_owner_regressions_passed','hdr_owner_regressions_missing','hdr_owner_regressions_failed','hdr_tonemap_defects']}
aggregate_path=b.parent/'measurements.json'
if aggregate_path.exists():
 aggregate=json.loads(aggregate_path.read_text())
 if 'pairs' in aggregate:shutil.copy2(aggregate_path,n/'measurements.json')
result={'DIRECTIVES':'v8aed688f73','batch':str(b),'manifest_sha256':sha(b/'manifest.json'),'sealed_files':len(m['files']),'errors':errors,'producer_exit':int((n/'exit.txt').read_text()),'manifest_errors':m['errors'],'manifest_crash':m['crash'],'pngs':len(images),'requested_views':views,'counts':[{'view':v,'arm':a,'hours':dict(sorted(c.items()))} for (v,a),c in sorted(counts.items())],'missing_local_samples':missing,'proof_fields':fields,'restored':restored,'restored_pid':r['pids'][0],'settings_sha256':r['restored_settings_sha256'],'apk_sha256':m['provenance']['apk_sha256'],'binary_sha256':m['provenance']['binary_sha256']}
(n/'audit.json').write_text(json.dumps(result,indent=2))
lines=[next((l for l in proof.splitlines() if l.startswith(k+'=')),k+' absent de la preuve') for k in ['source','serial','crash','frames','hdr_batch_pairs','hdr_batch_cells','hdr_owner_regressions_passed','hdr_tonemap_defects']]
(n/'verdict.md').write_text('DIRECTIVES v8aed688f73\nLot borné collecté ; qualité finale et régions owner non validées.\n'+'\n'.join(lines)+'\nVues : '+','.join(views)+'\n'+str(len(images))+'PNG ;'+str(len(m['files']))+'fichiers scellés ; erreurs audit '+str(errors)+' ; lacunes samples locales '+str(len(missing))+'.\nErreurs manifeste : '+str(m['errors'])+' ; crash '+str(m['crash'])+'.\nRestauration exacte : '+str(restored)+' ; PID'+r['pids'][0]+'stable12s ; settingsSHA'+r['restored_settings_sha256']+'.\nAPK '+m['provenance']['apk_sha256']+'\nLib '+m['provenance']['binary_sha256']+'\nnon prouvé : qualité finale/ciels/intérieurs/vraie hutte/ROI sol, cinq cas owner, Honor.\nAucune relance ni changement source/validateur.\n')
files=[p for p in n.rglob('*') if p.is_file() and p.name!='archive-sha256.json'];(n/'archive-sha256.json').write_text(json.dumps({str(p.relative_to(n)):sha(p) for p in files},indent=2))
print(json.dumps({k:v for k,v in result.items() if k!='counts'},indent=2))
