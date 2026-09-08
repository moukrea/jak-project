from pathlib import Path
import subprocess,os,hashlib,json,atexit,signal,time,zipfile,re,shutil,tempfile
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
files=[Path(p) for p in run(['git','ls-files']).splitlines() if p.startswith(('goal_src/','game/','common/','test/','android/')) and not p.startswith('android/app/src/main/jniLibs/') and Path(p).is_file()]
before={str(p):sha(p) for p in files};(n/'sources-before.json').write_text(json.dumps(before,indent=2))
packpaths=json.loads((root/'.autoport/reports/lighting-hdr/notes/essai39/build/packs-before.json').read_text());packs={p:sha(p) for p in packpaths};(n/'packs-before.json').write_text(json.dumps(packs,indent=2))
public=root/'android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk';public_sha=sha(public)
baseline=root/'.autoport/reports/lighting-hdr/notes/essai43/build/gradle-app/outputs/apk/jak1/debug/app-jak1-debug.apk'
baseline_sha=sha(baseline)
lib=root/'build-android/lib/arm64-v8a/libgk.so'
run(['cmake','--build','build-android','--target','gk','-j3'],'android.log')
(n/'isolate.gradle').write_text("gradle.beforeProject { p -> if (p.path == ':app') { p.layout.buildDirectory.set(new File(System.getenv('ESSAI43_RENDU_GRADLE_APP'))) } }\n")
gradle_app=Path(tempfile.mkdtemp(prefix='essai43-rendu-gradle-',dir='/tmp'))
(n/'gradle-directory.txt').write_text(str(gradle_app)+'\n')
env={**os.environ,'ESSAI43_RENDU_GRADLE_APP':str(gradle_app),'AUTOPORT_BACKEND':'codex','TMPDIR':'/home/emeric/.autoport-tmp'};env['GRADLE_OPTS']=env.get('GRADLE_OPTS','')+' -Djava.io.tmpdir='+env['TMPDIR']
run(['./gradlew','-I',str(n/'isolate.gradle'),'assembleJak1Debug','--no-daemon','-x','configureNativeLibs','-x','buildNativeLibs','-x','bundleJak1CgoPack','-x','bundleJak1CustomPack'],'repack.log',env=env,cwd=root/'android')
built_apk=gradle_app/'outputs/apk/jak1/debug/app-jak1-debug.apk'
apk=n/'app-jak1-debug.apk'
shutil.copy2(built_apk,apk)
with zipfile.ZipFile(apk) as z,zipfile.ZipFile(baseline) as old:
 assert hashlib.sha256(z.read('lib/arm64-v8a/libgk.so')).hexdigest()==sha(lib)
 for entry in z.namelist():
  if entry.startswith('assets/bundle/'):assert z.read(entry)==old.read(entry),entry
assert sha(public)==public_sha
assert sha(baseline)==baseline_sha
assert {p:sha(p) for p in packpaths}==packs
assert {str(p):sha(p) for p in files}==before,'sources changed during build'
identity={'lib':sha(lib),'apk':sha(apk),'packs_unchanged':True,'publisher_unchanged':True};(n/'repack-identity.json').write_text(json.dumps(identity,indent=2))
a=['/home/emeric/Android/platform-tools/adb','-s','eae4df44'];pkg='org.opengoal.gk.jak1';settings='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
assert run(a+['get-state']).strip()=='device'
assert run(['bash','.autoport/lib/pick_device.sh'],env={**os.environ,'ANDROID_SERIAL':'eae4df44','AUTOPORT_BACKEND':'codex'}).strip()=='eae4df44'
original_settings=run(a+['exec-out','cat',settings])
(n/'settings-original.ini').write_text(original_settings)
settings_sha=run(a+['shell','sha256sum',settings]).split()[0]
props_before=run(a+['shell','getprop'])
props_before={k:v for k,v in re.findall(r'^\[(debug\.opengoal\.[^]]+)\]: \[(.*)\]$',props_before,re.M)}
(n/'props-original.json').write_text(json.dumps(props_before,indent=2))
cgo_hashes=json.loads((root/'.autoport/reports/lighting-hdr/notes/essai43/build/apk-cgo-hashes.json').read_text())
cgopaths=['files/cgo/jak1/'+name for name in sorted(cgo_hashes)]
with zipfile.ZipFile(apk) as az:
 import io
 with zipfile.ZipFile(io.BytesIO(az.read('assets/bundle/jak1_cgo.zip'))) as cz:
  assert {name:hashlib.sha256(cz.read(name)).hexdigest() for name in cgo_hashes}==cgo_hashes;cgos_before=run(a+['shell','run-as',pkg,'sha256sum']+cgopaths)
run(a+['shell','am','force-stop',pkg]);run(a+['install','-r',str(apk)])
remote=run(a+['shell','pm','path',pkg]).strip().removeprefix('package:')
assert run(a+['shell','sha256sum',remote]).split()[0]==identity['apk']
assert run(a+['shell','sha256sum',str(Path(remote).parent/'lib/arm64/libgk.so')]).split()[0]==identity['lib']
assert run(a+['shell','sha256sum',settings]).split()[0]==settings_sha
assert run(a+['shell','run-as',pkg,'sha256sum']+cgopaths)==cgos_before
assert {Path(line.split()[1]).name:line.split()[0] for line in cgos_before.splitlines()}==cgo_hashes
identity.update(device_apk=remote,serial='eae4df44',settings_sha256=settings_sha,device_cgos_unchanged=True)
(n/'device-identity.json').write_text(json.dumps(identity,indent=2))
(n/'DIRECTIVES.txt').write_text('DIRECTIVES v3909a9767c\n')
print(json.dumps(identity,indent=2))
