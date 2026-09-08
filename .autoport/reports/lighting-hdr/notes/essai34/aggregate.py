from pathlib import Path
import json,hashlib,shutil
n=Path(__file__).parent;root=Path('.autoport/reports/lighting-hdr/batches');out={'DIRECTIVES':'ve7fcbe0116','method':'byte-identical copies of official producer batches; original directories preserved; no replacement','batches':[]}
for campaign in ['essai34-sky-restored','essai34-portal-restored']:
 batches=list((root/campaign).glob('*/manifest.json'));assert len(batches)==1
 src=batches[0].parent;dst=root/'essai34-restored-compatible'/src.name;assert not dst.exists()
 m=json.loads((src/'manifest.json').read_text())
 for f,h in m['files'].items():assert hashlib.sha256((src/f).read_bytes()).hexdigest()==h,(src,f)
 shutil.copytree(src,dst)
 hashes={}
 for f in src.rglob('*'):
  if f.is_file():
   rel=f.relative_to(src);assert f.read_bytes()==(dst/rel).read_bytes();hashes[str(rel)]=hashlib.sha256(f.read_bytes()).hexdigest()
 out['batches'].append({'original':str(src),'copy':str(dst),'manifest_sha256':hashes['manifest.json'],'sealed_files':len(m['files']),'all_copied_files_sha256':hashes})
(n/'aggregate-lineage.json').write_text(json.dumps(out,indent=2)+'\n')
print(out['batches'][-1]['copy'])
