from pathlib import Path
import subprocess,time,json,os,shutil,hashlib
n=Path(__file__).resolve().parent
root=n.parents[5];os.chdir(root)
a=['/home/emeric/Android/platform-tools/adb','-s','eae4df44'];pkg='org.opengoal.gk.jak1';settings='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
def adb(*args):
 p=subprocess.run(a+list(args),capture_output=True,timeout=40);p.check_returncode();return p.stdout
assert not Path('.autoport/.deploy-in-progress').exists()
assert subprocess.check_output(['bash','.autoport/lib/pick_device.sh'],env={**os.environ,'ANDROID_SERIAL':'eae4df44'}).strip()==b'eae4df44'
s=adb('exec-out','cat',settings);(n/'settings-before.ini').write_bytes(s)
for prop in ['lighting','rt.light','refset']:
 assert not adb('shell','getprop','debug.opengoal.'+prop).strip()
args=['bash','-c','pkill(){ return 1; }; export -f pkill; exec bash "$@"','_', '.autoport/lib/proof_run.sh','lighting-hdr','device','--timeout','210']
p=None
try:
 with (n/'producer.log').open('x') as log:
  p=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,env={**os.environ,'AUTOPORT_BACKEND':'codex','ANDROID_SERIAL':'eae4df44'})
  deadline=time.monotonic()+90
  while 'appareil eae4df44 :' not in (n/'producer.log').read_text():
   assert p.poll() is None and time.monotonic()<deadline
   time.sleep(.3)
  adb('shell','setprop debug.opengoal.lighting ""')
  adb('shell','setprop debug.opengoal.pbr.shadowdbg 1')
  for prop in ['lighting','rt.light','refset']:
   (n/('prop-'+prop+'.txt')).write_bytes(adb('shell','getprop','debug.opengoal.'+prop))
  (n/'started.txt').write_text(str(time.time()))
  p.wait(timeout=300)
  (n/'exit.txt').write_text(str(p.returncode))
finally:
 if p and p.poll() is None:p.wait(timeout=300)
 for name in ['proof.txt','proof-engine.log']:
  src=Path('.autoport/reports/lighting-hdr')/name
  if src.exists():shutil.copy2(src,n/name)
 (n/'settings-after.ini').write_bytes(adb('exec-out','cat',settings))
 adb('shell','am','force-stop',pkg)
 adb('push',str(n/'settings-before.ini'),settings)
 for prop in ['lighting','rt.light','refset','pbr.shadowdbg']:
  adb('shell','setprop debug.opengoal.'+prop+' ""')
 assert adb('exec-out','cat',settings)==s
 adb('shell','am','start','-n',pkg+'/org.opengoal.gk.LoaderActivity')
 time.sleep(8);pid1=adb('shell','pidof',pkg).strip();time.sleep(12);pid2=adb('shell','pidof',pkg).strip()
 adb('push',str(n/'settings-before.ini'),settings)
 (n/'restoration.json').write_text(json.dumps({'settings_sha256':hashlib.sha256(s).hexdigest(),'pids':[pid1.decode(),pid2.decode()],'stable':bool(pid1 and pid1==pid2),'settings_exact':adb('exec-out','cat',settings)==s},indent=2)+'\n')
