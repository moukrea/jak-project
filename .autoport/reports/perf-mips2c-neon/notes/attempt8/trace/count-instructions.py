import pathlib,json,re,collections
out=pathlib.Path('.autoport/reports/perf-mips2c-neon/notes/attempt8'); p=out/'tested-manifest.json'; m=json.loads(p.read_text())
for name,j in m['jobs'].items():
 if not name.startswith('object-'):continue
 _,variant,arch=name.split('-'); prefix=out/f'tested-{variant}-{arch}'
 text=pathlib.Path(str(prefix)+'-full.asm').read_text(); nm=pathlib.Path(str(prefix)+'-nm.txt').read_text()
 for dim,s in j['symbols'].items():
  match=re.search(r'^([0-9a-f]+) ([0-9a-f]+) T '+s['symbol']+'$',nm,re.M); start,size=[int(x,16) for x in match.groups()]
  head=re.search(r'^[0-9a-f]+ <Mips2C::jak1::sp_process_block_'+dim+r'::execute\(void\*\)>:\n',text,re.M)
  body=text[head.end():]; nexthead=re.search(r'^\s*[0-9a-f]+ <',body,re.M)
  if nexthead:body=body[:nexthead.start()]
  ins=[]
  for l in body.splitlines():
   fields=l.split('\t')
   if len(fields)<3:continue
   address=re.match(r'\s*([0-9a-f]+):',fields[0]); mnemonic=fields[2].strip().split()
   if address and start<=int(address[1],16)<start+size and mnemonic:ins.append(mnemonic[0])
  s.update(instruction_count=len(ins),mnemonic_histogram=dict(sorted(collections.Counter(ins).items())))
  print(name,dim,size,len(ins))
m['instruction_count_method']='objdump instruction rows within nm [start,start+size); includes operandless ret; excludes padding outside symbol'
p.write_text(json.dumps(m,indent=2)+'\n')
