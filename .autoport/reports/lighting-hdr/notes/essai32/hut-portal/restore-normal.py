from pathlib import Path
import subprocess,json,time
n=Path('.autoport/reports/lighting-hdr/notes/essai32/hut-portal');calls=[]
def adb(*args):
 r=subprocess.run(['/home/emeric/Android/platform-tools/adb','-s','eae4df44',*args],text=True,capture_output=True,timeout=30)
 calls.append({'args':args,'rc':r.returncode,'stdout':r.stdout,'stderr':r.stderr});assert r.returncode==0;return r.stdout.strip()
def props_check():
 props=adb('shell','getprop');nonempty=[l for l in props.splitlines() if l.startswith('[debug.opengoal.') and not l.endswith(': []')];assert not nonempty,nonempty;return nonempty
props_check();adb('shell','am','force-stop','org.opengoal.gk.jak1');adb('shell','am','start','-n','org.opengoal.gk.jak1/org.opengoal.gk.LoaderActivity');time.sleep(8);p1=adb('shell','pidof','org.opengoal.gk.jak1');time.sleep(12);p2=adb('shell','pidof','org.opengoal.gk.jak1');apk=adb('shell','pm','path','org.opengoal.gk.jak1').removeprefix('package:');sha=adb('shell','sha256sum',str(Path(apk).parent/'lib/arm64/libgk.so'));assert p1 and p1==p2;assert sha.split()[0]==__import__('hashlib').sha256(Path('build-android/lib/arm64-v8a/libgk.so').read_bytes()).hexdigest();assert not Path('.autoport/.deploy-in-progress').exists();nonempty=props_check()
out={'DIRECTIVES':'ve7fcbe0116','pids':[p1,p2],'stable_seconds':12,'sha256sum':sha,'nonempty_debug_props':nonempty,'lock_absent':True,'calls':calls};(n/'normal-restoration.json').write_text(json.dumps(out,indent=2)+'\n');print({k:v for k,v in out.items() if k!='calls'})
