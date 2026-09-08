from pathlib import Path
import subprocess,time,json,os,shutil,hashlib,re,shlex
n=Path(__file__).resolve().parent;root=n.parents[5];os.chdir(root)
a=['/home/emeric/Android/platform-tools/adb','-s','eae4df44'];pkg='org.opengoal.gk.jak1';settings='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
def adb(*args):
 p=subprocess.run(a+list(args),capture_output=True,timeout=40);p.check_returncode();return p.stdout
assert not Path('.autoport/.deploy-in-progress').exists()
assert subprocess.check_output(['bash','.autoport/lib/pick_device.sh'],env={**os.environ,'ANDROID_SERIAL':'eae4df44','ADB':str(n/'adb-before-boot.py')}).strip()==b'eae4df44'
props=dict(re.findall(r'^\[(debug\.opengoal\.[^]]+)\]: \[(.*)\]$',adb('shell','getprop').decode(),re.M));(n/'props-before.json').write_text(json.dumps(props,indent=2))
s=adb('exec-out','cat',settings);(n/'settings-before.ini').write_bytes(s)
assert b'recharged-lighting? = #t' in s
args=['bash','-c','pkill(){ return 1; }; export -f pkill; exec bash "$@"','_', '.autoport/lib/proof_run.sh','lighting-hdr','device','--timeout','300']
env={**os.environ,'AUTOPORT_BACKEND':'codex','ANDROID_SERIAL':'eae4df44','ADB':str(n/'adb-before-boot.py')}
p=None
try:
 (n/'command.json').write_text(json.dumps(args,indent=2))
 with (n/'producer.log').open('x') as log:
  p=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,env=env)
  (n/'producer-pid.txt').write_text(str(p.pid))
  p.wait(timeout=420)
 (n/'exit.txt').write_text(str(p.returncode))
 for name in ['proof.txt','proof-engine.log']:
  src=Path('.autoport/reports/lighting-hdr')/name
  if src.exists():shutil.copy2(src,n/name)
 (n/'official-complete.txt').write_text(str(time.time()))
 deadline=time.monotonic()+180
 while not (n/'navigation-done.json').exists() and time.monotonic()<deadline:time.sleep(.5)
 nav=json.loads((n/'navigation-done.json').read_text()) if (n/'navigation-done.json').exists() else {'off':False,'reason':'navigation timeout'}
 off=adb('exec-out','cat',settings);(n/'settings-after-menu.ini').write_bytes(off)
 if nav.get('off') and b'recharged-lighting? = #f' in off:
  pn=n.parent/'persist-off';pn.mkdir(exist_ok=True);(pn/'settings-before.ini').write_bytes(off)
  pargs=args[:-1]+['60'];(pn/'command.json').write_text(json.dumps(pargs,indent=2))
  with (pn/'producer.log').open('x') as log:p=subprocess.Popen(pargs,stdout=log,stderr=subprocess.STDOUT,env=env);p.wait(timeout=180)
  (pn/'exit.txt').write_text(str(p.returncode))
  for name in ['proof.txt','proof-engine.log']:
   src=Path('.autoport/reports/lighting-hdr')/name
   if src.exists():shutil.copy2(src,pn/name)
  after=adb('exec-out','cat',settings);(pn/'settings-after.ini').write_bytes(after)
  (pn/'persistence.json').write_text(json.dumps({'lighting_off':b'recharged-lighting? = #f' in after,'before_sha256':hashlib.sha256(off).hexdigest(),'after_sha256':hashlib.sha256(after).hexdigest()},indent=2))
 else:(n/'persistence-not-run.json').write_text(json.dumps(nav,indent=2))
finally:
 if p and p.poll() is None:p.wait(timeout=560)
 adb('shell','am','force-stop',pkg);adb('push',str(n/'settings-before.ini'),settings)
 for prop in dict(re.findall(r'^\[(debug\.opengoal\.[^]]+)\]: \[(.*)\]$',adb('shell','getprop').decode(),re.M)):adb('shell','setprop '+prop+' ""')
 for key,value in props.items():adb('shell','setprop '+key+' '+shlex.quote(value))
 assert adb('exec-out','cat',settings)==s
 adb('shell','am','start','-n',pkg+'/org.opengoal.gk.LoaderActivity')
 time.sleep(8);pid1=adb('shell','pidof',pkg).strip();time.sleep(12);pid2=adb('shell','pidof',pkg).strip()
 adb('push',str(n/'settings-before.ini'),settings)
 finalprops=dict(re.findall(r'^\[(debug\.opengoal\.[^]]+)\]: \[(.*)\]$',adb('shell','getprop').decode(),re.M))
 assert {k:v for k,v in props.items() if v}=={k:v for k,v in finalprops.items() if v}
 (n/'restoration.json').write_text(json.dumps({'DIRECTIVES':'v8aed688f73','settings_sha256':hashlib.sha256(s).hexdigest(),'pids':[pid1.decode(),pid2.decode()],'stable':bool(pid1 and pid1==pid2),'settings_exact':adb('exec-out','cat',settings)==s,'props_nonempty_restored':True},indent=2)+'\n')
