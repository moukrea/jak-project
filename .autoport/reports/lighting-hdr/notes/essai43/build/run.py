from pathlib import Path
import subprocess,os,hashlib,json,atexit,signal,time,zipfile,re
root=Path('/home/emeric/code/jak-project');n=Path(__file__).resolve().parent;os.chdir(root)
def sha(p):
 with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
calls=[]
def run(args,log=None,env=None,cwd=None):
 start=time.monotonic()
 if log:
  with (n/log).open('w') as f:p=subprocess.run(args,stdout=f,stderr=subprocess.STDOUT,env=env,cwd=cwd)
  out=''
 else:
  p=subprocess.run(args,capture_output=True,text=True,env=env,cwd=cwd,timeout=180);out=p.stdout
 calls.append({'args':args,'rc':p.returncode,'seconds':time.monotonic()-start,'log':log,'stdout':out,'stderr':getattr(p,'stderr',None)});(n/'commands.json').write_text(json.dumps(calls,indent=2));p.check_returncode();return out
ps=run(['ps','-eo','pid,ppid,comm,args']);(n/'processes-before.txt').write_text(ps)
for line in ps.splitlines()[1:]:
 f=line.split(None,3)
 if len(f)==4 and (f[2] in ['ninja','ninja-build','cmake','clang++','cc1plus','ld.lld'] or (f[2]=='java' and 'GradleDaemon' in f[3])):raise RuntimeError('concurrent build '+line)
lock=root/'.autoport/.deploy-in-progress'
fd=os.open(lock,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o644)
with os.fdopen(fd,'w') as f:f.write(f'{__file__} pid={os.getpid()}\n')
def release():
 if lock.exists() and f'pid={os.getpid()}\n' in lock.read_text():lock.unlink()
atexit.register(release)
def stop(*a):raise SystemExit(1)
signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
(n/'DIRECTIVES.txt').write_text('DIRECTIVES v8aed688f73\n')
files=[Path(p) for p in run(['git','ls-files']).splitlines() if p.startswith(('goal_src/','game/','common/','test/')) and not p.startswith('android/app/src/main/jniLibs/') and Path(p).is_file()]
before={str(p):sha(p) for p in files};(n/'sources-before.json').write_text(json.dumps(before,indent=2))
packpaths=json.loads((root/'.autoport/reports/lighting-hdr/notes/essai39/build/packs-before.json').read_text());packs={p:sha(p) for p in packpaths};(n/'packs-before.json').write_text(json.dumps(packs,indent=2))
public=root/'android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk';public_sha=sha(public)
lib=root/'build-android/lib/arm64-v8a/libgk.so'
lib_before=sha(lib)
run(['bash','.autoport/build_arm64_full_consistent.sh'],'goal-iso.log',env={**os.environ,'AUTOPORT_BACKEND':'codex'})
assert sha(lib)==lib_before
run(['bash','android/build_cgo_pack.sh','jak1'],'cgo-pack.log',env={**os.environ,'AUTOPORT_BACKEND':'codex'})
(n/'isolate.gradle').write_text("gradle.beforeProject { p -> if (p.path == ':app') { p.layout.buildDirectory.set(new File(System.getenv('ESSAI43_GRADLE_APP'))) } }\n")
env={**os.environ,'ESSAI43_GRADLE_APP':str(n/'gradle-app'),'AUTOPORT_BACKEND':'codex','TMPDIR':'/home/emeric/.autoport-tmp'};env['GRADLE_OPTS']=env.get('GRADLE_OPTS','')+' -Djava.io.tmpdir='+env['TMPDIR']
run(['./gradlew','-I',str(n/'isolate.gradle'),'assembleJak1Debug','--no-daemon','-x','configureNativeLibs','-x','buildNativeLibs','-x','bundleJak1CgoPack','-x','bundleJak1CustomPack'],'repack.log',env=env,cwd=root/'android')
apk=n/'gradle-app/outputs/apk/jak1/debug/app-jak1-debug.apk'
with zipfile.ZipFile(apk) as z,zipfile.ZipFile(public) as old:
 assert hashlib.sha256(z.read('lib/arm64-v8a/libgk.so')).hexdigest()==sha(lib)
 for entry in z.namelist():
  if entry.startswith('assets/bundle/') and 'jak1_cgo' not in entry:assert z.read(entry)==old.read(entry),entry
with zipfile.ZipFile(apk) as az:
 import io
 with zipfile.ZipFile(io.BytesIO(az.read('assets/bundle/jak1_cgo.zip'))) as cz:
  cgo_hashes={name:hashlib.sha256(cz.read(name)).hexdigest() for name in cz.namelist() if name.endswith(('.CGO','.DGO'))}
  assert len(cgo_hashes)==28
  for name,digest in cgo_hashes.items():assert digest==sha(root/'out/jak1-arm64-full/iso'/name)
(n/'apk-cgo-hashes.json').write_text(json.dumps(cgo_hashes,indent=2))
assert sha(public)==public_sha
packs_after={p:sha(p) for p in packpaths}
(n/'packs-after.json').write_text(json.dumps(packs_after,indent=2))
assert {str(p):sha(p) for p in files}==before,'sources changed during build'
identity={'lib':sha(lib),'apk':sha(apk),'changed_packs':[p for p in packs if packs[p]!=packs_after[p]],'publisher_unchanged':True};(n/'repack-identity.json').write_text(json.dumps(identity,indent=2))
a=['/home/emeric/Android/platform-tools/adb','-s','eae4df44'];pkg='org.opengoal.gk.jak1';settings='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
assert run(a+['get-state']).strip()=='device'
assert run(['bash','.autoport/lib/pick_device.sh'],env={**os.environ,'ANDROID_SERIAL':'eae4df44','AUTOPORT_BACKEND':'codex'}).strip()=='eae4df44'
settings_original=run(a+['exec-out','cat',settings])
(n/'settings-original.ini').write_text(settings_original)
settings_sha=run(a+['shell','sha256sum',settings]).split()[0]
cgopaths=[f'files/cgo/jak1/{x}.CGO' for x in ['GAME','ENGINE','KERNEL']];cgos_before=run(a+['shell','run-as',pkg,'sha256sum']+cgopaths)
run(a+['shell','am','force-stop',pkg]);run(a+['install','-r',str(apk)])
remote=run(a+['shell','pm','path',pkg]).strip().removeprefix('package:')
assert run(a+['shell','sha256sum',remote]).split()[0]==identity['apk']
assert run(a+['shell','sha256sum',str(Path(remote).parent/'lib/arm64/libgk.so')]).split()[0]==identity['lib']
assert run(a+['shell','sha256sum',settings]).split()[0]==settings_sha
run(a+['shell','am','start','-n',pkg+'/org.opengoal.gk.LoaderActivity'])
expected={Path(p).name:sha(root/'out/jak1-arm64-full/iso'/Path(p).name) for p in cgopaths}
deadline=time.monotonic()+120
while True:
 observed=run(a+['shell','run-as',pkg,'sha256sum']+cgopaths)
 got={Path(line.split()[1]).name:line.split()[0] for line in observed.splitlines()}
 if got==expected:break
 assert time.monotonic()<deadline,{'expected':expected,'got':got}
 time.sleep(2)
(n/'device-cgos.json').write_text(json.dumps({'before':cgos_before,'after':got,'expected':expected},indent=2))
time.sleep(8)
pid1=run(a+['shell','pidof',pkg]).strip()
time.sleep(12)
pid2=run(a+['shell','pidof',pkg]).strip()
assert pid1 and pid1==pid2
run(a+['push',str(n/'settings-original.ini'),settings])
assert run(a+['shell','sha256sum',settings]).split()[0]==settings_sha
identity.update(device_apk=remote,serial='eae4df44',settings_sha256=settings_sha,device_cgos_match_stage=True,stable_pids=[pid1,pid2])
(n/'device-identity.json').write_text(json.dumps(identity,indent=2));print(json.dumps(identity,indent=2))
