"""Prepared only. Entry point after manager GO: python3 diagnostic.py --go.
Build/deploy lock is released for the official proof_run busy gate, reacquired for restore.
Never writes the publisher's APK path and never publishes or invokes generic.sh.
"""
from pathlib import Path
import atexit
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time

import run as loading_run


def sha(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


class Context:
    def __init__(self):
        self.root = Path('/home/emeric/code/jak-project')
        os.chdir(self.root)
        self.n = Path(__file__).resolve().parent
        self.report = self.root / '.autoport/reports/lighting-hdr'
        self.before = self.n / 'before'
        self.lock = self.root / '.autoport/.deploy-in-progress'
        self.owns_lock = False
        self.a = ['/home/emeric/Android/platform-tools/adb', '-s', 'eae4df44']
        self.pkg = 'org.opengoal.gk.jak1'
        self.settings_path = '/storage/emulated/0/OpenGOAL/jak1/settings.ini'
        self.lib = self.root / 'build-android/lib/arm64-v8a/libgk.so'
        self.jni = self.root / 'android/app/src/main/jniLibs/arm64-v8a/libgk.so'
        self.apk = self.root / 'android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk'
        self.diag_apk = self.n / 'gradle-app/outputs/apk/jak1/debug/app-jak1-debug.apk'
        self.env = {**os.environ, 'AUTOPORT_BACKEND': 'codex', 'ANDROID_SERIAL': 'eae4df44',
                    'TMPDIR': '/home/emeric/.autoport-tmp',
                    'ESSAI37_GRADLE_APP': str(self.n / 'gradle-app')}
        self.env['GRADLE_OPTS'] = self.env.get('GRADLE_OPTS', '') + ' -Djava.io.tmpdir=' + self.env['TMPDIR']
        self.calls = []
        self.saved = False
        self.device_touched = False

    def command(self, args, logname, check=True, timeout=120, cwd=None):
        with (self.n / logname).open('a') as f:
            f.write('$ ' + shlex.join(map(str, args)) + '\n'); f.flush()
            p = subprocess.run(args, stdout=f, stderr=subprocess.STDOUT, cwd=cwd,
                               env=self.env, timeout=timeout)
            f.write('exit=' + str(p.returncode) + '\n')
        if check:
            p.check_returncode()
        return p

    def adb(self, *args, timeout=60):
        p = subprocess.run(self.a + list(args), capture_output=True, timeout=timeout)
        self.calls.append({'args': args, 'rc': p.returncode,
                           'stdout': p.stdout.decode(errors='replace'),
                           'stderr': p.stderr.decode(errors='replace')})
        (self.n / 'adb-calls.json').write_text(json.dumps(self.calls, indent=2) + '\n')
        p.check_returncode()
        return p.stdout

    def acquire(self):
        # Fail closed for existing locks; no deletion/guessing about another process.
        fd = os.open(self.lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        self.owns_lock = True
        with os.fdopen(fd, 'w') as f:
            f.write(f'{__file__} pid={os.getpid()}\n')

    def release(self):
        if self.owns_lock:
            assert f'pid={os.getpid()}\n' in self.lock.read_text()
            self.lock.unlink()
            self.owns_lock = False

    def process_check(self):
        text = subprocess.check_output(['ps', '-eo', 'pid,ppid,comm,args'], text=True)
        (self.n / 'processes-before.txt').write_text(text)
        busy = []
        for line in text.splitlines():
            f = line.split(None, 3)
            if len(f) != 4:
                continue
            if f[2] in ['cmake', 'ninja', 'ninja-build', 'cc1plus', 'clang++', 'goalc', 'gk']:
                busy.append(line)
            if f[2] == 'java' and ('GradleDaemon' in f[3] or 'GradleWrapperMain' in f[3]):
                busy.append(line)
            if f[2] in ['bash', 'sh'] and 'auto_build_apk.sh' in f[3]:
                busy.append(line)
        assert not busy, 'Concurrent builder; no process killed: ' + repr(busy)

    def packs(self):
        bundle = self.root / 'android/app/src/jak1/assets-slim/bundle'
        paths = [bundle / (stem + suffix) for stem in ['jak1_cgo', 'jak1_custom']
                 for suffix in ['.zip', '.manifest.properties']]
        paths += sorted((self.root / 'out/jak1-arm64-full/iso').glob('*.CGO'))
        paths += sorted((self.root / 'out/jak1-arm64-full/iso').glob('*.DGO'))
        return {str(p.relative_to(self.root)): sha(p) for p in paths}

    def properties(self):
        return dict(re.findall(r'^\[(debug\.opengoal\.[^]]+)\]: \[(.*)\]$',
                               self.adb('shell', 'getprop').decode().replace('\r', ''), re.M))

    def identity(self, apk, expected_lib):
        import zipfile
        with zipfile.ZipFile(apk) as z:
            with z.open('lib/arm64-v8a/libgk.so') as f:
                assert hashlib.file_digest(f, 'sha256').hexdigest() == expected_lib
            for stem in ['jak1_cgo', 'jak1_custom']:
                for suffix in ['.zip', '.manifest.properties']:
                    name = stem + suffix
                    with z.open('assets/bundle/' + name) as f:
                        got = hashlib.file_digest(f, 'sha256').hexdigest()
                    assert got == self.pack_before['android/app/src/jak1/assets-slim/bundle/' + name]
        remote = self.adb('shell', 'pm', 'path', self.pkg).decode().strip().removeprefix('package:')
        assert remote.startswith('/') and '\n' not in remote
        assert self.adb('shell', 'sha256sum', remote).decode().split()[0] == sha(apk)
        assert self.adb('shell', 'sha256sum', str(Path(remote).parent / 'lib/arm64/libgk.so')).decode().split()[0] == expected_lib
        return {'apk_sha256': sha(apk), 'lib_sha256': expected_lib, 'device_apk': remote}

    def build_deploy(self):
        self.process_check()
        self.acquire()
        self.before.mkdir(exist_ok=False)
        for src, name in [(self.lib, 'libgk37-before.so'), (self.jni, 'jni37-before.so'),
                          (self.apk, 'APK37-before.apk')]:
            shutil.copy2(src, self.before / name)
        for name in ['proof.txt', 'proof-engine.log']:
            if (self.report / name).exists():
                shutil.copy2(self.report / name, self.before / ('proof36-' + name))
        self.pack_before = self.packs()
        (self.before / 'packs-sha256.json').write_text(json.dumps(self.pack_before, indent=2) + '\n')
        selected = subprocess.check_output(['bash', '.autoport/lib/pick_device.sh'], env=self.env).strip()
        assert selected == b'eae4df44'
        assert self.adb('get-state').strip() == b'device'
        self.settings = self.adb('exec-out', 'cat', self.settings_path)
        (self.before / 'settings-original.ini').write_bytes(self.settings)
        self.props = self.properties()
        (self.before / 'properties.json').write_text(json.dumps(self.props, indent=2) + '\n')
        # Refuse to overwrite a different installed normal version.
        self.identity(self.apk, sha(self.lib))
        self.saved = True
        diff = subprocess.check_output(['git', 'diff', '--', 'game/', 'common/', 'android/'])
        (self.n / 'diagnostic-source.diff').write_bytes(diff)
        changed = subprocess.check_output(['git', 'diff', '--name-only', '--', 'game/', 'common/', 'android/'], text=True).splitlines()
        source_hashes = {}
        for name in changed:
            src = self.root / name
            if src.is_file():
                dst = self.n / 'sources' / name
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
                source_hashes[name] = sha(src)
        (self.n / 'source-sha256.json').write_text(json.dumps(source_hashes, indent=2) + '\n')
        Path(self.env['TMPDIR']).mkdir(exist_ok=True)
        self.command(['cmake', '--build', 'build-android', '--target', 'gk', '-j2'], 'build.log', timeout=1800)
        assert sha(self.lib) != sha(self.before / 'libgk37-before.so'), 'Native binary did not change'
        shutil.copy2(self.lib, self.n / 'libgk-diagnostic.so')
        self.command(['./gradlew', '-I', str(self.n / 'isolate.gradle'), 'assembleJak1Debug',
                      '--no-daemon', '-x', 'configureNativeLibs', '-x', 'buildNativeLibs',
                      '-x', 'bundleJak1CgoPack', '-x', 'bundleJak1CustomPack'],
                     'repack.log', cwd=self.root / 'android', timeout=1200)
        assert self.packs() == self.pack_before
        assert sha(self.apk) == sha(self.before / 'APK37-before.apk'), 'Publisher APK changed'
        assert sha(self.jni) == sha(self.lib)
        self.device_touched = True
        self.adb('install', '-r', str(self.diag_apk), timeout=180)
        identity = self.identity(self.diag_apk, sha(self.lib))
        shutil.copy2(self.lib, self.n / 'libgk-diagnostic.so')
        (self.n / 'delivery-identity.json').write_text(json.dumps(identity, indent=2) + '\n')
        self.adb('shell', 'am', 'force-stop', self.pkg)
        assert self.adb('exec-out', 'cat', self.settings_path) == self.settings
        self.release()

    def restore(self):
        if not self.saved:
            return
        if not self.owns_lock:
            self.acquire()
        errors = []
        def attempt(label, action):
            try:
                action()
            except Exception as e:
                errors.append(label + ': ' + repr(e))
        if self.device_touched:
            attempt('force-stop', lambda: self.adb('shell', 'am', 'force-stop', self.pkg))
            attempt('normal APK reinstall', lambda: self.adb('install', '-r', str(self.before / 'APK37-before.apk'), timeout=180))
            attempt('settings restore', lambda: self.adb('push', str(self.before / 'settings-original.ini'), self.settings_path))
            def restore_props():
                for key in self.properties().keys() | self.props.keys():
                    self.adb('shell', 'setprop ' + shlex.quote(key) + ' ' + shlex.quote(self.props.get(key, '')))
                assert {k: v for k, v in self.properties().items() if v} == {k: v for k, v in self.props.items() if v}
            attempt('properties restore', restore_props)
            def verify_device():
                assert self.adb('exec-out', 'cat', self.settings_path) == self.settings
                self.identity(self.before / 'APK37-before.apk', sha(self.before / 'libgk37-before.so'))
            attempt('device normal identity/settings', verify_device)
        # Preserve diagnostic separately before reverting local lib for normal APK coherence.
        for target, saved in [(self.lib, 'libgk37-before.so'), (self.jni, 'jni37-before.so')]:
            attempt('local restore ' + saved, lambda target=target, saved=saved: shutil.copy2(self.before / saved, target))
        def verify_local():
            assert sha(self.apk) == sha(self.before / 'APK37-before.apk')
            assert sha(self.lib) == sha(self.before / 'libgk37-before.so')
            assert sha(self.jni) == sha(self.before / 'jni37-before.so')
            assert self.packs() == self.pack_before
        attempt('local identity and packs', verify_local)
        (self.n / 'restoration.json').write_text(json.dumps({'DIRECTIVES': 'v708c60642a',
            'errors': errors, 'settings_sha256': hashlib.sha256(self.settings).hexdigest(),
            'normal_apk_sha256': sha(self.before / 'APK37-before.apk')}, indent=2) + '\n')
        if errors:
            raise RuntimeError('Restoration incomplete: ' + repr(errors))


def main():
    if sys.argv[1:] != ['--go']:
        raise SystemExit('Prepared only. Require manager GO, then invoke --go once.')
    ctx = Context()
    atexit.register(ctx.release)
    def interrupted(signum, _frame):
        raise RuntimeError('Signal ' + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        ctx.build_deploy()
        loading_run.run(ctx)
    finally:
        try:
            ctx.restore()
        finally:
            ctx.release()


if __name__ == '__main__':
    main()
