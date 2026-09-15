set pagination off
set confirm off
set debuginfod enabled off
set architecture aarch64
set sysroot /usr/aarch64-linux-gnu
target remote :12348
python
import gdb,re
class Target(gdb.Breakpoint):
 def stop(self):
  c=int(gdb.parse_and_eval('$x0'))
  def u32(p): return int.from_bytes(gdb.selected_inferior().read_memory(p,4),'little')
  mem=int(gdb.parse_and_eval('*(unsigned long*)0x420060'))
  return u32(c+0x380)==0xff800000 and u32(c+0x140)==64 and u32(c+0x150)==256 and u32(mem+256+96)==0x7fc12345
bp=Target('*0x4012e0')
gdb.execute('continue')
bp.delete()
def trace(label):
 c=int(gdb.parse_and_eval('$x0'))
 print('TRACE '+label+' sample13 s4=64 s5=256 fade=7fc12345')
 print(gdb.execute('p/x $fpcr',to_string=True))
 while True:
  ins=gdb.execute('x/i $pc',to_string=True).strip()
  if re.search(r'\bret\b',ins): break
  fp=bool(re.search(r'\bf(?:mul|add|sub)\b',ins))
  if fp:
   print('PRE '+ins)
   regs=list(dict.fromkeys(re.findall(r'\b[sv](\d+)',ins)))
   for r in regs: print('v'+r+' '+gdb.execute('p/x $v'+r+'.s.u',to_string=True).strip())
  gdb.execute('si',to_string=True)
  if fp:
   dest=re.findall(r'\b[sv](\d+)',ins)[0]
   print('POST v'+dest+' '+gdb.execute('p/x $v'+dest+'.s.u',to_string=True).strip())
 print('OUTPUT vf11 '+gdb.execute('x/4wx '+hex(c+0x330),to_string=True))
trace('before')
bp=gdb.Breakpoint('*0x401500',temporary=True)
gdb.execute('continue')
trace('after')
print('TARGET COMPLETE; kill emulator before remaining campaign')
end
kill
quit
