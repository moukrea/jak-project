#!/usr/bin/env bash
# External-asset-root feature (autoport 2026-07): build the SLIM "CGO pack" that
# the assets-slim APK ships. Unlike build_asset_bundle.sh (which packs the FULL
# ~1.6 GiB runtime set — iso data + fr3 + arm64 code), this packs ONLY the tiny
# arch-specific code layer: every *.CGO/*.DGO from the ARM64 build, plus every
# rebuilt *.TXT text bank. The bulky iso data + fr3 come from the
# user's external asset root instead; the CGO pack is unpacked to
# <filesDir>/cgo/<game>/ and handed to fake_iso as the FIRST-scanned overlay dir,
# so the freshly-built arm64 code (matching HEAD libgk.so) always wins over any
# x86/older CGOs sitting in the external iso dir.
#
# Layout (zip root, FLAT — no subdirs):
#   *.CGO / *.DGO   the 28 ARM64-compiled code files (jak1; >0 for jak2)
#   *.TXT           ALL rebuilt text banks (out/<game>/iso/*.TXT — COMMON + SUBTIT,
#                   every language; they carry port-custom text ids so they are
#                   PACKAGE artifacts per the Grecharged-buildsys-packaging rule;
#                   the source-derived <game>_assets.zip ships NO TXT).
#
# There is NO LONGER an "android text override" overlay. It was a build-time
# rewrite of #x16e in a separate out/<game>-android-text/ copy that this packer laid
# over the desktop banks; it froze whole languages three times (the worst: #x1728
# shipped as "UNKNOWN ID 5928" on device only) and it decided by PLATFORM, which is
# wrong — the SHIELD is Android with no touchscreen. Both wordings now live in the
# SAME bank under two ids (#x16e without touch, #x17e7 with) and GOAL picks at
# RUNTIME from a fact the platform posts. See the touch-variant gate below.
#
# Output:
#   android/app/src/<game>/assets-slim/bundle/<game>_cgo.zip           (DEFLATE)
#   android/app/src/<game>/assets-slim/bundle/<game>_cgo.manifest.properties
#
# HARD-FAILS if the arm64 iso dir is missing, if the code-file count is wrong
# (jak1: exactly 28; jak2: >0), or if the arm64 KERNEL.CGO is missing / equals
# the x86 oracle copy (a mixed/x86 pack would SIGILL on the arm64 device).
# Mirrors build_asset_bundle.sh's rigor: content-derived VERSION, staleness skip,
# completeness gates, KERNEL.CGO arm64!=x86 assertion.
set -euo pipefail

GAME="${1:-jak1}"

cd "$(git rev-parse --show-toplevel)"

ARM64_CODE="out/${GAME}-arm64-full/iso"
# x86 oracle copies — used ONLY for the "arm64 != x86" KERNEL.CGO assertion.
ISO_BUILD="out/${GAME}/iso"
# Text sources — read ONLY by the touch-variant gate below, to learn which languages
# are SUPPOSED to carry a touch wording. Never packed.
TEXT_SRC="game/assets/${GAME}/text"
OUT_DIR="android/app/src/${GAME}/assets-slim/bundle"
STAGE="out/${GAME}-cgo-pack-stage"
ZIP_REL="${OUT_DIR}/${GAME}_cgo.zip"
MANIFEST="${OUT_DIR}/${GAME}_cgo.manifest.properties"
ZIP_ABS="$(pwd)/${ZIP_REL}"
ROOT="$(pwd)"

fail(){ echo "[cgo-pack] FATAL: $*" >&2; exit 1; }

[ -d "$ARM64_CODE" ] || fail "no $ARM64_CODE — run .autoport/build_arm64_full_consistent.sh first (need the consistent arm64 CGO/DGO set)"

# Every *.CGO/*.DGO in the arm64 iso dir is a pack member.
mapfile -t CODE_FILES < <(find "$ARM64_CODE" -maxdepth 1 -type f \( -name '*.CGO' -o -name '*.DGO' \) -printf '%f\n' | sort)
N_CODE=${#CODE_FILES[@]}
[ "$N_CODE" -gt 0 ] || fail "no CGO/DGO in $ARM64_CODE"
if [ "$GAME" = "jak1" ]; then
  [ "$N_CODE" -eq 28 ] || fail "jak1 expects exactly 28 CGO/DGO, found $N_CODE in $ARM64_CODE"
fi
[ -f "$ARM64_CODE/KERNEL.CGO" ] || fail "arm64 set missing KERNEL.CGO"

# ALL rebuilt text banks from the desktop iso build (COMMON + SUBTIT, every
# language). Grecharged-buildsys-packaging: the separate <game>_assets.zip ships
# ONLY vanilla data (no TXT), so the pack is now the ONLY delivery path for the
# rebuilt banks — a missing bank here = missing language/subtitles on device.
mapfile -t DESKTOP_TXT < <(find "$ISO_BUILD" -maxdepth 1 -type f -name '*.TXT' -printf '%f\n' 2>/dev/null | sort)
N_DTXT=${#DESKTOP_TXT[@]}
[ "$N_DTXT" -gt 0 ] || fail "no *.TXT banks in $ISO_BUILD — run the PC text build first"
if [ "$GAME" = "jak1" ]; then
  [ "$N_DTXT" -eq 46 ] || fail "jak1 expects exactly 46 TXT banks (23 COMMON + 23 SUBTIT), found $N_DTXT in $ISO_BUILD"
fi

# LA PORTE DE LA VARIANTE TACTILE — AU POINT DE PRODUCTION, PAS AU POINT DE CONTROLE.
#
# Ce qui s'est passe trois fois : une surcharge de texte fabriquee a cote du banc, laissee
# derriere par le build, et livree gelee (ou pas livree du tout) sans que rien ne le dise.
# La derniere fois, `.autoport/gtt_build_android_text.sh` a ete ARCHIVE ; la garde de
# fraicheur d'ici a teste `[ -x <ce chemin> ]`, l'a trouve faux, a DROP l'overlay et a
# laisse partir le banc bureau. L'owner a lu « Appuie sur start » sur un telephone sans
# bouton start.
#
# La lecon est dans la garde elle-meme : elle dependait d'un fichier EXTERIEUR, donc elle
# est morte en silence quand ce fichier a bouge. Celle-ci n'appelle RIEN. Le decodeur de
# banc est ecrit ici, en entier ; aucun script de `.autoport/` n'est dans son chemin.
#
# CE QU'ELLE EXIGE, ET POURQUOI CE N'EST PAS « >= 1 ». La reference n'est pas une constante
# mais les SOURCES : chaque `game_custom_text_<lang>.json` qui definit "17e7" promet une
# variante tactile. La porte compte ces promesses et exige autant de bancs livres qui la
# tiennent. Ajouter une traduction fait monter les deux cotes ; en perdre une fait ECHOUER
# l'empaquetage. Un seuil fixe, lui, aurait laisse passer sept langues perdues sur huit.
touch_variant_gate(){
  python3 - "$1" "$TEXT_SRC" <<'PYGATE'
import glob, json, os, struct, sys, zipfile
src, text_src = sys.argv[1], sys.argv[2]

def bank_ids(name, d):
    tag, length, ver = struct.unpack_from('<III', d, 0)
    if tag != 0xFFFFFFFF or ver != 2:
        raise ValueError('%s: not a V2 linked object (tag=%08x ver=%d)' % (name, tag, ver))
    w = lambda i: struct.unpack_from('<I', d, length + 4 * i)[0]
    n, lang, out = w(1), w(2), {}
    for k in range(n):
        tid, ptr = w(4 + 2 * k), w(5 + 2 * k)
        off = length + ptr + 4
        out[tid] = d[off:d.index(b'\x00', off)]
    return lang, n, out

# Les bancs viennent SOIT du fermage de symlinks qu'on s'apprete a zipper, SOIT du zip deja
# sur le disque quand le repack est saute. Les deux passent par la MEME porte : un paquet
# qu'on ne reconstruit pas n'est pas un paquet qu'on n'a pas besoin de regarder.
def banks(src):
    if os.path.isdir(src):
        for p in sorted(glob.glob(os.path.join(src, '*COMMON.TXT'))):
            yield os.path.basename(p), open(p, 'rb').read()
    else:
        with zipfile.ZipFile(src) as z:
            for nm in sorted(x for x in z.namelist() if x.endswith('COMMON.TXT')):
                yield os.path.basename(nm), z.read(nm)

TOUCH, PLAIN = 0x17e7, 0x16e
want = sorted(os.path.basename(p) for p in glob.glob(os.path.join(text_src, 'game_custom_text_*.json'))
              if '%x' % TOUCH in json.load(open(p, encoding='utf-8')))
got, bad, seen = [], [], 0
for name, data in banks(src):
    seen += 1
    try:
        lang, n, ids = bank_ids(name, data)
    except Exception as e:
        bad.append('%s: illisible (%s)' % (name, e)); continue
    t = ids.get(TOUCH)
    if t is None:
        continue
    if not t:
        bad.append('%s (langue %d): #x17e7 est VIDE' % (name, lang)); continue
    if t == ids.get(PLAIN):
        bad.append('%s (langue %d): #x17e7 == #x16e, la variante tactile n\'existe pas' %
                   (name, lang)); continue
    got.append(lang)
print('[cgo-pack] touch-variant [%s]: %d banc(s) sur %d lus portent #x17e7 distinct de #x16e '
      '(langues %s) ; %d source(s) le promettent (%s)'
      % (src, len(got), seen, ','.join(str(l) for l in sorted(got)) or '-', len(want),
         ' '.join(s.replace('game_custom_text_', '').replace('.json', '') for s in want) or '-'))
for b in bad:
    print('[cgo-pack]   DEFAUT: ' + b, file=sys.stderr)
if bad:
    sys.exit(1)
# LE PLANCHER DE VACUITE. Sans lui, une source qui ne rend AUCUN banc (chemin faux, structure
# du zip changee) donnerait got=[] — et la porte accuserait la variante tactile au lieu
# d'accuser son propre instrument.
if seen == 0:
    print('[cgo-pack]   DEFAUT: aucun banc *COMMON.TXT lu dans %s — c\'est la PORTE qui est '
          'aveugle, pas forcement le paquet' % src, file=sys.stderr)
    sys.exit(1)
if len(want) == 0:
    print('[cgo-pack]   DEFAUT: aucune source ne definit "17e7" — la variante tactile a disparu '
          'des sources, pas seulement du paquet', file=sys.stderr)
    sys.exit(1)
if len(got) < len(want):
    print('[cgo-pack]   DEFAUT: %d banc(s) portent la variante tactile pour %d source(s) qui la '
          'promettent — le texte partirait degrade, en silence, sur un appareil sans bouton start'
          % (len(got), len(want)), file=sys.stderr)
    sys.exit(1)
PYGATE
}

WANT_FC=$((N_CODE + N_DTXT))

# Content-derived VERSION (md5 of all pack member contents), like
# build_asset_bundle.sh — any code/text change forces on-device re-unpack.
VERSION="${CGO_PACK_VERSION:-}"
if [ -z "$VERSION" ]; then
  # Hash the EFFECTIVE member contents: arm64 code + every TXT bank. There is exactly
  # one source per member now that the override overlay is gone, so this list is the
  # staging loops below, read twice. `.autoport/lib/release_verify.sh` recomputes the
  # same hash from the APK: keep the two in step.
  VERSION="c$( {
      for f in "${CODE_FILES[@]}"; do printf '%s\0' "$ARM64_CODE/$f"; done
      for f in "${DESKTOP_TXT[@]}"; do printf '%s\0' "$ISO_BUILD/$f"; done
    } | sort -z | xargs -0 md5sum | md5sum | cut -c1-12 )"
fi

mkdir -p "$OUT_DIR"

# All source trees whose mtimes gate a repack (ISO_BUILD gates the desktop TXT
# banks; over-invalidation from unrelated iso files is safe, stale reuse is not).
SRC_DIRS=("$ARM64_CODE" "$ISO_BUILD")

# --- Staleness skip: zip current vs all sources AND version+count match. ---
if [ -f "$ZIP_REL" ] && [ -f "$MANIFEST" ]; then
  newest=$(find "${SRC_DIRS[@]}" -type f -printf '%T@\n' 2>/dev/null | awk 'BEGIN{m=0}{t=int($1); if(t>m)m=t} END{print m}')
  zmt=$(stat -c %Y "$ZIP_REL")
  cv=$(grep -E '^version=' "$MANIFEST" | cut -d= -f2 || echo "")
  cfc=$(grep -E '^file_count=' "$MANIFEST" | cut -d= -f2 || echo "")
  if [ -n "$newest" ] && [ "$zmt" -ge "$newest" ] && [ "$cv" = "$VERSION" ] && [ "$cfc" = "$WANT_FC" ]; then
    # LA PORTE TOURNE AUSSI QUAND ON NE REPACKE PAS. Sans cette ligne elle etait
    # CONDITIONNELLE a un repack, et c'est exactement la condition qui manque le jour ou ca
    # compte : l'ANCIENNE formule de `version` (celle qui hachait l'overlay) devient
    # IDENTIQUE a la nouvelle des que l'overlay etait DROP — c'est-a-dire pendant tout
    # l'incident. Un zip fabrique a cette epoque presente donc la bonne `version`, le
    # repack est saute, et il repart vers l'APK sans que rien ne l'ait regarde. On lit le
    # zip LUI-MEME, jamais les sources dont il est cense sortir.
    touch_variant_gate "$ZIP_REL" || fail "le paquet deja sur le disque ne porte pas la variante tactile (voir ci-dessus). L'empaquetage ECHOUE au lieu de le relivrer tel quel."
    echo "[cgo-pack] up to date: $ZIP_REL (version=$VERSION file_count=$cfc)"
    exit 0
  fi
fi

echo "[cgo-pack] assembling arm64 CGO pack for $GAME (symlink farm)…"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# 1. arm64 code files at zip root.
for f in "${CODE_FILES[@]}"; do
  ln -s "$ROOT/$ARM64_CODE/$f" "$STAGE/$f"
done

# 2. ALL rebuilt TXT banks at zip root. One source, no overlay.
for f in "${DESKTOP_TXT[@]}"; do
  ln -s "$ROOT/$ISO_BUILD/$f" "$STAGE/$f"
done
echo "[cgo-pack] text banks: $N_DTXT"

# The touch-variant gate runs HERE, on the STAGED banks — the bytes that go into the zip,
# never the sources they were built from. A gate that read the sources would have passed
# every single time the overlay shipped a frozen bank.
touch_variant_gate "$STAGE" || fail "la variante tactile n'est pas dans les bancs a empaqueter (voir ci-dessus). L'empaquetage ECHOUE au lieu de livrer un texte degrade en silence."

# --- HARD completeness + consistency gates ---
got=$(find -L "$STAGE" -type f | wc -l | tr -d ' ')
[ "$got" -eq "$WANT_FC" ] || fail "staged $got files != expected $WANT_FC"

# arm64 consistency: KERNEL.CGO must be the arm64 build, NOT the x86 oracle.
k_stg=$(md5sum "$STAGE/KERNEL.CGO" | cut -d' ' -f1)
k_arm=$(md5sum "$ARM64_CODE/KERNEL.CGO" | cut -d' ' -f1)
[ "$k_stg" = "$k_arm" ] || fail "staged KERNEL.CGO != arm64 build (mixed/stale code)"
if [ -f "$ISO_BUILD/KERNEL.CGO" ]; then
  k_x86=$(md5sum "$ISO_BUILD/KERNEL.CGO" | cut -d' ' -f1)
  [ "$k_stg" != "$k_x86" ] || fail "staged KERNEL.CGO == x86 oracle (would SIGILL on the arm64 device)"
fi
echo "[cgo-pack] completeness OK: code=$N_CODE text=$N_DTXT; arm64 KERNEL.CGO verified."

RAW_BYTES=$(find -L "$STAGE" -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')
FILE_COUNT=$(find -L "$STAGE" -type f | wc -l | tr -d ' ')
[ "$FILE_COUNT" -eq "$WANT_FC" ] || fail "assembled $FILE_COUNT files, expected $WANT_FC"

echo "[cgo-pack] packing $FILE_COUNT files → $ZIP_REL (DEFLATE)…"
rm -f "$ZIP_ABS"
# -6 balanced DEFLATE (CGOs compress well); -X drop extra metadata; -q quiet.
# zip dereferences the farm symlinks and stores real content at the flat entry name.
(
  cd "$STAGE"
  zip -6 -X -q "$ZIP_ABS" ./*
)

ZIP_BYTES=$(stat -c %s "$ZIP_ABS")

# Grecharged-buildsys-flags: record the flag-set marker compiled into the CGOs
# (GAME.CGO carries "ogflags:<flag-hash>:<target>"); release_verify pairs it with
# the libgk.so marker so a mixed flag-set APK is refused (risk R1).
FLAG_MARKER=$(grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' "$ARM64_CODE/GAME.CGO" 2>/dev/null | head -1 || true)

cat > "$MANIFEST" <<EOF
# Generated by android/build_cgo_pack.sh — do not edit.
version=${VERSION}
game=${GAME}
file_count=${FILE_COUNT}
raw_bytes=${RAW_BYTES}
zip_bytes=${ZIP_BYTES}
flags=${FLAG_MARKER}
text_banks=${N_DTXT}
EOF

rm -rf "$STAGE"   # the symlink farm is transient; the zip + manifest are the artifacts

echo "[cgo-pack] done: ${ZIP_REL}"
echo "[cgo-pack]   files=${FILE_COUNT} (code=${N_CODE} txt=${N_DTXT})  raw=${RAW_BYTES}B  zip=${ZIP_BYTES}B  version=${VERSION}"
