set pagination off
set confirm off
set print elements 0
python
import gdb,re
class Target(gdb.Breakpoint):
 def stop(self):
  c=int(gdb.parse_and_eval('$rdi'))
  def u32(p): return int.from_bytes(gdb.selected_inferior().read_memory(p,4),'little')
  mem=int(gdb.parse_and_eval('*(unsigned long*)0x404050'))
  return u32(c+0x380)==0xff800000 and u32(c+0x140)==64 and u32(c+0x150)==256 and u32(mem+256+96)==0x7fc12345
bp=Target('*0x401780')
gdb.execute('run')
bp.delete()
def trace(label):
 print('TRACE '+label+' sample13 s4=64 s5=256 fade=7fc12345')
 print(gdb.execute('p/x $mxcsr',to_string=True))
 while True:
  pc=int(gdb.parse_and_eval('$pc'))
  ins=gdb.execute('x/i $pc',to_string=True).strip()
  if '\tret' in ins: break
  fp=bool(re.search(r'\bv(?:mul|add|sub)(?:ss|ps)\b',ins))
  if fp:
   print('PRE '+ins)
   regs=list(dict.fromkeys(re.findall(r'%xmm\d+',ins)))
   for r in regs: print(r+' '+gdb.execute('p/x $'+r[1:]+'.v4_int32',to_string=True).strip())
   if '0x20(%rsp)' in ins: print(gdb.execute('x/4wx $rsp+0x20',to_string=True))
   if '0x30(%rsp)' in ins: print(gdb.execute('x/4wx $rsp+0x30',to_string=True))
  gdb.execute('si',to_string=True)
  if fp:
   dest=re.findall(r'%xmm\d+',ins)[-1]
   print('POST '+dest+' '+gdb.execute('p/x $'+dest[1:]+'.v4_int32',to_string=True).strip())
 print('OUTPUT vf11 '+gdb.execute('x/4wx $rdi+0x330',to_string=True))
trace('before')
bp=gdb.Breakpoint('*0x401a70',temporary=True)
gdb.execute('continue')
trace('after')
print('TARGET COMPLETE; quit before remaining campaign')
end
quit
