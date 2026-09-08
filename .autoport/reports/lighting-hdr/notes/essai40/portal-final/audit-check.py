from pathlib import Path
import json,hashlib
n=Path(__file__).resolve().parent
b=Path((n/'batch-path.txt').read_text().strip())
def j(p):return json.loads(Path(p).read_text())
def sha(p):
 with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
m=j(b/'manifest.json');bad=[p for p,h in m['files'].items() if sha(b/p)!=h];assert not bad
identity=j(n.parent/'build-final/device-identity.json');assert m['provenance']['binary_sha256']==m['provenance']['installed_sha256']==identity['lib'];assert m['provenance']['apk_sha256']==identity['apk']
t=j(n/'timing-and-witnesses.json');assert t['engine_sha256']==sha(b/'engine.log');assert len(t['samples'])==4
lines=(b/'engine.log').read_text(errors='replace').splitlines()
for sample in t['samples']:
 assert sample['wall_seconds']>=10 and sample['minimum10s_observed']
 assert sample['raw'] in lines and sample['repin_raw'] in lines
alpha=j(n/'alpha-before-after.json');after=[r for r in alpha['runs'] if r['label']=='after'][0];assert sha(after['events_source'])==after['sha256'];assert len(after['groups'])==4
for g in after['groups']:assert g['samples']==2 and g['alpha_max']==1 and g['alpha_above_one']==g['alpha_negative']==0 and g['roi_exclusive']==[147,42,173,79]
p=Path('.autoport/reports/lighting-hdr/proof.txt');assert p.read_bytes()==(n/'proof-portal.txt').read_bytes();kv=dict(line.split('=',1) for line in p.read_text().splitlines() if '=' in line)
for k,v in {'crash':'0','frames':'4560','hdr_tonemap_defects':'4','hdr_owner_regressions_passed':'0','hdr_owner_regressions_missing':'5'}.items():assert kv[k]==v
r=j(n/'restoration.json');assert r['original_settings_sha256']==r['restored_settings_sha256']==sha(n/'settings-original.ini')==identity['settings_sha256'];assert r['pids'][0]==r['pids'][1]=='3726';assert not r['nonempty_debug_props'];assert all(c['rc']==0 for c in r['calls'])
regions={x['arm']:x for x in j(n/'image-region-summary.json') if x['layer']=='portal_disc'}
for arm,luma,nw in [('recharged',102.02234927234927,41.5),('origine-lumiere',127.01611226611226,48.5)]:assert regions[arm]['samples']==2 and abs(regions[arm]['mean']['luma']-luma)<1e-8 and regions[arm]['mean']['nearwhite']==nw
print('PASS sealed_hashes='+str(len(m['files']))+' samples=4 alpha_groups=4 crash=0 frames=4560 defects=4 restored_pid=3726')
print('wait_seconds='+str([s['wall_seconds'] for s in t['samples']]))
