from pathlib import Path
import subprocess,hashlib,time,json,os,re,shutil
root=Path('/home/emeric/code/jak-project');os.chdir(root)
n=root/'.autoport/reports/lighting-hdr/notes/essai36/menu-proof';events=[];a=['/home/emeric/Android/platform-tools/adb','-s','eae4df44'];pkg='org.opengoal.gk.jak1';t0=time.monotonic()
def adb(*args):
 r=subprocess.run(a+list(args),capture_output=True,timeout=30);events.append({'seconds':round(time.monotonic()-t0,3),'args':args,'rc':r.returncode,'stdout':r.stdout.decode(errors='replace'),'stderr':r.stderr.decode(errors='replace')});(n/'events.json').write_text(json.dumps(events,indent=2)+'\n');r.check_returncode();return r.stdout
def props(label):
 v=adb('shell','getprop');(n/('props-'+label+'.txt')).write_bytes(v);assert not re.search(rb'^\[debug.opengoal.rt.light\]: \[(?!\])',v,re.M)
assert adb('get-state').strip()==b'device'
assert subprocess.check_output(['bash','.autoport/lib/pick_device.sh'],env={**os.environ,'ANDROID_SERIAL':'eae4df44'}).strip()==b'eae4df44'
assert not Path('.autoport/.deploy-in-progress').exists()
assert Path('.autoport/reports/lighting-hdr/notes/essai36/menu-build/delivery-identity.json').exists()
settings_path=adb('exec-out','run-as',pkg,'cat','files/asset_root.txt').decode().strip()+'/settings.ini'
settings=adb('exec-out','cat',settings_path);(n/'settings-start.ini').write_bytes(settings);assert b'pbr-materials? = #f' in settings
props('before')
for name in ['proof.txt','proof-engine.log']:
 src=root/'.autoport/reports/lighting-hdr'/name
 if src.exists():shutil.copy2(src,n/('previous-'+name))
command='''pkill(){ printf '%s\\n' 'DIRECTIVES: fallback kill par motif omis; nettoyage PID conservé' >&2; return 1; }; export -f pkill; export AUTOPORT_BACKEND=codex ANDROID_SERIAL=eae4df44; bash .autoport/lib/proof_run.sh lighting-hdr device --timeout 48'''
(n/'command.txt').write_text(command+'\n')
failure=None
rc=None
try:
 with open(n/'producer.log','xb') as log:
  p=subprocess.Popen(['bash','-c',command],stdout=log,stderr=subprocess.STDOUT)
  try:
   deadline=time.monotonic()+90
   while b'appareil eae4df44 :' not in (n/'producer.log').read_bytes():
    assert p.poll() is None,'producer ended before start';assert time.monotonic()<deadline,'start timeout';time.sleep(.3)
   started=time.monotonic()
   adb('shell','setprop','debug.opengoal.lighting','""')
   adb('shell','setprop','debug.opengoal.pbr.shadowdbg','1')
   props('normal-start')
   while time.monotonic()-started<28 and p.poll() is None:time.sleep(.5)
   assert p.poll() is None,'producer ended before OFF'
   adb('shell','setprop','debug.opengoal.lighting','0');props('override-off')
   time.sleep(8)
   adb('shell','setprop','debug.opengoal.lighting','""');props('normal-restored')
   rc=p.wait(timeout=120);(n/'exit.txt').write_text(str(rc)+'\n')
  finally:
   if p.poll() is None:
    p.wait(timeout=120)
except Exception as exc:
 failure=exc
 (n/'failure.txt').write_text(repr(exc)+'\n')
for name in ['proof.txt','proof-engine.log']:
 src=root/'.autoport/reports/lighting-hdr'/name
 if src.exists():shutil.copy2(src,n/name)
props('after-proof')
assert not [l for l in (n/'props-after-proof.txt').read_text().splitlines() if l.startswith('[debug.opengoal.') and not l.endswith(': []')]
end=adb('exec-out','cat',settings_path);(n/'settings-end.ini').write_bytes(end);assert settings==end
adb('shell','am','force-stop',pkg);adb('shell','am','start','-n',pkg+'/org.opengoal.gk.LoaderActivity');time.sleep(8);p1=adb('shell','pidof',pkg).decode().strip();time.sleep(12);p2=adb('shell','pidof',pkg).decode().strip();assert p1 and p1==p2
props('normal-final');assert not Path('.autoport/.deploy-in-progress').exists()
(n/'normal-restoration.json').write_text(json.dumps({'DIRECTIVES':'ve7fcbe0116','pids':[p1,p2],'stable_seconds':12,'settings_sha256':hashlib.sha256(end).hexdigest(),'settings_unchanged':True,'lock_absent':True,'producer_exit':rc},indent=2)+'\n')
print('proof + restoration complete',rc,p1,p2)

if failure is not None:raise failure
