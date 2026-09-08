from pathlib import Path
import subprocess,struct,json,sys,time,re
n=Path(__file__).parent;a=['/home/emeric/Android/platform-tools/adb','-s','eae4df44'];pkg='org.opengoal.gk.jak1'
pid=subprocess.check_output(a+['shell','pidof',pkg]).decode().strip();assert pid.isdigit()
base=0x7f00000000;s7=0x14fd24
maps=subprocess.check_output(a+['exec-out','run-as',pkg,'cat',f'/proc/{pid}/maps']).decode()
assert any(int(m[0],16)<=base and int(m[1],16)>=base+134217728 for m in re.findall(r'^([0-9a-f]+)-([0-9a-f]+)',maps,re.M)), 'EE mapping absent'
def read(off,count):
 assert 0<=off<134217728 and 0<count<=262144 and off+count<=134217728
 p=subprocess.run(a+['exec-out','run-as',pkg,'dd',f'if=/proc/{pid}/mem','bs=1',f'skip={base+off}',f'count={count}'],capture_output=True);p.check_returncode();assert len(p.stdout)>=count;return p.stdout[:count]
def u32(off):return struct.unpack('<I',read(off,4))[0]
info=read(s7-65536+131068,131072)
def sym(name):
 crc=0
 for ch in name.encode():
  x=crc&0xff000000
  for _ in range(8):x=((x<<1)^(0x04c11db7 if x&0x80000000 else 0))&0xffffffff
  crc=x^(((crc<<8)|ch)&0xffffffff)
 crc=(~crc)&0xffffffff
 for i in range(16384):
  h,st=struct.unpack_from('<II',info,i*8)
  if h==crc and read(st+4,len(name)+1)==name.encode()+b'\0':
   addr=s7-65536+i*8;return {'slot':addr,'value':u32(addr),'crc':crc,'verified_name':name}
 raise Exception('symbol absent '+name)
def string(p):
 if not p or p==s7:return None
 length=struct.unpack('<i',read(p,4))[0]
 assert 0<=length<=4096,(p,length)
 return read(p+4,min(length+1,512)).split(b'\0',1)[0].decode(errors='replace')
r={'DIRECTIVES':'v8aed688f73','pid':pid,'wall_time':time.time(),'base':base,'s7':s7,'symbols':{}}
for name in ['*menu-touch*','*progress-process*','*pc-settings*','*options-remap*','*recharged-lighting-label*','*recharged-settings-label*','#t']:
 try:r['symbols'][name]=sym(name)
 except Exception as e:r['symbols'][name]={'error':str(e)}
def val(name):return r['symbols'][name]['value']
b=read(val('*menu-touch*'),512);r['screen']=struct.unpack_from('<q',b,4)[0];cnt=struct.unpack_from('<i',b)[0];assert 0<=cnt<=12
r['rows']=[dict(zip(['idx','oy','cx','cy','half_h'],struct.unpack_from('<h2xffff',b,12+i*32))) for i in range(cnt)]
p=u32(val('*progress-process*'));pb=read(p+124,20);r['progress']=dict(zip(['display','next','option_index'],struct.unpack('<qqi',pb)))
remap=val('*options-remap*');h=struct.unpack('<iiI',read(remap,12));r['remap_header']=h
(n/(sys.argv[1]+'-partial.json')).write_text(json.dumps(r,indent=2))
assert 0<=r['screen']<h[1]<=256,{'screen':r['screen'],'header':h}
arr=u32(remap+12+4*r['screen']);length,alloc,ctype=struct.unpack('<iiI',read(arr,12));assert 0<=length<=alloc<=256
r['options_array']={'ptr':arr,'length':length,'allocated':alloc,'type':ctype};ptrs=struct.unpack('<'+'I'*length,read(arr+12,4*length)) if length else []
r['options']=[]
for idx,p in enumerate(ptrs):
 b=read(p,52);o={'index':idx,'ptr':p,'option_type':struct.unpack_from('<Q',b,4)[0],'name':struct.unpack_from('<I',b,12)[0],'param3':struct.unpack_from('<i',b,28)[0],'value_to_modify':struct.unpack_from('<I',b,32)[0],'name_override':struct.unpack_from('<I',b,40)[0]}
 try:o['label']=string(o['name_override'])
 except Exception as e:o['label_error']=str(e)
 if o['option_type']==2 and o['value_to_modify'] not in [0,s7]:o['current_value']=u32(o['value_to_modify']);o['is_false']=o['current_value']==s7
 r['options'].append(o)
for name in ['*recharged-lighting-label*','*recharged-settings-label*']:
 try:r[name]=string(val(name))
 except Exception as e:r[name]={'error':str(e)}
if '--handles' in sys.argv:
 r['handle_caches']={}
 for kind in ['companion','driver']:
  count_name='*hd-scan-'+kind+'-count*';array_name='*hd-scan-'+kind+'s*'
  try:
   count=sym(count_name);arrsym=sym(array_name);countv=count['value'];assert 0<=countv<=16
   header=None # static array handle is an unboxed pointer, no boxed header
   entries=[]
   if countv:
    buf=read(arrsym['value'],countv*8)
    for i in range(countv):
     pp,handle_pid=struct.unpack_from('<II',buf,i*8);e={'index':i,'ppointer':pp,'handle_pid':handle_pid}
     if pp not in [0,s7] and pp<134217724:
      proc=u32(pp);e['process']=proc
      if proc not in [0,s7] and proc<134217680:e['current_pid']=u32(proc+36);e['pid_matches']=e['current_pid']==handle_pid
     entries.append(e)
   r['handle_caches'][kind]={'count_symbol':count,'array_symbol':arrsym,'header':header,'entries':entries}
  except Exception as e:r['handle_caches'][kind]={'error':str(e)}
assert subprocess.check_output(a+['shell','pidof',pkg]).decode().strip()==pid,'PID changed'
(n/(sys.argv[1]+'.json')).write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
