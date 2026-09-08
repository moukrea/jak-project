from pathlib import Path
import subprocess,os,atexit,signal,time,json,hashlib
n=Path(__file__).resolve().parent;root=n.parents[5];os.chdir(root);a=['/home/emeric/Android/platform-tools/adb','-s','eae4df44'];pkg='org.opengoal.gk.jak1';settings='/storage/emulated/0/OpenGOAL/jak1/settings.ini';lock=Path('.autoport/.deploy-in-progress')
fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o644)
with os.fdopen(fd,'w') as f:f.write(f'{__file__} pid={os.getpid()}\n')
atexit.register(lambda:lock.unlink(missing_ok=True))
def stop(*a):raise SystemExit(1)
signal.signal(signal.SIGINT,stop);signal.signal(signal.SIGTERM,stop)
calls=[]
def run(args,check=True):
 p=subprocess.run(args,capture_output=True,text=True,timeout=45);calls.append({'args':args,'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr});(n/'finish-deploy-calls.json').write_text(json.dumps(calls,indent=2))
 if check:p.check_returncode()
 return p
assert run(['bash','.autoport/lib/pick_device.sh']).stdout.strip()=='eae4df44'
identity=json.loads((n/'repack-identity.json').read_text());expected=json.loads((n/'apk-cgo-hashes.json').read_text());paths=['files/cgo/jak1/'+x for x in expected]
deadline=time.monotonic()+120
while True:
 p=run(a+['shell','run-as',pkg,'sha256sum']+paths,False)
 got={Path(l.split()[1]).name:l.split()[0] for l in p.stdout.splitlines() if len(l.split())==2}
 if p.returncode==0 and got==expected:break
 assert time.monotonic()<deadline,{'rc':p.returncode,'got':got}
 time.sleep(3)
(n/'device-cgos.json').write_text(json.dumps({'after':got,'expected':expected},indent=2))
remote=run(a+['shell','pm','path',pkg]).stdout.strip().removeprefix('package:')
assert run(a+['shell','sha256sum',remote]).stdout.split()[0]==identity['apk']
assert run(a+['shell','sha256sum',str(Path(remote).parent/'lib/arm64/libgk.so')]).stdout.split()[0]==identity['lib']
pid1=run(a+['shell','pidof',pkg]).stdout.strip();time.sleep(12);pid2=run(a+['shell','pidof',pkg]).stdout.strip();assert pid1 and pid1==pid2
run(a+['push',str(n/'settings-original.ini'),settings]);settings_sha=hashlib.sha256((n/'settings-original.ini').read_bytes()).hexdigest();assert run(a+['shell','sha256sum',settings]).stdout.split()[0]==settings_sha
identity.update(serial='eae4df44',device_apk=remote,settings_sha256=settings_sha,device_cgos_match_stage=True,stable_pids=[pid1,pid2]);(n/'device-identity.json').write_text(json.dumps(identity,indent=2));print(json.dumps(identity,indent=2))
