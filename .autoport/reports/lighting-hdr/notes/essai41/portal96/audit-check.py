from pathlib import Path
import json,hashlib,statistics
n=Path(__file__).resolve().parent
b=Path((n/'batch-path.txt').read_text().strip())
def j(p):return json.loads(Path(p).read_text())
def sha(p):
 with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
m=j(b/'manifest.json');bad=[p for p,h in m['files'].items() if sha(b/p)!=h];assert not bad
identity=j(n.parent/'build96/device-identity.json');assert m['provenance']['binary_sha256']==m['provenance']['installed_sha256']==identity['lib'];assert m['provenance']['apk_sha256']==identity['apk']
t=j(n/'timing-and-witnesses.json');assert t['engine_sha256']==sha(b/'engine.log');assert len(t['samples'])==4
lines=(b/'engine.log').read_text(errors='replace').splitlines()
for sample in t['samples']:
 assert sample['wall_seconds']>=10 and sample['minimum10s_observed']
 assert sample['raw'] in lines and sample['repin_raw'] in lines
p=Path('.autoport/reports/lighting-hdr/proof.txt');assert p.read_bytes()==(n/'proof-portal.txt').read_bytes();kv=dict(line.split('=',1) for line in p.read_text().splitlines() if '=' in line)
assert kv['crash']=='0' and int(kv['frames'])>0
r=j(n/'restoration.json');assert r['original_settings_sha256']==r['restored_settings_sha256']==sha(n/'settings-original.ini')==identity['settings_sha256'];assert r['pids'][0] and r['pids'][0]==r['pids'][1];assert not r['nonempty_debug_props'];assert all(c['rc']==0 for c in r['calls'])
regions={x['arm']:x for x in j(n/'image-region-summary.json') if x['layer']=='portal_disc'}
source=next(x for x in j(b/'owner-regions.json')['regions'] if x.get('layer')=='portal_disc')
for arm,row in regions.items():
 samples=[s['stats'] for s in source['samples'] if s['arm']==arm]
 assert row['samples']==len(samples)==2
 for k,value in row['mean'].items():assert abs(value-statistics.mean(s[k] for s in samples))<1e-8
print(json.dumps({'sealed_hashes':len(m['files']),'samples':len(t['samples']),'proof':{k:kv[k] for k in ['crash','frames','hdr_tonemap_defects','hdr_owner_regressions_passed','hdr_owner_regressions_missing']},'restored_pid':r['pids'][0],'wait_seconds':[s['wall_seconds'] for s in t['samples']]},indent=2))
