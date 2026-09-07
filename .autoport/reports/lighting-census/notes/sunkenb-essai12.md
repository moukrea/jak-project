# Sunkenb — inspection CPU essai12
DIRECTIVES v6fca51fe40
Commandes exécutées par le researcher natif ; aucun run jeu ni appareil.
```python
import pathlib, struct, hashlib
raw = pathlib.Path('decompiler_out/jak1/raw_obj/sunkenb-vis.go').read_bytes()
print('header', struct.unpack_from('<4I', raw))
a = struct.unpack_from('<I', raw, 16+168)[0]
print('adgifs', hex(a), 'count', struct.unpack_from('<I', raw, 16+a)[0])
start = 16+a-4+16
print('texture-ids', *[hex(struct.unpack_from('<I', raw, start+i*80+24)[0]) for i in range(9)])
b = pathlib.Path('out/jak1/iso/SUB.DGO').read_bytes()
n = struct.unpack_from('<I', b)[0]
off = 64
for _ in range(n):
    size = struct.unpack_from('<I', b, off)[0]
    name = b[off+4:off+64].split(bytes([0]))[0].decode()
    off += 64
    if name == 'sunkenb-vis':
        print(name, 'size', size, 'same', raw == b[off:off+size],
              'sha256', hashlib.sha256(b[off:off+size]).hexdigest())
    off += (size+15) & ~15
```
Script ci-dessus regroupant les lectures réalisées ; sorties exactes transmises :
```
sunkenb header (4294967295, 31168, 4, 2765424) data-base 0x10
adgifs offset 168 0x29ff04
sunkenb adgifs basic 0x29ff04 bytes ff ff ff ff 09 00 00 00 09 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 06 03 00 00 00 00 00 00 20 01 00 00
texture-ids 0xa200114 0xa200214 0xa200314 0xa200414 0xa200514 0xa200614 0xa200714 0xa200814 0xa200014
SUB.DGO 4812512 header 21 b'SUB.DGO'
sunkenb-vis size 2796608 raw_size 2796608 same True sha256 4af61081b37f3acc887e8661c5342f91763102b3760f58ac3f04d1ef64039680
```
V4 : données+16 ; champ BSP+168 ; basic offset−4 ; tableau+16 ; stride80 ; texid+24.
Types et overlays : goal_src/jak1/engine/gfx/texture/texture-h.gc:235–259.
Tpage162=0xa2 sunkenb-vis-alpha : engine/data/tpages.gc:3.
Indices1–8=vil1-sky-00..07,0=vil1-clouds : engine/data/textures.gc:62–70.
SUB.DGO inclut tpage-162.go : goal_src/jak1/dgos/sub.gd:5.

Conditions statiques : sky-tng.gc:901–914 exige niveau actif/info.sky,
contribution non nulle (forcée à1 si seul niveau à ciel), adgifs et poids sky-times.
Sunken sky#f,Sunkenb#t ; mood.gc:1021 appelle update-mood-sky-texture.
Drawable.gc:819–824 teste masque sky/contexte sky/sky-drawn, sinon gradient.
SkyRenderer.cpp:144,157–174 distingue bucket vide/paquet toit et m_enabled.
Aucun relevé runtime trouvé de ces conditions à la capture ni de couverture ciel
avant géométrie. La profondeur finale ne distingue pas absence et occultation.
La présence de ressources ne démontre pas la visibilité ; Sunkenb reste manquant.

Vérification manager : script regroupé exécuté code0 ; mêmes champs et SHA ci-dessus.
