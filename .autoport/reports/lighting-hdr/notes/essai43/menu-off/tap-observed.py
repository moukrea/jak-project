from pathlib import Path
import json,sys,subprocess,time
n=Path(__file__).parent;a=json.loads((n/(sys.argv[1]+'.json')).read_text());b=json.loads((n/(sys.argv[2]+'.json')).read_text());target=int(sys.argv[3])
assert a['pid']==b['pid'] and a['screen']==b['screen'] and a['rows']==b['rows'] and a['options']==b['options']
row=next(x for x in b['rows'] if x['idx']==target);option=next(x for x in b['options'] if x['index']==target)
assert b['progress']['display']==b['progress']['next']==b['screen']
x,y=round(row['cx']*2400),round(row['cy']*1080)
cmd=['/home/emeric/Android/platform-tools/adb','-s','eae4df44','shell','input','tap',str(x),str(y)]
p=subprocess.run(cmd,capture_output=True,text=True);p.check_returncode()
with (n/'observed-actions.jsonl').open('a') as f:f.write(json.dumps({'time':time.time(),'before':[sys.argv[1],sys.argv[2]],'page':b['screen'],'row':row,'option':option,'geometry_source':'runtime CINEVP draw2400x1080+0+0','args':cmd,'rc':p.returncode})+'\n')
