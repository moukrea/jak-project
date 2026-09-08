from pathlib import Path
import subprocess,struct,json,sys,time
n=Path(__file__).parent;a=['/home/emeric/Android/platform-tools/adb','-s','eae4df44'];pkg='org.opengoal.gk.jak1';pid=subprocess.check_output(a+['shell','pidof',pkg]).decode().strip();base=0x7f00000000;s7=0x14fd24
# Read-only debugger snapshots of the existing menu, no writes to GOAL memory.
def read(off,count):
 p=subprocess.run(a+['exec-out','run-as',pkg,'dd',f'if=/proc/{pid}/mem','bs=1',f'skip={base+off}',f'count={count}'],capture_output=True);p.check_returncode();assert len(p.stdout)>=count;return p.stdout[:count]
def sym(name):
 crc=0
 for ch in name.encode():
  x=crc&0xff000000
  for _ in range(8):x=((x<<1)^(0x04c11db7 if x&0x80000000 else 0))&0xffffffff
  crc=x^(((crc<<8)|ch)&0xffffffff)
 crc=(~crc)&0xffffffff;h=crc&8191;h=h-8192 if h&4096 else h;start=s7+h*8
 data=read(start+131068,512)
 for i in range(64):
  hash_,string=struct.unpack_from('<II',data,i*8)
  if hash_==crc and read(string+4,len(name)+1)==name.encode()+b'\0':
   addr=start+i*8;return addr,struct.unpack('<I',read(addr,4))[0]
 raise Exception(name)
r={'pid':pid,'wall_time':time.time(),'symbols':{}}
for name in ['*menu-touch*','*progress-process*','*pc-settings*']:
 slot,val=sym(name);r['symbols'][name]={'slot':slot,'value':val}
 if name=='*menu-touch*' and val and val!=s7:
  b=read(val,512);(n/'menu-memory.bin').write_bytes(b);r['menu_words']=struct.unpack('<128I',b)
print(json.dumps(r,indent=2));(n/(sys.argv[1]+'.json')).write_text(json.dumps(r,indent=2)+'\n')
