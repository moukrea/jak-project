#!/usr/bin/env bash
# census/harness-copes-with-usage-pacing.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il n'ecrit aucun champ de `proof.txt` : sa sortie `cle=valeur` rejoint le journal de course.
#
# LA GRANDEUR : `paced_attempts_killed` = essais TUES ou COMPTES alors qu'un crochet de rythme
# (le frein d'usage de l'owner, `pacing-hook`) tournait sous le worker. Doit valoir 0.
#
# TROIS SOURCES, jamais une seule :
#   - LE BANC (`lib/pacing_selftest.py`) : le VRAI `run_attempt` sur un etat jetable, un faux
#     crochet qui « dort 60 min » (temps a l'echelle 1 s = 15 min), le code neuf ET le code
#     d'avant ancre par MARQUEUR. Controle positif (pas tue, temps freine publie), controle
#     negatif (worker fige SANS crochet : toujours tue), mort pendant la pause (ni comptee ni
#     empreintee), reprise de la garde apres la pause.
#   - LES JOURNAUX REELS depuis le correctif : `attempt_end.pacing` / `abort_paced`, et le
#     `validator-NNN.txt` de l'essai (un validateur lance = un essai compte).
#   - L'HISTORIQUE d'avant le correctif : les essais coupes par la garde depuis le 23/09. Ils
#     sont RECENSES et nommes, jamais additionnes : leur code est celui d'avant, aucun journal
#     ne dit si le crochet tournait (il n'etait pas instrumente), et le superviseur a deja
#     rouvert les deux items bloques le 24/09. Les additionner rendrait la porte rouge a vie.
#
# INCONNU = DEFAUT. Un bras manquant, un bras d'avant qui ne montre pas le defaut (banc
# aveugle), un controle negatif qui ne tue plus : chacun AJOUTE au compte. Sans cette polarite,
# une garde supprimee tout entiere donnerait « 0 essai tue » par inaction.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "pace_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

ST=$(timeout 600 python3 "$AP/lib/pacing_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$ST" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

HI=$(python3 - "$AP" <<'PY' 2>/dev/null
import json, sys
from pathlib import Path
ap = Path(sys.argv[1])
GUARD = ("no-progress", "hard-silence", "post-result", "exit-stall", "tool-budget")
instr = paced = killed = counted = 0
paced_s = 0.0
hist, guard_total = [], 0
for p in sorted(ap.glob("logs/*/attempt-*.jsonl")):
    end = None
    try:
        for raw in p.open(errors="replace"):
            if '"attempt_end"' in raw:
                try:
                    ev = json.loads(raw)
                except ValueError:
                    continue
                if ev.get("event") == "attempt_end":
                    end = ev
    except OSError:
        continue
    if not end:
        continue
    reason = end.get("abort_reason") or ""
    name = "%s/%s" % (p.parent.name, p.stem.replace("attempt-", ""))
    if "pacing" in end:
        instr += 1
        pc = end.get("pacing") or {}
        if int(pc.get("episodes") or 0) > 0:
            paced += 1
            paced_s += float(pc.get("total_s") or 0)
        if end.get("abort_paced") and reason in GUARD:
            killed += 1
            print("real_killed_while_paced_item=%s" % name)
        seq = p.stem.replace("attempt-", "")
        if pc.get("active_at_end") and (p.parent / ("validator-%s.txt" % seq)).exists():
            counted += 1
            print("real_counted_while_paced_item=%s" % name)
    elif reason in ("no-progress", "hard-silence"):
        guard_total += 1
        if (end.get("ended_at") or "") >= "2026-09-23":
            hist.append("%s:%s:%s" % (name, reason, end.get("tool_calls", "?")))
print("real_attempts_instrumented=%d" % instr)
print("real_attempts_paced=%d" % paced)
print("real_paced_total_min=%.1f" % (paced_s / 60))
print("real_killed_while_paced=%d" % killed)
print("real_counted_while_paced=%d" % counted)
print("history_guard_kills_all=%d" % guard_total)
print("history_since_0923=%d" % len(hist))
print("history_since_0923_list=%s" % (",".join(hist) or "-"))
PY
)
h(){ printf '%s\n' "$HI" | sed -n "s/^$1=//p" | tail -1; }
hn(){ local v; v=$(h "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

why=""
faute(){ unknown=$((unknown+1)); why="${why:+$why,}$1"; }
add(){ case "$1" in -1) echo 1 ;; 0) echo 0 ;; *) echo "$1" ;; esac; }
unknown=0

# --- 1+2. SOUS FREIN, L'ESSAI N'EST PAS TUE (controle positif), ET LE TEMPS FREINE EST PUBLIE.
t_killed=$(add "$(n neuf_frein_killed)")
[ "$(n neuf_frein_ran)" = 1 ] || faute bras-positif-absent
[ "$(n neuf_frein_paced_episodes)" -ge 1 ] 2>/dev/null || faute pause-non-detectee
# 60 min de faux crochet : au moins 45 min doivent etre publiees (granularite de lecture).
python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= 45 else 1)" \
  "$(s neuf_frein_paced_total_min)" 2>/dev/null || faute temps-freine-non-publie
case "$(s neuf_frein_status_during_pause)" in
  En_pause_:_frein_d\'usage_depuis_*) ;; *) faute statut-muet-pendant-la-pause ;; esac
[ "$(s neuf_frein_status_after)" = "-" ] || faute statut-perime-apres-la-pause
[ "$(n neuf_frein_journal_says_paused)" = 1 ] || faute journal-muet
# La garde REPREND a la sortie : worker fige apres la pause = tue, sans compter la pause.
[ "$(n neuf_reprise_killed)" = 1 ] || faute garde-ne-reprend-pas
[ "$(n neuf_reprise_abort_paced)" = 0 ] || faute reprise-prise-pour-une-pause

# --- 3. MORT PENDANT LA PAUSE : ni comptee, ni empreintee, pas de validateur.
t_counted=0
t_counted=$((t_counted + $(add "$(n neuf_mort_retries_delta)")))
[ "$(n neuf_mort_fingerprints_delta)" = 0 ] || t_counted=$((t_counted+1))
[ "$(n neuf_mort_validator_calls)" = 0 ] || t_counted=$((t_counted+1))
[ "$(s neuf_mort_outcome)" = paced ] || faute mort-en-pause-mal-classee

# --- CONTROLE NEGATIF : un worker vraiment fige, SANS crochet, est toujours tue.
[ "$(n neuf_fige_killed)" = 1 ] || faute controle-negatif-non-tue
[ "$(n neuf_fige_paced_episodes)" = 0 ] || faute faux-frein-detecte

# --- LE BANC VOIT LE DEFAUT : le code d'avant tue sous frein et compte la mort en pause.
[ "$(s bench_before_commit)" != "-" ] && [ -n "$(s bench_before_commit)" ] || faute pas-de-code-d-avant
[ "$(n vieux_frein_killed)" = 1 ] || faute banc-aveugle-kill
[ "$(n vieux_mort_retries_delta)" = 1 ] || faute banc-aveugle-compte

# --- LES ESSAIS REELS depuis le correctif.
t_real=$(( $(add "$(hn real_killed_while_paced)") + $(add "$(hn real_counted_while_paced)") ))

TOTAL=$((t_killed + t_counted + t_real + unknown))

pub pace_census_ran "$([ -n "$ST" ] && [ -n "$HI" ] && echo 1 || echo 0)"
pub paced_attempts_killed "$TOTAL"
pub paced_attempts_killed_terms "banc_tue$t_killed+banc_compte$t_counted+reels$t_real+inconnu$unknown${why:+:$why}"
pub paced_bench_killed "$t_killed"
pub paced_bench_counted "$t_counted"
pub paced_real_killed_or_counted "$t_real"
pub paced_unknown "$unknown"
# LES GRANDEURS DU LIVRABLE, nommees comme il les nomme.
pub paced_published_min "$(s neuf_frein_paced_total_min)"
pub paced_status_line "$(s neuf_frein_status_during_pause)"
pub paced_real_attempts_instrumented "$(h real_attempts_instrumented)"
pub paced_real_attempts_paced "$(h real_attempts_paced)"
pub paced_real_total_min "$(h real_paced_total_min)"
# L'HISTORIQUE, RECENSE ET NON ADDITIONNE (voir l'en-tete).
pub paced_history_before_fix "$(h history_since_0923)"
pub paced_history_before_fix_list "$(h history_since_0923_list)"
pub paced_history_guard_kills_all "$(h history_guard_kills_all)"
# L'ETAT « FREINE » EN CE MOMENT, tel que `autoport status` le lit.
pub paced_now "$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); from lib import backlog; print(1 if backlog.pacing_line() else 0)" "$AP" 2>/dev/null || echo -1)"

printf '%s\n' "$ST" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/pace_st_\1=/p'
printf '%s\n' "$HI" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/pace_hist_\1=/p'

for f in orchestrator.py lib/pacing.py lib/pacing_selftest.py lib/backlog.py \
         lib/census/harness-copes-with-usage-pacing.sh; do
  k="pace_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
