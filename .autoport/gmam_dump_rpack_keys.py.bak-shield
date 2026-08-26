import json, struct, subprocess, sys, os
ADB=["adb","-s","192.168.1.32:5555"]
PKG="org.opengoal.gk.jak1"
DIR=f"files/managed_assets/jak1"
def sh(cmd):
    return subprocess.run(ADB+["exec-out","run-as",PKG,"sh","-c",cmd],capture_output=True).stdout
names=[l for l in sh(f"ls {DIR}").decode().split() if l.endswith(".rpack")]
print("shards:",len(names),file=sys.stderr)
allentries=[]
for n in names:
    p=f"{DIR}/{n}"
    tail=sh(f"tail -c 24 {p} | base64")
    import base64
    t=base64.b64decode(tail)
    if len(t)!=24 or t[20:24]!=b"RIDX":
        print("bad trailer",n,len(t),t[-8:],file=sys.stderr); continue
    off,size=struct.unpack("<QQ",t[:16])
    bs=4096
    skip=off//bs
    pad=off-skip*bs
    count=(pad+size+bs-1)//bs
    raw=base64.b64decode(sh(f"dd if={p} bs={bs} skip={skip} count={count} 2>/dev/null | base64"))
    idx=json.loads(raw[pad:pad+size].decode("utf-8"))
    ents=idx["entries"] if isinstance(idx,dict) and "entries" in idx else idx
    for e in ents:
        allentries.append((e.get("key"),e.get("map"),e.get("width"),e.get("height")))
    print(f"{n}: {len(ents)} entries",file=sys.stderr)
json.dump(allentries,open("/tmp/rpack_keys.json","w"))
print("total entries:",len(allentries))
