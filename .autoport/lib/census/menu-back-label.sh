#!/usr/bin/env bash
# census/menu-back-label.sh — LA MOITIE QUE LE JEU NE PEUT PAS VOIR, pour l'item `menu-back-label`.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), APRES la course. Sa
# sortie `cle=valeur` rejoint celle du moteur dans le MEME journal, et la DERNIERE valeur d'une cle
# gagne. Il n'ecrit aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`.
#
# LE PARTAGE DES ROLES, ET POURQUOI C'EST LUI QUI PUBLIE LA CLE DE LA PORTE.
# Le moteur recense ce qu'il DESSINE, dans la langue CHARGEE : une par course. Le livrable exige
# la verification dans CHAQUE langue installee — 23 bancs `<n>COMMON.TXT`, que le jeu ne charge
# pas. Le moteur publie donc `menu_label_engine_wrong`, sa moitie ; ce script lit les 23 bancs et
# publie le TOTAL sous `menu_label_wrong`. Si ce script ne tourne pas, la cle de la porte MANQUE et
# le validateur est rouge — au lieu d'etre vert par silence sur toute la dimension langue.
#
# POLARITE, NON NEGOCIABLE : TOUT INCONNU VAUT DEFAUT. Banc illisible, valeur du moteur absente ou
# non numerique, temoin a zero : on publie une valeur NON NULLE qui ferme la porte, jamais un zero
# par silence. Le script sort en 0 meme quand il accuse — c'est le validateur qui juge.
#
# LE PIEGE DE LA RELECTURE. La sortie de ce script est APPENDUE au journal brut de la course,
# celui-la meme ou le moteur publie ses `menu_label_*`. Un `grep` sur ce journal apres ecriture
# relirait donc nos propres lignes. On prend un INSTANTANE du journal AVANT d'ecrire quoi que ce
# soit : ce qu'on ajoute ensuite ne peut pas s'y trouver, quelle que soit la bufferisation.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "menu_label_wrong=9001"; exit 1; }
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "$2"; }
REASONS=""
note(){ REASONS="${REASONS:+$REASONS;}$1"; }
PENALTY=0

SNAP=$(mktemp) || { echo "menu_label_wrong=9002"; exit 1; }
trap 'rm -f "$SNAP" "$SNAP.norm"' EXIT
if [ -n "${AUTOPORT_CENSUS_DIR:-}" ]; then
  cat "$AUTOPORT_CENSUS_DIR"/proof*-engine.log > "$SNAP" 2>/dev/null
fi

# LA NORMALISATION DU PREFIXE. Rien n'arrive nu : sur x86 le journal prefixe chaque ligne du temps
# ecoule, sur l'APPAREIL `logcat -v time` prefixe la date, le niveau, le tag et le pid. Recopiee de
# `norm()` de `lib/proof_run.sh` et NON appelee : ce script tourne dans son propre shell, et une
# fonction qu'on croit heritee rend la tranche muette au lieu de rouge.
sed -E 's/\r$//
        s/^[0-9]{2}-[0-9]{2} [0-9:.]+ +[A-Z]\/[^(]*\( *[0-9]+\): *//
        s/^[[:space:]]*[0-9]+\.[0-9]+[[:space:]]+//
        s/^\[[0-9:]+\] *//' "$SNAP" > "$SNAP.norm" 2>/dev/null

eng(){ # eng <cle> : la valeur publiee par le moteur, "" si absente
  grep -ahE "^$1=[-0-9]+$" "$SNAP.norm" 2>/dev/null | tail -1 | sed "s/^$1=//"
}

ENG_WRONG=$(eng menu_label_engine_wrong)
ENG_ROWS=$(eng menu_label_rows)
ENG_LOGGED=$(eng menu_label_logged)
ENG_LANG=$(eng menu_label_bank_language)
ENG_SEED_CAUGHT=$(eng menu_label_seed_caught)
ENG_SEED_FALSE=$(eng menu_label_seed_false)
ENG_SEED_BACK=$(eng menu_label_seed_back_ok)
ENG_YESNO=$(eng menu_label_yesno_ok)
ENG_DYNPAGES=$(eng menu_label_dynamic_pages)

num(){ case "${1:-}" in ''|*[!-0-9]*) return 1 ;; *) return 0 ;; esac; }

# ── 1. LE MOTEUR A-T-IL PARLE ? ───────────────────────────────────────────────────────────────
if ! num "$ENG_WRONG"; then
  pub menu_label_engine_wrong -1
  note "valeur moteur menu_label_engine_wrong absente ou non numerique"
  PENALTY=$((PENALTY + 1000))
  ENG_WRONG=0
fi
num "$ENG_ROWS"   || { ENG_ROWS=0;   note "menu_label_rows absent";   PENALTY=$((PENALTY + 1000)); }
num "$ENG_LOGGED" || { ENG_LOGGED=0; note "menu_label_logged absent"; PENALTY=$((PENALTY + 1000)); }
num "$ENG_LANG"   || { ENG_LANG=-1;  note "menu_label_bank_language absent"; PENALTY=$((PENALTY + 1000)); }

# LES TEMOINS DE NON-VACUITE DU MOTEUR. Un zero obtenu « le comparateur ne regarde rien » se lit
# exactement comme un zero obtenu « tout est juste » : le controle SEME est ce qui les separe.
[ "${ENG_SEED_CAUGHT:-0}" = 1 ] || { note "controle seme NON attrape (seed_caught=${ENG_SEED_CAUGHT:--})"; PENALTY=$((PENALTY + 1000)); }
[ "${ENG_SEED_FALSE:-1}" = 0 ]  || { note "controle seme CORRECT accuse a tort (seed_false=${ENG_SEED_FALSE:--})"; PENALTY=$((PENALTY + 1000)); }
[ "${ENG_SEED_BACK:-0}" = 1 ]   || { note "la rangee temoin ne rend pas le Retour du banc (seed_back_ok=${ENG_SEED_BACK:--})"; PENALTY=$((PENALTY + 1000)); }
[ "${ENG_YESNO:-0}" = 1 ]       || { note "les ids OUI/NON ne resolvent pas (yesno_ok=${ENG_YESNO:--})"; PENALTY=$((PENALTY + 1000)); }
[ "${ENG_ROWS:-0}" -gt 100 ] 2>/dev/null || { note "menu_label_rows=$ENG_ROWS : le recensement n'a presque rien parcouru"; PENALTY=$((PENALTY + 1000)); }
[ "${ENG_DYNPAGES:-0}" -ge 7 ] 2>/dev/null || { note "menu_label_dynamic_pages=${ENG_DYNPAGES:--} : les pages baties a l'execution n'ont pas ete recensees"; PENALTY=$((PENALTY + 1000)); }
[ "${ENG_LOGGED:-0}" -ge "${ENG_ROWS:-0}" ] 2>/dev/null || { note "journal TRONQUE : $ENG_LOGGED lignes pour $ENG_ROWS rangees"; PENALTY=$((PENALTY + 1000)); }

# ── 2. LE TABLEAU DES COUPLES (identifiant demande, texte affiche) ────────────────────────────
OUT_DIR="${AUTOPORT_CENSUS_DIR:-.autoport/reports/menu-back-label}"
TSV="$OUT_DIR/menu-labels.tsv"
mkdir -p "$OUT_DIR" 2>/dev/null
grep -ahE '^MENULBL page=' "$SNAP.norm" 2>/dev/null \
  | sed -E 's/^MENULBL page=([^ ]+) row=([0-9]+) type=([0-9]+) id=([0-9]+) src=([a-z]+) ok=([0-9]+) text=\|(.*)\|$/\1\t\2\t\3\t\4\t\5\t\6\t\7/' \
  > "$TSV" 2>/dev/null
ROWS_LOGGED=$(grep -c . "$TSV" 2>/dev/null) || ROWS_LOGGED=0
pub menu_label_rows_logged "$ROWS_LOGGED"
pub menu_label_table "$TSV"
# CE QUE LE JOURNAL A PERDU EN ROUTE. Le moteur compte les lignes qu'il EMET
# (`menu_label_logged`) ; ce script compte celles qu'il RETROUVE. Sur l'appareil, `logcat` peut en
# jeter sous rafale. La difference ne fabrique pas de faux vert — le verdict par rangee vient du
# moteur, qui les a TOUTES vues — mais elle retrecit la population sur laquelle la verification
# multi-langues porte. Elle est donc PUBLIEE et NOMMEE, jamais laissee muette, et le denominateur
# de la verification (`menu_label_lang_ids`) est publie a cote.
DROPPED=$(( ${ENG_LOGGED:-0} - ROWS_LOGGED ))
[ "$DROPPED" -ge 0 ] || DROPPED=0
pub menu_label_rows_dropped "$DROPPED"
[ "$DROPPED" -eq 0 ] || note "$DROPPED ligne(s) MENULBL emises par le moteur et absentes du journal"

if [ "${ROWS_LOGGED:-0}" -lt 100 ]; then
  note "tableau des couples quasi vide ($ROWS_LOGGED lignes)"
  PENALTY=$((PENALTY + 1000))
fi

# ── 3. LES 23 BANCS, ET CE QUE CHAQUE LANGUE REND POUR CHAQUE IDENTIFIANT DEMANDE ──────────────
# Le format est celui que `game/system/settings_case_l10n.cpp:25-75` documente et lit :
#   [0..12) LinkHeaderV2 { type_tag=0xffffffff ; length ; version=2 } ; `length` = offset du corps
#   corps   +4 nombre d'entrees, +8 language-id, puis N couples { id ; renvoi vers la chaine }
#   chaine  a l'offset o du corps : u32 allocated-length, puis les octets, termines par 0
LANG_OUT=$(ISO_DIR="out/jak1/iso" TSV="$TSV" CUR_LANG="$ENG_LANG" python3 - <<'PY' 2>/dev/null
import os, struct, sys, glob

iso = os.environ["ISO_DIR"]
tsv = os.environ["TSV"]
try:
    cur = int(os.environ.get("CUR_LANG", "-1"))
except ValueError:
    cur = -1

def read_bank(path):
    d = open(path, "rb").read()
    if len(d) < 16:
        return None
    tag, ln, ver = struct.unpack_from("<III", d, 0)
    if ver != 2 or ln < 12 or ln >= len(d):
        return None
    body = ln
    count, lang = struct.unpack_from("<II", d, body + 4)
    if count > 100000 or body + 16 + 8 * count > len(d):
        return None
    out = {}
    for i in range(count):
        tid, ref = struct.unpack_from("<II", d, body + 16 + 8 * i)
        if ref == 0 or body + ref + 4 > len(d):
            continue
        start = body + ref + 4
        end = d.find(b"\x00", start)
        out[tid] = d[start:end if end >= 0 else len(d)]
    return lang, out

banks = {}
for p in sorted(glob.glob(os.path.join(iso, "*COMMON.TXT"))):
    base = os.path.basename(p)
    n = base[:-len("COMMON.TXT")]
    if not n.isdigit():
        continue
    r = read_bank(p)
    if r and r[0] == int(n) and r[1]:
        banks[int(n)] = r[1]

# Les identifiants que les rangees demandent au banc (src=bank), et le texte que le moteur a
# rapporte pour chacun dans la langue chargee.
want, drawn = set(), {}
try:
    for line in open(tsv, "rb"):
        f = line.rstrip(b"\n").split(b"\t")
        if len(f) < 7 or f[4] != b"bank":
            continue
        tid = int(f[3])
        if tid == 0:
            continue
        want.add(tid)
        drawn.setdefault(tid, f[6])
except OSError:
    pass

en = banks.get(0, {})
missing = fallback = empty = 0
missing_list = []
for tid in sorted(want):
    for lang, tbl in banks.items():
        v = tbl.get(tid)
        if v is None:
            if en.get(tid):
                fallback += 1
            else:
                missing += 1
                if len(missing_list) < 12:
                    missing_list.append("%d@%d" % (tid, lang))
        elif not v:
            empty += 1
            if len(missing_list) < 12:
                missing_list.append("vide:%d@%d" % (tid, lang))

# Le texte RAPPORTE par le moteur contre le texte du banc de SA langue : l'identite, mesuree sur
# l'artefact, sans passer par le juge du moteur.
mismatch = compared = 0
mismatch_list = []
cb = banks.get(cur)
if cb is not None:
    for tid, txt in drawn.items():
        ref = cb.get(tid)
        if ref is None:
            ref = en.get(tid)
        if ref is None:
            continue
        compared += 1
        if ref != txt:
            mismatch += 1
            if len(mismatch_list) < 8:
                mismatch_list.append(str(tid))

# LES DEUX TEMOINS DU LECTEUR DE BANC. Un identifiant qui DOIT etre la partout (`back` = #x13e) et
# un qui ne peut etre nulle part : sans eux, « aucun manquant » se lirait aussi bien sur un lecteur
# qui ne lit rien.
ctl_present = sum(1 for t in banks.values() if t.get(0x13e))
ctl_absent = sum(1 for t in banks.values() if 0x7ffff0 not in t)

print("langs=%d" % len(banks))
print("ids=%d" % len(want))
print("missing=%d" % missing)
print("empty=%d" % empty)
print("fallback=%d" % fallback)
print("mismatch=%d" % mismatch)
print("compared=%d" % compared)
print("ctl_present=%d" % ctl_present)
print("ctl_absent=%d" % ctl_absent)
print("missing_list=%s" % (",".join(missing_list) if missing_list else "-"))
print("mismatch_list=%s" % (",".join(mismatch_list) if mismatch_list else "-"))
PY
)
lv(){ printf '%s\n' "$LANG_OUT" | sed -n "s/^$1=//p" | tail -1; }

LANGS=$(lv langs); IDS=$(lv ids); MISSING=$(lv missing); LEMPTY=$(lv empty)
FALLBACK=$(lv fallback); MISMATCH=$(lv mismatch); COMPARED=$(lv compared)
CTLP=$(lv ctl_present); CTLA=$(lv ctl_absent)
for v in LANGS IDS MISSING LEMPTY FALLBACK MISMATCH COMPARED CTLP CTLA; do
  eval "x=\${$v:-}"
  num "$x" || { eval "$v=0"; note "lecture des bancs illisible ($v)"; PENALTY=$((PENALTY + 1000)); }
done
pub menu_label_langs "$LANGS"
pub menu_label_lang_ids "$IDS"
pub menu_label_lang_missing "$MISSING"
pub menu_label_lang_empty "$LEMPTY"
pub menu_label_lang_fallback "$FALLBACK"
pub menu_label_text_mismatch "$MISMATCH"
pub menu_label_text_compared "$COMPARED"
pub menu_label_lang_control_present "$CTLP"
pub menu_label_lang_control_absent "$CTLA"
pub menu_label_lang_missing_list "$(lv missing_list)"
pub menu_label_text_mismatch_list "$(lv mismatch_list)"

[ "${LANGS:-0}" -ge 20 ] 2>/dev/null || { note "seulement ${LANGS:-0} banc(s) de texte lisible(s) dans out/jak1/iso"; PENALTY=$((PENALTY + 1000)); }
[ "${IDS:-0}" -ge 20 ] 2>/dev/null   || { note "seulement ${IDS:-0} identifiant(s) demande(s) au banc : le tableau ne porte rien"; PENALTY=$((PENALTY + 1000)); }
[ "${CTLP:-0}" = "${LANGS:-0}" ]     || { note "temoin PRESENT : #x13e absent de $(( ${LANGS:-0} - ${CTLP:-0} )) banc(s)"; PENALTY=$((PENALTY + 1000)); }
[ "${CTLA:-0}" = "${LANGS:-0}" ]     || { note "temoin ABSENT : un id impossible a ete TROUVE"; PENALTY=$((PENALTY + 1000)); }
[ "${COMPARED:-0}" -ge 20 ] 2>/dev/null || { note "seulement ${COMPARED:-0} texte(s) compare(s) au banc de la langue chargee"; PENALTY=$((PENALTY + 1000)); }

# ── 4. LA FRAICHEUR DES BANCS LUS ─────────────────────────────────────────────────────────────
NEWEST=$(find out/jak1/iso -maxdepth 1 -name '*COMMON.TXT' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1)
pub menu_label_bank_newest_mtime "$(date -u -d "@${NEWEST%% *}" +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"

# ── 5. LA SOMME, ET SA POLARITE ───────────────────────────────────────────────────────────────
WRONG=$(( ENG_WRONG + MISSING + LEMPTY + MISMATCH + PENALTY ))
pub menu_label_census_penalty "$PENALTY"
pub menu_label_census_reason "${REASONS:--}"
pub menu_label_wrong "$WRONG"
exit 0
