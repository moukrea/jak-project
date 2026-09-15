import pathlib,subprocess,shlex,json,hashlib,concurrent.futures,re
root=pathlib.Path.cwd(); notes=root/'.autoport/reports/perf-mips2c-neon/notes'; old=notes/'attempt7'; out=notes/'attempt8'
sha=lambda p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
manifest={'directives':'vaff5c1afea','scope':'isolated laboratory, no Android device proof','sources':{str(p):sha(p) for p in [out/'block-parity.cpp',out/'corrected-sparticle.cpp',old/'before-sparticle.cpp']},'jobs':{}}
def command(cmd,log):
 with open(log,'w') as f:
  f.write('$ '+shlex.join(cmd)+'\n'); f.flush()
  p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
  f.write('\nEXIT '+str(p.returncode)+'\n')
 return p.returncode
def bench(arch):
 if arch=='arm-clang': cmd=json.loads((notes/'supervisor-clang-20260915/manifest.json').read_text())['build_command']
 else: cmd=shlex.split((old/f'block-parity-{arch}-build2.log').read_text().splitlines()[0][2:])
 binary=out/f'tested-block-parity-{arch}'
 cmd=[str(out/'block-parity.cpp') if x.endswith('/attempt7/block-parity.cpp') else x for x in cmd]; cmd[cmd.index('-o')+1]=str(binary)
 result={'build_command':cmd,'build_exit':command(cmd,out/f'tested-block-parity-{arch}-build.log')}
 if result['build_exit']==0:
  run=([str(binary)] if arch=='x86' else ['qemu-aarch64','-L','/usr/aarch64-linux-gnu',str(binary)])
  result.update(run_command=run,run_exit=command(run,out/f'tested-block-parity-{arch}-run.log'),binary_sha256=sha(binary))
 return 'bench-'+arch,result
def obj(arch,variant):
 src=old/'before-sparticle.cpp' if variant=='before' else out/'corrected-sparticle.cpp'
 prefix=out/f'tested-{variant}-{arch}'; binary=pathlib.Path(str(prefix)+'.o')
 cmd=shlex.split((old/f'before-{arch}-compile-command.txt').read_text())
 for flag,val in [('-c',src),('-o',binary),('-MF',str(binary)+'.d'),('-MT',binary)]:cmd[cmd.index(flag)+1]=str(val)
 result={'build_command':cmd,'source_sha256':sha(src),'build_exit':command(cmd,str(prefix)+'-build.log')}
 if result['build_exit']==0:
  result['object_sha256']=sha(binary)
  nm='nm' if arch=='x86' else 'aarch64-linux-gnu-nm'; dump='objdump' if arch=='x86' else 'aarch64-linux-gnu-objdump'
  result['nm_exit']=command([nm,'-S','--defined-only',str(binary)],str(prefix)+'-nm.txt')
  result['objdump_exit']=command([dump,'-drwC',str(binary)],str(prefix)+'-full.asm')
  text=pathlib.Path(str(prefix)+'-full.asm').read_text(); symbols={}
  for dim in ['2d','3d']:
   mangled=f'_ZN6Mips2C4jak119sp_process_block_{dim}7executeEPv'
   nmtxt=pathlib.Path(str(prefix)+'-nm.txt').read_text()
   m=re.search(r'^([0-9a-f]+) ([0-9a-f]+) T '+mangled+r'$',nmtxt,re.M)
   header=re.search(r'^([0-9a-f]+) <Mips2C::jak1::sp_process_block_'+dim+r'::execute\(void\*\)>:\n',text,re.M)
   if header:
    body=text[header.end():]; nexthead=re.search(r'^\s*[0-9a-f]+ <',body,re.M)
    if nexthead:body=body[:nexthead.start()]
    # Exclude continuation bytes: instruction mnemonic required after opcode bytes.
    lines=[l for l in body.splitlines() if re.match(r'^\s*[0-9a-f]+:\s+(?:[0-9a-f]{2,8}\s+)+\s*[a-z][a-z0-9.]*\s',l)]
    symbols[dim]={'symbol':mangled,'size_bytes':int(m.group(2),16) if m else None,'instruction_count':len(lines)}
   else:symbols[dim]={'error':'symbol disassembly not found'}
  result['symbols']=symbols
 return 'object-'+variant+'-'+arch,result
jobs=[(bench,(a,)) for a in ['x86','arm-gcc','arm-clang']]+[(obj,(a,v)) for a in ['x86','android'] for v in ['before','after']]
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
 for name,result in pool.map(lambda job:job[0](*job[1]),jobs):manifest['jobs'][name]=result;print(name,result.get('build_exit'),result.get('run_exit'),flush=True)
manifest['source_sha256_after']={p:sha(p) for p in manifest['sources']}
(out/'tested-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
