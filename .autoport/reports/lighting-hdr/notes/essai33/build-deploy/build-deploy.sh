#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
N=.autoport/reports/lighting-hdr/notes/essai33/build-deploy
LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then
  oldpid=$(sed -n 's/.*pid=\([0-9]\{1,\}\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then echo "deploy lock vivant pid=$oldpid"; exit 3; fi
fi
python3 - <<'PY'
import subprocess,sys
rows=subprocess.check_output(['ps','-eo','pid,comm,args'],text=True).splitlines()
busy=[x for x in rows if len(x.split(None,2))==3 and (x.split(None,2)[1] in ['ninja','ninja-build','goalc','cc1plus','clang++','gk','gk.exe','cmake'] or (x.split(None,2)[1]=='java' and 'GradleDaemon' in x))]
if busy: print('\n'.join(busy));sys.exit(3)
PY
printf '%s pid=%s\n' "$0" "$$" > "$LOCK"
cleanup(){ (cd android && ./gradlew --stop) >> "$N/build-deploy.log" 2>&1 || true; rm -f "$LOCK"; }
trap cleanup EXIT
exec > >(tee -a "$N/build-deploy.log") 2>&1
set -x
mkdir -p "$N/before-build"
test ! -e "$N/before-build/libgk.so"
test ! -e "$N/before-build/app-jak1-debug.apk"
cp -n build-android/lib/arm64-v8a/libgk.so "$N/before-build/libgk.so"
cp -n android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk "$N/before-build/app-jak1-debug.apk"
sha256sum "$N/before-build/libgk.so" "$N/before-build/app-jak1-debug.apk"
git rev-parse HEAD
python3 - <<'SEAL'
import subprocess,hashlib,json
from pathlib import Path
n=Path('.autoport/reports/lighting-hdr/notes/essai33/build-deploy')
paths=set(subprocess.check_output(['git','diff','--name-only','HEAD','--','game/graphics'],text=True).splitlines())
paths.update(['game/graphics/opengl_renderer/DirectRenderer.cpp','game/graphics/opengl_renderer/DirectRenderer.h','game/graphics/opengl_renderer/sprite/Sprite3.h','game/graphics/refset.cpp','game/graphics/opengl_renderer/sprite/Sprite3.cpp','game/graphics/opengl_renderer/shaders/sprite3_3d.frag','game/graphics/opengl_renderer/shaders/sprite3_3d_inst.frag'])
paths.update(str(p) for p in Path('game/graphics').rglob('*') if p.is_file() and ('tonemap' in p.name.lower() or 'hdr' in p.name.lower()))
paths=sorted(p for p in paths if Path(p).is_file())
(n/'source-sha256.txt').write_text(''.join(hashlib.sha256(Path(p).read_bytes()).hexdigest()+'  '+p+'\n' for p in paths))
(n/'source-paths.json').write_text(json.dumps(paths,indent=2)+'\n')
(n/'source-diff.patch').write_bytes(subprocess.check_output(['git','diff','HEAD','--','game/graphics']))
SEAL
cmake --build build-android --target gk -j3
(cd android && ./gradlew assembleJak1Debug --no-daemon -x configureNativeLibs -x buildNativeLibs -x bundleJak1CgoPack -x bundleJak1CustomPack)
(cd android && ./gradlew --stop)
python3 - <<'PY'
from pathlib import Path
import hashlib,zipfile
apk=Path('android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk')
lib=Path('build-android/lib/arm64-v8a/libgk.so').read_bytes()
with zipfile.ZipFile(apk) as z: packaged=z.read('lib/arm64-v8a/libgk.so')
assert lib==packaged, 'APK lib differs from build'
assert Path('build-android/lib/arm64-v8a/libgk.so').stat().st_mtime >= max(Path(p).stat().st_mtime for p in __import__('json').loads(Path('.autoport/reports/lighting-hdr/notes/essai33/build-deploy/source-paths.json').read_text())), 'build older than sources'
print('APK SHA256',hashlib.sha256(apk.read_bytes()).hexdigest())
print('build/APK lib SHA256',hashlib.sha256(lib).hexdigest());print('build/APK lib MD5',hashlib.md5(lib).hexdigest());print('APK MD5',hashlib.md5(apk.read_bytes()).hexdigest())
PY
sha256sum -c "$N/source-sha256.txt"
test "$(/home/emeric/Android/platform-tools/adb -s eae4df44 get-state)" = device
selected=$(ANDROID_SERIAL=eae4df44 bash .autoport/lib/pick_device.sh)
test "$selected" = eae4df44
/home/emeric/Android/platform-tools/adb -s eae4df44 install -r android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
python3 - <<'PY'
from pathlib import Path
import hashlib,subprocess,datetime,shutil
adb=['/home/emeric/Android/platform-tools/adb','-s','eae4df44'];pkg='org.opengoal.gk.jak1'
apkpath=subprocess.check_output(adb+['shell','pm','path',pkg],text=True).strip().removeprefix('package:')
cmd=adb+['shell','md5sum',str(Path(apkpath).parent/'lib/arm64/libgk.so')];print('$',' '.join(cmd))
device_md5=subprocess.check_output(cmd,text=True).split()[0]
lib=Path('build-android/lib/arm64-v8a/libgk.so').read_bytes();assert hashlib.md5(lib).hexdigest()==device_md5
print('device lib MD5',device_md5)
device_sha=subprocess.check_output(adb+['shell','sha256sum',str(Path(apkpath).parent/'lib/arm64/libgk.so')],text=True).split()[0]
assert hashlib.sha256(lib).hexdigest()==device_sha
print('device lib SHA256',device_sha)
apk=Path('android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk')
device_apk_sha=subprocess.check_output(adb+['shell','sha256sum',apkpath],text=True).split()[0]
assert hashlib.sha256(apk.read_bytes()).hexdigest()==device_apk_sha
print('device APK SHA256',device_apk_sha)
PY

printf "build_deploy_exit=0\n"
