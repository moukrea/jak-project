from pathlib import Path
import subprocess,hashlib,zipfile,json,os,shutil,re,io,time
root=Path('/home/emeric/code/jak-project');os.chdir(root)
n=root/'.autoport/reports/lighting-hdr/notes/essai36/menu-build'
log=open(n/'build-deploy.log','x',buffering=1)
def run(args,**kw):
 print('$ '+' '.join(map(str,args)),file=log,flush=True)
 r=subprocess.run(list(map(str,args)),stdout=log,stderr=subprocess.STDOUT,**kw)
 print('exit='+str(r.returncode),file=log,flush=True);r.check_returncode();return r
def out(args):
 r=subprocess.run(list(map(str,args)),capture_output=True,check=True);print('$ '+' '.join(map(str,args))+'\n'+r.stdout.decode(errors='replace'),file=log,flush=True);return r.stdout
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
a=['/home/emeric/Android/platform-tools/adb','-s','eae4df44'];pkg='org.opengoal.gk.jak1'
lock=root/'.autoport/.deploy-in-progress'
if lock.exists():
 m=re.search(r'pid=(\d+)',lock.read_text());assert m,'lock without PID'
 try:os.kill(int(m[1]),0)
 except ProcessLookupError:lock.unlink()
 else:raise RuntimeError('live lock '+m[1])
for l in out(['ps','-eo','pid,comm,args']).decode().splitlines():
 f=l.split(None,2)
 if len(f)==3 and (f[1] in ['goalc','cmake','ninja','cc1plus','clang++','gk'] or (f[1]=='java' and 'GradleDaemon' in f[2])):raise RuntimeError('busy '+l)
backup=n/'before';backup.mkdir(exist_ok=False)
iso=root/'out/jak1/iso';obj=root/'out/jak1/obj';stage=root/'out/jak1-arm64-full/iso'
apk=root/'android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk';lib=root/'build-android/lib/arm64-v8a/libgk.so'
pack=root/'android/app/src/jak1/assets-slim/bundle/jak1_cgo.zip';manifest=pack.with_name('jak1_cgo.manifest.properties')
sources=[root/'goal_src/jak1/pc/hud-classes-pc.gc',root/'goal_src/jak1/pc/progress-pc.gc',root/'goal_src/jak1/pc/pckernel.gc']
seals={str(p.relative_to(root)):sha(p) for p in sources};(n/'source-sha256.json').write_text(json.dumps(seals,indent=2)+'\n')
oldlib=sha(lib);assert oldlib=='dbc383605d0125ed543accfca9f8f471ecbee83839edf76e8492026700fef8b5'
restore_ready=False
settings_path='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
assert out(a+['get-state']).strip()==b'device'
settings=out(a+['exec-out','cat',settings_path]);(n/'settings-original.ini').write_bytes(settings)
started=time.monotonic()
try:
 lock.write_text(f'{__file__} pid={os.getpid()}\n')
 assert b'arm64' in out(['build-arm64/goalc/goalc','--version'])
 assert b'x86' in out(['build/goalc/goalc','--version'])
 marker=b'ogflags:435df2141670:android-arm64'
 assert marker in (root/'goal_src/jak1/pc/recharged-flags.gc').read_bytes() and marker in lib.read_bytes() and marker in (stage/'GAME.CGO').read_bytes()
 for src,name in [(iso,'iso-x86'),(obj,'obj-x86'),(stage,'iso-arm64')]:run(['cp','-a','--reflink=auto',src,backup/name])
 for src in [apk,pack,manifest]:shutil.copy2(src,backup/src.name)
 restore_ready=True
 for p in obj.iterdir():
  if p.is_file() and p.suffix in ['.o','.go']:p.unlink()
 run(['build-arm64/goalc/goalc','--user-auto','--game','jak1','--disable-ansi','-c','(make-group "iso" :force #t)'],timeout=1800)
 files=sorted(list(iso.glob('*.CGO'))+list(iso.glob('*.DGO')));assert len(files)==28,len(files)
 assert sha(iso/'KERNEL.CGO')!=sha(backup/'iso-x86/KERNEL.CGO')
 assert marker in (iso/'GAME.CGO').read_bytes() and marker in (iso/'ENGINE.CGO').read_bytes()
 for p in files:shutil.copy2(p,stage/p.name)
 changes={name:{'before':sha(backup/'iso-arm64'/name),'after':sha(stage/name)} for name in ['GAME.CGO','ENGINE.CGO']}
 (n/'cgo-changes.json').write_text(json.dumps(changes,indent=2)+'\n')
 (n/'arm64-sha256.json').write_text(json.dumps({p.name:sha(p) for p in stage.iterdir() if p.suffix in ['.CGO','.DGO']},indent=2)+'\n')
 run(['cp','-a',str(backup/'iso-x86')+'/.',iso])
 for p in obj.iterdir():
  if p.is_file() and p.suffix in ['.o','.go']:p.unlink()
 run(['cp','-a',str(backup/'obj-x86')+'/.',obj]);restore_ready=False
 assert sha(iso/'KERNEL.CGO')==sha(backup/'iso-x86/KERNEL.CGO')
 run(['./gradlew','assembleJak1Debug','--no-daemon','-x','configureNativeLibs','-x','buildNativeLibs','-x','bundleJak1CustomPack'],cwd=root/'android',timeout=900)
 assert sha(lib)==oldlib
 with zipfile.ZipFile(apk) as z:
  assert hashlib.sha256(z.read('lib/arm64-v8a/libgk.so')).hexdigest()==oldlib
  apkpack=z.read('assets/bundle/jak1_cgo.zip');assert hashlib.sha256(apkpack).hexdigest()==sha(pack)
  with zipfile.ZipFile(io.BytesIO(apkpack)) as cg:
   for name in ['GAME.CGO','ENGINE.CGO']:assert hashlib.sha256(cg.read(name)).hexdigest()==sha(stage/name)
 assert all(sha(root/p)==h for p,h in seals.items())
 assert out(a+['get-state']).strip()==b'device'
 assert out(['env','ANDROID_SERIAL=eae4df44','bash','.autoport/lib/pick_device.sh']).strip()==b'eae4df44'
 run(a+['install','-r',str(apk)],timeout=120)
 run(a+['shell','am','force-stop',pkg])
 run(a+['shell','am','start','-n',pkg+'/org.opengoal.gk.LoaderActivity'])
 print('DELIVERY_STARTED_WAITING_FOR_UNPACK',file=log,flush=True)
 version=re.search(r'^version=(.+)$',manifest.read_text(),re.M)[1]
 for attempt in range(12):
  time.sleep(5)
  stamp=subprocess.run(a+['exec-out','run-as',pkg,'cat','files/.cgo_pack_stamp_jak1'],capture_output=True).stdout.decode().strip()
  if stamp==version:break
 assert stamp==version,(stamp,version)
 devapk=out(a+['shell','pm','path',pkg]).decode().strip().removeprefix('package:')
 identity={'DIRECTIVES':'ve7fcbe0116','lib_sha256':sha(lib),'apk_sha256':sha(apk),'pack_version':version,'pack_sha256':sha(pack),'sources':seals,'settings_sha256':hashlib.sha256(settings).hexdigest(),'duration_s':round(time.monotonic()-started,3),'cgos':{}}
 assert out(a+['shell','sha256sum',devapk]).decode().split()[0]==sha(apk)
 assert out(a+['shell','sha256sum',str(Path(devapk).parent/'lib/arm64/libgk.so')]).decode().split()[0]==oldlib
 for name in ['GAME.CGO','ENGINE.CGO']:
  expected=sha(stage/name);actual=out(a+['exec-out','run-as',pkg,'sha256sum','files/cgo/jak1/'+name]).decode().split()[0];assert expected==actual
  identity['cgos'][name]={'stage':expected,'device':actual,'before':sha(backup/'iso-arm64'/name)}
 (n/'delivery-identity.json').write_text(json.dumps(identity,indent=2)+'\n')
 print('DELIVERY_IDENTITY_OK\n'+json.dumps(identity,indent=2),file=log,flush=True)
finally:
 if restore_ready:
  run(['cp','-a',str(backup/'iso-x86')+'/.',iso])
  for p in obj.iterdir():
   if p.is_file() and p.suffix in ['.o','.go']:p.unlink()
  run(['cp','-a',str(backup/'obj-x86')+'/.',obj])
 if lock.exists() and f'pid={os.getpid()}' in lock.read_text():lock.unlink()
 current=out(a+['exec-out','cat',settings_path])
 if current!=settings:run(a+['push',n/'settings-original.ini',settings_path])
 assert out(a+['exec-out','cat',settings_path])==settings
 (n/'elapsed.txt').write_text(str(round(time.monotonic()-started,3))+'\n')
 log.close()
