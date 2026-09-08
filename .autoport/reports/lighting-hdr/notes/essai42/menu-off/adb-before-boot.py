#!/usr/bin/env python3
import sys,subprocess,json,time,os
from pathlib import Path
real='/home/emeric/Android/platform-tools/adb'
a=sys.argv[1:]
if len(a)<2 or a[:2]!=['-s','eae4df44']:
 raise SystemExit('Only explicit Redmi serial is authorized')
if a[2:6]==['shell','am','start','-n']:
 r={"wall_time":time.time(),"command":a,"properties":{}}
 for name in ['padreplay','lighting','rt.light','level.warp','refset','recharged','hdr']:
  key='debug.opengoal.'+name
  subprocess.run([real,'-s','eae4df44','shell','setprop '+key+' ""'],check=True)
  value=subprocess.check_output([real,'-s','eae4df44','shell','getprop',key]).decode().strip()
  r['properties'][key]=value
  assert not value
 subprocess.run([real,'-s','eae4df44','shell','setprop debug.opengoal.pbr.shadowdbg 1'],check=True)
 with (Path(__file__).parent/'before-boot.jsonl').open('a') as f:f.write(json.dumps(r)+'\n')
os.execv(real,[real]+a)
