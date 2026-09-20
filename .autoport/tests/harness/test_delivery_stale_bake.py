"""Delivery regression bench: real producer scripts, isolated git and fake tools only."""
import hashlib
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import zipfile

import pytest

AP = Path(__file__).resolve().parents[2]
APK = 'android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk'
ZIP = 'out/artifacts/jak1_hd_assets.zip'
INFO = 'out/artifacts/BUILD-INFO.txt'

FAKE = r'''import json, os, signal, sys, time, zipfile
from pathlib import Path
r=Path(os.environ['DELIVERY_BENCH_ROOT']); ap=r/'.autoport'
name=sys.argv[1]; args=sys.argv[2:]
def write(p,s):
 p=r/p; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(s)
def archive(p,s):
 p=r/p; p.parent.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(p,'w') as z: z.writestr('content',s)
def get(p):
 p=r/p; return p.read_text().strip() if p.exists() else None
with (r/'events').open('a') as f: f.write(json.dumps([name,*args])+'\n')
if name=='sleep':
 if args and args[0] in ('240','300'):
  n=int(get('turn') or '0')+1; write('turn',str(n))
  snap={k:get('.autoport/'+k) for k in ['.last_apk_build_sha','.last_apk_build_commit','.build-request','.deploy-in-progress']}
  snap['turn']=n
  with (r/'snapshots').open('a') as f: f.write(json.dumps(snap)+'\n')
  if n>int(os.environ.get('BENCH_TURNS','1')): os.kill(os.getppid(),signal.SIGTERM)
 sys.exit(0)
if name in ('ps','adb','disk','tag','notes'): sys.exit(0)
turn=int(get('turn') or '1')
fail=os.environ.get('BENCH_FAIL','')
if name==fail and turn==1: sys.exit(17)
if name=='arm' and fail=='sourcechange' and turn==1:
 write('common/custom_data/TFrag3Data.cpp','source changed during build')
if name=='gradle' and 'assembleJak1Debug' in args:
 if fail in ('gradle_missing','gradle_stale') and turn==1: sys.exit(0)
 archive('android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk','apk-produced-'+str(turn))
 if os.environ.get('BENCH_MANIFESTS')=='1':
  for pack in ('cgo','custom'):
   write(f'android/app/src/jak1/assets-slim/bundle/jak1_{pack}.manifest.properties','version=generated\n')
if name=='hd' and not (fail=='hd_stale' and turn==1): archive('out/artifacts/jak1_hd_assets.zip','hd-produced-'+str(turn))
if name=='mesh':
 if fail=='mesh_no_output':
  print('BAKED SIDECARS: 1 written'); sys.exit(0)
 level=args[args.index('--level')+1] if '--level' in args else None
 fr3=r/args[args.index('--fr3-dir')+1]
 paths=[fr3/f'{level}.fr3'] if level else list(fr3.glob('*.fr3'))
 for p in paths:
  q=p.with_suffix('.meshweld')
  if fail=='mesh_partial':
   q.write_text('truncated'); os.utime(q,None); sys.exit(17)
  q.write_text('baked '+p.stem); os.utime(q,None)
 print('BAKED SIDECARS: 1 written')
sys.exit(0)
'''


def put(root, name, value, executable=False):
    p = root / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(value)
    if executable:
        p.chmod(0o755)
    return p


@pytest.fixture
def bench(tmp_path):
    root = tmp_path / 'repo'
    root.mkdir()
    for name in ('auto_build_apk.sh', 'auto_push_builds.sh', 'prepare_delivery_bakes.sh',
                 'delivery_artifact.py', 'lib/checkpoint_snapshot.sh'):
        target = root / '.autoport' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(AP / name, target)
    for directory in ('.autoport/logs', '.autoport/dist', 'out/artifacts', 'tmp', 'fakebin'):
        (root / directory).mkdir(parents=True, exist_ok=True)
    dispatcher = put(root, 'fake.py', FAKE)
    mapping = {'fakebin/ps':'ps', 'fakebin/sleep':'sleep', 'fakebin/adb':'adb',
               'fakebin/gh':'gh', 'fakebin/cmake':'cmake', '.autoport/disk_reclaim.sh':'disk',
               '.autoport/build_arm64_full_consistent.sh':'arm',
               '.autoport/build_tag.sh':'tag', '.autoport/release_notes.sh':'notes',
               '.autoport/lib/build_x86.sh':'toolbuild',
               'build/tools/mesh_audit/mesh_audit':'mesh', 'android/gradlew':'gradle',
               'scripts/package_hd_assets.sh':'hd', 'build/goalc/goalc':'goalc'}
    for path, tool in mapping.items():
        put(root, path, '#!/bin/bash\nexec '+shlex_quote(sys.executable)+' '+shlex_quote(str(dispatcher))+' '+tool+' "$@"\n', True)
    put(root, '.gitignore', '/.autoport/\n/out/\n/build/\n/fakebin/\n/tmp/\n/events\n/snapshots\n/turn\n/android/app/build/\n/builder-pids\n/decoy/\n')
    put(root, 'common/custom_data/TFrag3Data.cpp', 'source v1\n')
    for level in ('beach', 'village1'):
        put(root, f'out/jak1/fr3/{level}.fr3', 'input '+level)
        p = put(root, f'out/jak1/fr3/{level}.meshweld', 'old bake '+level)
        os.utime(p, (time.time()-100, time.time()-100))
    # LA GARDE DU CONSTRUCTEUR NE LIT PLUS LE /proc DE L'HOTE (20/09). auto_build_apk.sh est
    # execute ENTIER ici : sans cette porte, un seul `gk`/`cc1plus`/`ninja` vivant ailleurs sur
    # la machine faisait `continue` a chaque tour et rendait EN BLOC les 11 tests qui pilotent ce
    # script — deux items d'affilee ont paye ce rouge (res-scale-submenu 18/09, pack-manifest
    # 20/09). Le banc n'expose que les pids qu'il choisit ; le fichier vide veut dire « aucun
    # constructeur », ce qui est la verite d'un depot jetable.
    put(root, 'builder-pids', '')
    env = dict(os.environ, PATH=str(root/'fakebin')+os.pathsep+os.environ['PATH'],
               DELIVERY_BENCH_ROOT=str(root), ADB=str(root/'fakebin/adb'), TMPDIR=str(root/'tmp'),
               HOME=str(root), GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
               BUILDER_PID_LIST_FILE=str(root/'builder-pids'))
    for args in [('init','-q'), ('config','user.name','Delivery bench'),
                 ('config','user.email','bench@example.invalid'), ('add','.'), ('commit','-qm','deliver fixture')]:
        subprocess.run(['git',*args], cwd=root, env=env, check=True, capture_output=True)
    return root, env


def shlex_quote(value):
    import shlex
    return shlex.quote(value)


def run(bench, script, *args, **extra):
    root, env = bench
    return subprocess.run(['bash', str(root/'.autoport'/script),*args], cwd=root,
                          env=dict(env,**extra), capture_output=True, text=True, timeout=20)


def events(root, name):
    path = root/'events'
    return [x for x in map(json.loads,path.read_text().splitlines()) if x[0]==name] if path.exists() else []


def artifact(bench, *args):
    root, env=bench
    return subprocess.run([sys.executable,str(root/'.autoport/delivery_artifact.py'),*args],
                          cwd=root,env=env,capture_output=True,text=True,timeout=10)


def _leurre(root):
    """Un VRAI processus de l'hote dont `comm` vaut `gk` — ce que la garde compte comme build."""
    source = shutil.which('sleep')
    if not source:
        pytest.skip('pas de /usr/bin/sleep pour fabriquer le leurre')
    chemin = root/'decoy'/'gk'
    chemin.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, chemin)
    proc = subprocess.Popen([str(chemin), '120'], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    fin = time.time()+5
    comm = ''
    while time.time() < fin:
        try:
            comm = Path('/proc/%d/comm' % proc.pid).read_text().strip()
        except OSError:
            comm = ''
        if comm == 'gk':
            return proc
        time.sleep(0.05)
    proc.kill(); proc.wait()
    pytest.fail('le leurre ne porte pas comm=gk mais %r' % comm)


@pytest.mark.parametrize('porte',['vide','avec-le-pid','absente'])
def test_host_build_process_is_invisible_unless_the_bench_exposes_it(bench, porte):
    """LA GARDE DE NON-REGRESSION DU 20/09, deux sens mesures avec LE MEME leurre.

    `vide`        : la porte est posee et ne nomme personne -> le `gk` de l'HOTE ne compte pas,
                    le build part. C'est l'etat livre du banc.
    `avec-le-pid` : le meme leurre inscrit dans la porte -> la garde le compte et refuse de
                    batir. Elle n'est donc pas devenue aveugle, elle lit ce qu'on lui donne.
    `absente`     : porte retiree -> repli sur le VRAI /proc, le leurre redevient visible et le
                    build ne part pas. C'est EXACTEMENT le symptome d'avant le correctif, et
                    c'est lui qui rend ce test capable de rougir si la porte disparait.
    """
    root, _ = bench
    proc = _leurre(root)
    try:
        if porte == 'avec-le-pid':
            (root/'builder-pids').write_text('%d\n' % proc.pid)
        elif porte == 'absente':
            (root/'builder-pids').unlink()
        result = run(bench, 'auto_build_apk.sh')
        assert result.returncode in (0,-15,143), result.stderr
        assert len(events(root,'arm')) == (1 if porte == 'vide' else 0), \
            (porte, (root/'.autoport/logs').exists() and events(root,'arm'))
    finally:
        proc.kill(); proc.wait()


@pytest.mark.parametrize('failure',['arm','mesh','gradle','hd','gradle_missing','sourcechange','gradle_stale','hd_stale'])
def test_retry_failure_preserves_request_and_success_stamps(bench, failure):
    root,_=bench
    if failure in ('gradle_stale','hd_stale'):
        old=root/(APK if failure=='gradle_stale' else ZIP)
        old.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(old,'w') as z:
            z.writestr('content','previous complete artifact')
        os.utime(old,(time.time()-200,time.time()-200))
    put(root,'.autoport/.last_apk_build_sha','previous-sha\n')
    put(root,'.autoport/.last_apk_build_commit','previous-commit\n')
    put(root,'.autoport/.build-request','retry requested\n')
    result=run(bench,'auto_build_apk.sh',BENCH_TURNS='3',BENCH_FAIL=failure)
    assert result.returncode in (0,-15,143), result.stderr
    snapshots=list(map(json.loads,(root/'snapshots').read_text().splitlines()))
    assert len(snapshots)==4
    failed=snapshots[1]
    assert failed['.last_apk_build_sha']=='previous-sha'
    assert failed['.last_apk_build_commit']=='previous-commit'
    assert failed['.build-request']=='retry requested'
    assert failed['.deploy-in-progress'] is None
    succeeded=snapshots[2]
    assert succeeded['.last_apk_build_sha'] not in (None,'previous-sha')
    assert succeeded['.last_apk_build_commit'] not in (None,'previous-commit')
    assert succeeded['.build-request'] is None
    assert succeeded['.deploy-in-progress'] is None
    assert snapshots[3]==dict(succeeded,turn=4)
    assert len(events(root,'arm'))==(1 if failure=='mesh' else 2)
    assert artifact(bench,'check').returncode==0


@pytest.mark.parametrize('manifests',[False,True])
def test_success_then_unchanged_does_not_rebuild(bench,manifests):
    root,env=bench
    if manifests:
        for pack in ('cgo','custom'):
            put(root,f'android/app/src/jak1/assets-slim/bundle/jak1_{pack}.manifest.properties','version=old\n')
        subprocess.run(['git','add','android'],cwd=root,env=env,check=True)
        subprocess.run(['git','commit','-qm','tracked generated manifests'],cwd=root,env=env,check=True)
    result=run(bench,'auto_build_apk.sh',BENCH_TURNS='2',BENCH_MANIFESTS=str(int(manifests)))
    assert result.returncode in (0,-15,143),result.stderr
    assert len(events(root,'arm'))==1
    assert len([e for e in events(root,'gradle') if 'assembleJak1Debug' in e])==1
    assert artifact(bench,'check').returncode==0
    assert not (root/'.autoport/.deploy-in-progress').exists()


def test_retry_legacy_success_stamp_without_receipt(bench):
    root,env=bench
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,env=env).decode()
    put(root,'.autoport/.last_apk_build_sha',hashlib.md5(head.encode()).hexdigest()+'\n')
    put(root,'.autoport/.last_apk_build_commit',head)
    run(bench,'auto_build_apk.sh')
    assert len(events(root,'arm'))==1
    assert artifact(bench,'check').returncode==0


def test_stale_bake_only_stale_levels_then_unchanged(bench):
    root,_=bench
    fresh=root/'out/jak1/fr3/village1.meshweld'
    os.utime(fresh,None)
    original=fresh.read_bytes(),fresh.stat().st_mtime_ns
    result=run(bench,'prepare_delivery_bakes.sh')
    assert result.returncode==0,result.stderr
    calls=events(root,'mesh')
    assert len(calls)==1 and 'beach' in calls[0],calls
    assert (fresh.read_bytes(),fresh.stat().st_mtime_ns)==original
    assert run(bench,'prepare_delivery_bakes.sh').returncode==0
    assert events(root,'mesh')==calls
    assert len(events(root,'toolbuild'))==1
    assert not list((root/'.autoport/logs/delivery-bakes').glob('.stage.*'))


@pytest.mark.parametrize('failure',['mesh','mesh_no_output','toolbuild'])
def test_stale_bake_failure_is_not_success(bench,failure):
    result=run(bench,'prepare_delivery_bakes.sh',BENCH_FAIL=failure)
    assert result.returncode!=0,result.stdout+result.stderr
    assert not list((bench[0]/'.autoport/logs/delivery-bakes').glob('.stage.*'))


def test_stale_partial_bake_preserves_destination_and_retry(bench):
    root,_=bench
    destination=root/'out/jak1/fr3/beach.meshweld'
    before=destination.read_bytes(),destination.stat().st_mtime_ns
    failed=run(bench,'prepare_delivery_bakes.sh',BENCH_FAIL='mesh_partial')
    assert failed.returncode!=0,failed.stdout+failed.stderr
    assert (destination.read_bytes(),destination.stat().st_mtime_ns)==before
    assert not list((root/'.autoport/logs/delivery-bakes').glob('.stage.*'))
    succeeded=run(bench,'prepare_delivery_bakes.sh')
    assert succeeded.returncode==0,succeeded.stdout+succeeded.stderr
    assert destination.read_text()=='baked beach'
    assert destination.stat().st_mtime_ns>before[1]
    assert len([e for e in events(root,'mesh') if 'beach' in e])==2
    assert not list((root/'.autoport/logs/delivery-bakes').glob('.stage.*'))


@pytest.mark.parametrize('damage',['missing_receipt','apk','zip','info','locked','none'])
def test_publication_requires_complete_coherent_receipt(bench,damage):
    root,env=bench
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,env=env).decode().strip()
    for name in (APK,ZIP):
        path=root/name
        path.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(path,'w') as z:
            z.writestr('content','complete')
    put(root,INFO,'commit: '+head+'\n')
    source=artifact(bench,'sources')
    assert source.returncode==0,source.stderr
    sealed=artifact(bench,'seal',head,source.stdout.strip())
    assert sealed.returncode==0,sealed.stderr
    if damage=='missing_receipt':
        (root/'.autoport/.delivery-ready.json').unlink()
    elif damage not in ('none','locked'):
        put(root,{'apk':APK,'zip':ZIP,'info':INFO}[damage],'modified')
    with (root/'.autoport/.delivery-artifacts.lock').open('w') as lock:
        if damage=='locked':
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        run(bench,'auto_push_builds.sh')
    uploads=[e for e in events(root,'gh') if e[1:3]==['release','upload']]
    assert bool(uploads)==(damage=='none'),uploads
