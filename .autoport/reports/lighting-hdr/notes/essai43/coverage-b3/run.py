from pathlib import Path
import subprocess, hashlib, json, re, time, os, shutil

root = Path('/home/emeric/code/jak-project')
os.chdir(root)
n = Path(__file__).parent
a = ['/home/emeric/Android/platform-tools/adb', '-s', 'eae4df44']
pkg = 'org.opengoal.gk.jak1'
settings_path = '/storage/emulated/0/OpenGOAL/jak1/settings.ini'
calls = []
def adb(*args):
    p = subprocess.run(a + list(args), capture_output=True, timeout=40)
    calls.append({'args': args, 'rc': p.returncode, 'stdout': p.stdout.decode(errors='replace'),
                  'stderr': p.stderr.decode(errors='replace')})
    p.check_returncode()
    return p.stdout

assert not Path('.autoport/.deploy-in-progress').exists()
assert adb('get-state').strip() == b'device'
assert subprocess.check_output(['bash', '.autoport/lib/pick_device.sh'],
    env={**os.environ, 'ANDROID_SERIAL': 'eae4df44'}).strip() == b'eae4df44'
props_before = adb('shell', 'getprop').decode()
(n / 'props-original.json').write_text(json.dumps({k:v for k,v in re.findall(r'^\[(debug\.opengoal\.[^]]+)\]: \[(.*)\]$', props_before, re.M)}, indent=2))
assert not [line for line in props_before.splitlines() if line.startswith('[debug.opengoal.') and not line.endswith(': []')]
original = adb('exec-out', 'cat', settings_path)
(n / 'settings-original.ini').write_bytes(original)
assert b'pbr-materials? = #f' in original
configured = original.decode()
for key, value in [('dynamic-render-scale?', '#f'), ('render-scale', '40.0000')]:
    configured, count = re.subn(r'^' + re.escape(key) + r' = .*$', key + ' = ' + value, configured, flags=re.M)
    assert count == 1, (key, count)
(n / 'settings-fixed.ini').write_text(configured)
sources = ['goal_src/jak1/pc/jak-hd.gc', 'game/graphics/gfx.h', 'game/graphics/opengl_renderer/foreground/Generic2.h', 'game/graphics/opengl_renderer/background/background_common.cpp', 'game/graphics/opengl_renderer/foreground/Generic2_OpenGL.cpp', 'goal_src/jak1/pc/hud-classes-pc.gc', 'goal_src/jak1/pc/progress-pc.gc',
           'game/graphics/opengl_renderer/shaders/tonemap.frag', 'goal_src/jak1/pc/pckernel.gc']
(n / 'source-sha256.txt').write_text(''.join(hashlib.sha256(Path(p).read_bytes()).hexdigest() + '  ' + p + '\n' for p in sources))
try:
    adb('shell', 'am', 'force-stop', pkg)
    adb('push', str(n / 'settings-fixed.ini'), settings_path)
    assert adb('exec-out', 'cat', settings_path) == configured.encode()
    args = ['bash', '-c', 'pkill(){ printf "%s\\n" "DIRECTIVES: fallback kill par motif omis; nettoyage PID conserve" >&2; return 1; }; export -f pkill; exec bash "$@"', '_',
        '.autoport/lib/proof_run.sh', 'lighting-hdr', 'device', '--timeout', '1200',
        '--hdr-campaign', 'essai43-coverage', '--hdr-vantages', 'sunkenb-helix,swamp-dock1,rolling-start,ogre-start,village3-start,snow-start', '--hdr-hours', '0,3,6,9,12,15,18,21']
    props = ['refset.cam=village1-out:10:-104:394:-100',
        'refset.temporal=2', 'level.warp=sunkenb-helix', 'refset.loadsettle=240',
        'refset.orderhour=1', 'refset.settle=12', 'refset.warpat=900', 'refset.warpstep=0',
        'hdr.load_diag=1']
    for prop in props:
        args.extend(['--hdr-prop', 'debug.opengoal.' + prop])
    (n / 'command.json').write_text(json.dumps(args, indent=2) + '\n')
    (n / 'run-started').open('x').close()
    started_ns = time.time_ns()
    with (n / 'run.log').open('x') as log:
        result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT,
            env={**os.environ, 'AUTOPORT_BACKEND': 'codex', 'ANDROID_SERIAL': 'eae4df44'})
    (n / 'exit.txt').write_text(str(result.returncode) + '\n')
    proof = Path('.autoport/reports/lighting-hdr/proof.txt')
    if proof.exists() and proof.stat().st_mtime_ns >= started_ns:
        shutil.copy2(proof, n / 'proof-coverage.txt')
        match = re.search(r'^hdr_batch_manifest=(.+)$', proof.read_text(), re.M)
        if match:
            batch = Path(match[1]).parent
            shutil.copy2(batch / 'manifest.json', n / 'manifest.json')
            shutil.copy2(batch / 'engine.log', n / 'engine.log')
            (n / 'batch-path.txt').write_text(str(batch) + '\n')
            subprocess.run(['python3', '.autoport/reports/lighting-hdr/notes/essai28/collect-composition.py',
                str(batch / 'engine.log'), str(n / 'composition')], check=True, stdout=(n / 'composition.log').open('w'))

    # A failed quality verdict remains evidence; preserve its producer exit.
    result.check_returncode()
finally:
    adb('shell', 'am', 'force-stop', pkg)
    adb('push', str(n / 'settings-original.ini'), settings_path)
    restored = adb('exec-out', 'cat', settings_path)
    assert restored == original
    props = adb('shell', 'getprop').decode()
    nonempty = [line for line in props.splitlines() if line.startswith('[debug.opengoal.') and not line.endswith(': []')]
    assert not nonempty, nonempty
    adb('shell', 'am', 'start', '-n', pkg + '/org.opengoal.gk.LoaderActivity')
    time.sleep(8)
    pid1 = adb('shell', 'pidof', pkg).strip().decode()
    time.sleep(12)
    pid2 = adb('shell', 'pidof', pkg).strip().decode()
    (n / 'restoration.json').write_text(json.dumps({'DIRECTIVES': 'v8aed688f73',
        'original_settings_sha256': hashlib.sha256(original).hexdigest(),
        'restored_settings_sha256': hashlib.sha256(restored).hexdigest(),
        'pids': [pid1, pid2], 'nonempty_debug_props': nonempty, 'calls': calls}, indent=2) + '\n')
    adb('push', str(n / 'settings-original.ini'), settings_path)
    assert adb('exec-out', 'cat', settings_path) == original
    assert pid1 and pid1 == pid2
