#!/usr/bin/env bash
# census/grass-bake-invalidation.sh — CE QUE LA COURSE DE JEU NE PEUT PAS DIRE.
#
# La course x86 prouve que la garde de fraicheur vit DANS le moteur et qu'elle compare des
# EMPREINTES : elle charge `training`, resout son bake et publie `grass_bake_engine_*` +
# `FEATURE ... armed=1 hits=<comparaisons d'empreinte faites>`. Elle ne peut rien dire des trois
# autres points du contrat, parce qu'un `gk` ne recuit RIEN et ne voit qu'un seul niveau :
#
#   2. DECLENCHEMENT AUTOMATIQUE — c'est le build de LIVRAISON qui appelle la cuisson.
#   3. REBAKE CIBLE — le temps d'une recuisson ciblee contre celui d'une recuisson totale.
#   4. LE TEMOIN A DEUX BRAS — un `.fr3` de meme TAILLE et de contenu different.
#
# LE CODE EST LE MEME DES DEUX COTES. `grass_bake::bake_freshness()` vit dans GrassBakeCore.cpp,
# compile a la fois dans `gk` et dans `tools/grass_bake` (meme .cpp). Ce recensement l'appelle hors
# ligne par `grass_bake --freshness`, par la PORTE de l'arbre — qui repare `.ninja_deps` et sort en
# 4 sur un binaire plus vieux que ses entrees, donc ce bras ne peut pas etre un vieux binaire.
#
# IL N'ECRIT RIEN DANS LA DONNEE LIVREE. Tout ce qui se recuit ici se recuit dans un bac a sable
# jetable ; `out/jak1/fr3/` n'est JAMAIS ouvert en ecriture par ce script.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
ROOT=$PWD
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"
mkdir -p "$TMPDIR" || exit 1

T=$(mktemp -d "$TMPDIR/grass-bake-inval.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census grass-bake-invalidation: %s\n' "$*" >&2; exit 1; }

bash .autoport/lib/build_x86.sh --target grass_bake > "$T/build.log" 2>&1 \
  || die "build_x86.sh --target grass_bake a rendu $? (voir $T/build.log)"
BIN="$ROOT/build/tools/grass_bake/grass_bake"
[ -x "$BIN" ] || die "$BIN absent apres la porte."

FR3="$ROOT/out/jak1/fr3"
[ -d "$FR3" ] || die "$FR3 absent."

# --- LES NIVEAUX ET LES PALIERS : lus dans le moteur, jamais recopies (meme regle que le
# --- producteur, scripts/shell/build_grass_bakes.sh).
HDR="$ROOT/game/graphics/opengl_renderer/background/background_common.h"
LEVELS=$(grep -oP 'kGrassLevels\[\]\s*=\s*\{\K[^}]*' "$HDR" | tr -d '" ' | tr ',' '\n' | sed '/^$/d')
[ -n "$LEVELS" ] || die "kGrassLevels illisible dans $HDR"
PHDR="$ROOT/game/graphics/grass_density_presets.h"
SLUGS=$(grep -oP '^\s*\{"\K[a-z-]+(?=", ")' "$PHDR")
[ -n "$SLUGS" ] || die "table des paliers illisible dans $PHDR"

# `--freshness` rend ses verdicts en `cle=valeur`. Ce lecteur est la SEULE facon dont ce script
# apprend un verdict : il n'en devine aucun.
fresh_key(){ sed -n "s/^$2=//p" "$1" | head -1; }

# ======================================================================================
# 1. EMPREINTE DE CONTENU — LES BAKES LIVRES, PAIRE PAR PAIRE.
# ======================================================================================
: > "$T/pairs.tsv"
for lv in $LEVELS; do
  for sg in $SLUGS; do
    bake="$FR3/$lv.$sg.grassbake"
    if [ ! -s "$bake" ]; then
      printf '%s\t%s\tabsent\t1\t0\t0\t0\t0\tbake-absent\n' "$lv" "$sg" >> "$T/pairs.tsv"
      continue
    fi
    prov=0; [ -s "$bake.fp" ] && prov=1
    if ! "$BIN" "$lv" --fr3-dir "$FR3" --preset "$sg" --freshness "$bake" > "$T/$lv.$sg.fresh" 2>"$T/$lv.$sg.err"; then
      printf '%s\t%s\toutil\t1\t%s\t0\t0\t0\trc-non-nul\n' "$lv" "$sg" "$prov" >> "$T/pairs.tsv"
      continue
    fi
    printf '%s\t%s\tlu\t%s\t%s\t%s\t%s\t%s\t%s\n' "$lv" "$sg" \
      "$(fresh_key "$T/$lv.$sg.fresh" freshness_stale)" "$prov" \
      "$(fresh_key "$T/$lv.$sg.fresh" freshness_comparisons)" \
      "$(fresh_key "$T/$lv.$sg.fresh" freshness_fp_read)" \
      "$(fresh_key "$T/$lv.$sg.fresh" freshness_fp_expected)" \
      "$(fresh_key "$T/$lv.$sg.fresh" freshness_reason)" >> "$T/pairs.tsv"
  done
done

# ======================================================================================
# 4. LE TEMOIN A DEUX BRAS — UN .fr3 DE MEME TAILLE ET DE CONTENU DIFFERENT.
# ======================================================================================
# Le bras « AVANT » est la garde de TAILLE, gardee mot pour mot dans `bake_freshness` sous
# `legacy_size_guard`. Il doit LAISSER PASSER le fichier trafique : c'est le defaut qui REVIENT,
# compte, et non un zero muet. Le bras LIVRE doit le refuser.
WLV=$(printf '%s\n' $LEVELS | head -1)
WSG=medium
printf '%s\n' $SLUGS | grep -qx "$WSG" || WSG=$(printf '%s\n' $SLUGS | head -1)
A="$T/witnessA"; mkdir -p "$A"
W_READY=0
if [ -s "$FR3/$WLV.fr3" ] && [ -s "$FR3/$WLV.$WSG.grassbake" ] && [ -s "$FR3/$WLV.$WSG.grassbake.fp" ]; then
  cp "$FR3/$WLV.fr3" "$A/$WLV.fr3"
  cp "$FR3/$WLV.$WSG.grassbake" "$A/"
  cp "$FR3/$WLV.$WSG.grassbake.fp" "$A/"
  # UN octet retourne au milieu du fichier. La taille ne bouge pas d'un bit : c'est exactement le
  # cas que la garde d'avant ne pouvait pas voir.
  python3 - "$A/$WLV.fr3" <<'PY'
import sys
p = sys.argv[1]
with open(p, 'r+b') as f:
    f.seek(0, 2); n = f.tell()
    off = n // 2
    f.seek(off); b = f.read(1)[0]
    f.seek(off); f.write(bytes([b ^ 0xFF]))
PY
  SZ_REF=$(stat -c %s "$FR3/$WLV.fr3"); SZ_DOC=$(stat -c %s "$A/$WLV.fr3")
  [ "$SZ_REF" = "$SZ_DOC" ] && W_READY=1
fi
W_SIZE_STALE=-1; W_FP_STALE=-1; W_FP_COMPARISONS=-1; W_SIZE_COMPARISONS=-1; W_FP_REASON="-"
if [ "$W_READY" = 1 ]; then
  "$BIN" "$WLV" --fr3-dir "$A" --preset "$WSG" --freshness "$A/$WLV.$WSG.grassbake" \
        --legacy-size-guard > "$T/wa-size.txt" 2>&1 \
    && { W_SIZE_STALE=$(fresh_key "$T/wa-size.txt" freshness_stale)
         W_SIZE_COMPARISONS=$(fresh_key "$T/wa-size.txt" freshness_comparisons); }
  "$BIN" "$WLV" --fr3-dir "$A" --preset "$WSG" --freshness "$A/$WLV.$WSG.grassbake" \
        > "$T/wa-fp.txt" 2>&1 \
    && { W_FP_STALE=$(fresh_key "$T/wa-fp.txt" freshness_stale)
         W_FP_COMPARISONS=$(fresh_key "$T/wa-fp.txt" freshness_comparisons)
         W_FP_REASON=$(fresh_key "$T/wa-fp.txt" freshness_reason); }
fi

# ======================================================================================
# 2 + 3. DECLENCHEMENT AUTOMATIQUE, ET RECUISSON CIBLEE CONTRE TOTALE.
# ======================================================================================
# Bac a sable B : le `.fr3` est INTACT (donc decodable, donc recuisable) et c'est la PROVENANCE
# d'une seule paire qui porte une empreinte qui ne correspond plus — ce qu'un `.fr3` reconstruit
# produit. On mesure le cycle complet : refuse -> recuit -> accepte.
B="$T/sandboxB"; mkdir -p "$B"
B_READY=0
if [ -s "$FR3/$WLV.fr3" ]; then
  ln -s "$FR3/$WLV.fr3" "$B/$WLV.fr3"
  n_copy=0
  for sg in $SLUGS; do
    if [ -s "$FR3/$WLV.$sg.grassbake" ] && [ -s "$FR3/$WLV.$sg.grassbake.fp" ]; then
      cp "$FR3/$WLV.$sg.grassbake" "$FR3/$WLV.$sg.grassbake.fp" "$B/"
      n_copy=$((n_copy + 1))
    fi
  done
  if [ -s "$B/$WLV.$WSG.grassbake.fp" ]; then
    sed -i 's/^fr3_fp=.*/fr3_fp=deadbeefdeadbeef/' "$B/$WLV.$WSG.grassbake.fp"
    B_READY=1
  fi
fi
B_COPIED=${n_copy:-0}
B_REFUSED=-1; B_AFTER=-1
B_EXAMINED=-1; B_STALE=-1; B_BAKED=-1; B_TARGET_MS=-1; B_FULL_MS=-1; B_FULL_BAKED=-1
B_IDEMPOTENT=-1; B_RECUIT_LIST="-"
if [ "$B_READY" = 1 ]; then
  "$BIN" "$WLV" --fr3-dir "$B" --preset "$WSG" --freshness "$B/$WLV.$WSG.grassbake" \
        > "$T/wb-before.txt" 2>&1 && B_REFUSED=$(fresh_key "$T/wb-before.txt" freshness_stale)

  t0=$(date +%s%N)
  bash scripts/shell/build_grass_bakes.sh --only-stale --fr3-dir "$B" > "$T/targeted.log" 2>&1
  rc_t=$?
  t1=$(date +%s%N)
  [ "$rc_t" = 0 ] && B_TARGET_MS=$(( (t1 - t0) / 1000000 ))
  B_EXAMINED=$(sed -n 's/.*paires_examinees=\([0-9]*\).*/\1/p' "$T/targeted.log" | tail -1)
  B_STALE=$(sed -n 's/.*paires_perimees=\([0-9]*\).*/\1/p' "$T/targeted.log" | tail -1)
  B_BAKED=$(sed -n 's/.*paires_recuites=\([0-9]*\).*/\1/p' "$T/targeted.log" | tail -1)
  B_RECUIT_LIST=$(grep -o 'recuit niveau=[^ ]* palier=[^ ]*' "$T/targeted.log" \
                  | sed 's/recuit niveau=//; s/ palier=/./' | paste -sd, -)

  "$BIN" "$WLV" --fr3-dir "$B" --preset "$WSG" --freshness "$B/$WLV.$WSG.grassbake" \
        > "$T/wb-after.txt" 2>&1 && B_AFTER=$(fresh_key "$T/wb-after.txt" freshness_stale)

  # RIEN NE SE RECUIT DEUX FOIS : une seconde passe ciblee sur un bac a sable frais doit recuire 0.
  bash scripts/shell/build_grass_bakes.sh --only-stale --fr3-dir "$B" > "$T/idem.log" 2>&1 \
    && B_IDEMPOTENT=$(sed -n 's/.*paires_recuites=\([0-9]*\).*/\1/p' "$T/idem.log" | tail -1)

  # LA RECUISSON TOTALE — celle d'avant, la seule qui existait. Mesuree sur le MEME bac a sable,
  # avec le MEME outil, a la suite : la comparaison ne traverse pas deux machines.
  t2=$(date +%s%N)
  bash scripts/shell/build_grass_bakes.sh --fr3-dir "$B" > "$T/full.log" 2>&1
  rc_f=$?
  t3=$(date +%s%N)
  [ "$rc_f" = 0 ] && B_FULL_MS=$(( (t3 - t2) / 1000000 ))
  B_FULL_BAKED=$(sed -n 's/.*paires_recuites=\([0-9]*\).*/\1/p' "$T/full.log" | tail -1)
fi

# Le CABLAGE : la cuisson est-elle appelee par le build de livraison, ou attend-elle une main ?
# On compte le NOEUD D'APPEL (une ligne qui lance le script), pas une mention en commentaire.
WIRED_PREP=$(grep -cE '^[^#]*build_grass_bakes\.sh' .autoport/prepare_delivery_bakes.sh 2>/dev/null || echo 0)
WIRED_APK=$(grep -cE '^[^#]*prepare_delivery_bakes\.sh' .autoport/auto_build_apk.sh 2>/dev/null || echo 0)
WIRED_PACK=$(grep -cE '^[^#]*freshness' android/build_custom_pack.sh 2>/dev/null || echo 0)

# ======================================================================================
# L'AGREGATION. Chaque terme est publie SEPAREMENT puis somme ; `grass_bake_stale_defects` est la
# somme de grandeurs qu'on peut relire une par une, jamais un chiffre isole.
# ======================================================================================
python3 - "$T/pairs.tsv" <<PY || die "agregation en echec"
import sys

pairs = []
for line in open(sys.argv[1], encoding="utf-8"):
    f = line.rstrip("\n").split("\t")
    if len(f) == 9:
        pairs.append(f)

def i(v, d=-1):
    try:
        return int(v)
    except (TypeError, ValueError):
        return d

W_READY = $W_READY
W_SIZE_STALE = i("$W_SIZE_STALE")
W_FP_STALE = i("$W_FP_STALE")
W_FP_COMP = i("$W_FP_COMPARISONS")
W_SIZE_COMP = i("$W_SIZE_COMPARISONS")
B_READY = $B_READY
B_COPIED = i("$B_COPIED")
B_REFUSED = i("$B_REFUSED")
B_AFTER = i("$B_AFTER")
B_EXAMINED = i("$B_EXAMINED")
B_STALE = i("$B_STALE")
B_BAKED = i("$B_BAKED")
B_IDEM = i("$B_IDEMPOTENT")
B_TARGET_MS = i("$B_TARGET_MS")
B_FULL_MS = i("$B_FULL_MS")
B_FULL_BAKED = i("$B_FULL_BAKED")
WIRED_PREP = i("$WIRED_PREP", 0)
WIRED_APK = i("$WIRED_APK", 0)
WIRED_PACK = i("$WIRED_PACK", 0)

# ---- 1. EMPREINTE DE CONTENU : l'etat des bakes LIVRES, publie par paire.
n_pairs = len(pairs)
d_prov_missing = 0
d_delivered_stale = 0
d_no_fp_compared = 0
for lv, sg, state, stale, prov, comp, fpr, fpe, why in pairs:
    print("grass_bake_pair_%s_%s_stale=%s" % (lv, sg.replace("-", "_"), i(stale)))
    print("grass_bake_pair_%s_%s_provenance=%s" % (lv, sg.replace("-", "_"), i(prov)))
    print("grass_bake_pair_%s_%s_comparisons=%s" % (lv, sg.replace("-", "_"), i(comp)))
    print("grass_bake_pair_%s_%s_fp_read=%s" % (lv, sg.replace("-", "_"), fpr or "0"))
    print("grass_bake_pair_%s_%s_fp_expected=%s" % (lv, sg.replace("-", "_"), fpe or "0"))
    print("grass_bake_pair_%s_%s_reason=%s" % (lv, sg.replace("-", "_"), (why or "-")))
    if i(prov) != 1:
        d_prov_missing += 1
    if i(stale) != 0:
        d_delivered_stale += 1
    # UNE GARDE QUI NE COMPARE AUCUNE EMPREINTE EST UNE GARDE DE TAILLE DEGUISEE.
    if i(comp) < 2:
        d_no_fp_compared += 1

print("grass_bake_pairs_examined=%d" % n_pairs)
print("grass_bake_pairs_provenance_ok=%d" % (n_pairs - d_prov_missing))

# ---- 4. LE TEMOIN A DEUX BRAS, LES DEUX VERDICTS COTE A COTE.
print("grass_bake_witness_ready=%d" % W_READY)
print("grass_bake_witness_size_arm_stale=%d" % W_SIZE_STALE)
print("grass_bake_witness_size_arm_comparisons=%d" % W_SIZE_COMP)
print("grass_bake_witness_fp_arm_stale=%d" % W_FP_STALE)
print("grass_bake_witness_fp_arm_comparisons=%d" % W_FP_COMP)
d_witness_absent = 0 if W_READY == 1 else 1
# Le defaut DOIT revenir dans le bras d'avant, sinon le temoin ne mesure rien.
d_witness_not_reproduced = 0 if W_SIZE_STALE == 0 else 1
d_witness_fp_accepted = 0 if W_FP_STALE == 1 else 1
d_witness_size_read_a_fp = 0 if W_SIZE_COMP == 0 else 1

# ---- 2. DECLENCHEMENT AUTOMATIQUE : le cycle refuse -> recuit -> accepte, et le cablage.
print("grass_bake_autobake_ready=%d" % B_READY)
print("grass_bake_autobake_bakes_copied=%d" % B_COPIED)
print("grass_bake_autobake_refused_before=%d" % B_REFUSED)
print("grass_bake_autobake_examined=%d" % B_EXAMINED)
print("grass_bake_autobake_stale=%d" % B_STALE)
print("grass_bake_autobake_rebaked=%d" % B_BAKED)
print("grass_bake_autobake_rebaked_list=$B_RECUIT_LIST")
print("grass_bake_autobake_fresh_after=%d" % (1 if B_AFTER == 0 else 0))
print("grass_bake_autobake_second_pass_rebaked=%d" % B_IDEM)
print("grass_bake_wired_prepare_delivery=%d" % WIRED_PREP)
print("grass_bake_wired_build_apk=%d" % WIRED_APK)
print("grass_bake_wired_pack_guard=%d" % WIRED_PACK)
d_autobake_absent = 0 if B_READY == 1 else 1
d_autobake_not_refused = 0 if B_REFUSED == 1 else 1
d_autobake_not_rebaked = 0 if B_BAKED == 1 else 1
d_autobake_still_stale = 0 if B_AFTER == 0 else 1
d_autobake_not_idempotent = 0 if B_IDEM == 0 else 1
d_not_wired = (1 if WIRED_PREP < 1 else 0) + (1 if WIRED_APK < 1 else 0) + (1 if WIRED_PACK < 1 else 0)

# ---- 3. REBAKE CIBLE : le temps de la recuisson ciblee contre celui de la totale.
print("grass_bake_targeted_ms=%d" % B_TARGET_MS)
print("grass_bake_full_ms=%d" % B_FULL_MS)
print("grass_bake_full_rebaked=%d" % B_FULL_BAKED)
print("grass_bake_targeted_saved_ms=%d" % (B_FULL_MS - B_TARGET_MS if B_FULL_MS > 0 and B_TARGET_MS > 0 else -1))
# « non nul, plus court » : les deux durees doivent exister ET la ciblee doit etre la plus courte.
d_targeted_not_measured = 0 if (B_TARGET_MS > 0 and B_FULL_MS > 0) else 1
d_targeted_not_shorter = 0 if (B_TARGET_MS > 0 and B_FULL_MS > 0 and B_TARGET_MS < B_FULL_MS) else 1
# Le ciblage ne doit pas recuire ce qui n'etait pas perime.
d_targeted_overreach = max(0, B_BAKED - B_STALE) if (B_BAKED >= 0 and B_STALE >= 0) else 1
d_full_not_total = 0 if (B_FULL_BAKED == B_EXAMINED and B_EXAMINED > 0) else 1

# ---- NON-VACUITE : une population vide rendrait tous les zeros ci-dessus gratuits.
d_population_empty = 1 if n_pairs == 0 else 0

terms = [
    ("provenance_missing", d_prov_missing),
    ("delivered_stale", d_delivered_stale),
    ("no_fingerprint_compared", d_no_fp_compared),
    ("witness_absent", d_witness_absent),
    ("witness_not_reproduced", d_witness_not_reproduced),
    ("witness_fp_accepted", d_witness_fp_accepted),
    ("witness_size_arm_read_a_fp", d_witness_size_read_a_fp),
    ("autobake_absent", d_autobake_absent),
    ("autobake_not_refused", d_autobake_not_refused),
    ("autobake_not_rebaked", d_autobake_not_rebaked),
    ("autobake_still_stale", d_autobake_still_stale),
    ("autobake_not_idempotent", d_autobake_not_idempotent),
    ("not_wired", d_not_wired),
    ("targeted_not_measured", d_targeted_not_measured),
    ("targeted_not_shorter", d_targeted_not_shorter),
    ("targeted_overreach", d_targeted_overreach),
    ("full_not_total", d_full_not_total),
    ("population_empty", d_population_empty),
]
for name, v in terms:
    print("grass_bake_stale_d_%s=%d" % (name, v))
print("grass_bake_stale_terms_measured=%d" % len(terms))
print("grass_bake_stale_defects=%d" % sum(v for _, v in terms))
PY
exit 0
