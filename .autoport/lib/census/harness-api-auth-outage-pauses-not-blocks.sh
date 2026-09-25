#!/usr/bin/env bash
# census/harness-api-auth-outage-pauses-not-blocks.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il n'ecrit aucun champ de `proof.txt` : sa sortie `cle=valeur` rejoint le journal de course.
#
# LA GRANDEUR : `auth_outage_items_blocked` = items BLOQUES (ou essais COMPTES) pour une cause
# d'authentification de l'API. Doit valoir 0.
#
# TROIS SOURCES, jamais une seule :
#   - LE BANC (`lib/auth_outage_selftest.py`) : la VRAIE boucle `main()` sur un depot jetable,
#     trois items, un faux `claude` qui rejoue les evenements releves le 25/09 (401 en plein
#     travail, puis 401 a la porte), une API simulee qui rend 401, 401, 200. Le code neuf ET le
#     code d'avant ancre par MARQUEUR. Controle positif (pause, sondes, reprise, alerte unique,
#     statut), controle negatif (les vrais echecs restent comptes, un 404 reste bloque).
#   - LE BACKLOG VIVANT : items `blocked` dont la raison nomme l'authentification ou dont le
#     dernier essai s'est termine sur un refus d'authentification.
#   - LES ESSAIS REELS depuis le correctif (commit qui porte le marqueur) : un essai termine sur
#     un refus d'authentification ET juge par le validateur est un essai compte a tort.
#     Les 28 d'avant (24-25/09) sont RECENSES et nommes, jamais additionnes : leur code est
#     celui d'avant et le superviseur a rouvert les items le 25/09 a 15:20.
#
# INCONNU = DEFAUT. Un bras manquant, un bras d'avant qui ne montre pas le defaut (banc aveugle),
# un controle negatif qui ne compte plus : chacun AJOUTE au compte. Sans cette polarite, une
# boucle qui ne compterait plus rien donnerait « 0 item bloque » par inaction.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "auth_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

ST=$(timeout 900 python3 "$AP/lib/auth_outage_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$ST" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# Le commit qui a pose le marqueur dans orchestrator.py : la frontiere avant / apres.
FIX_TS=$(git log --format=%ct -S 'PANNE-D-AUTH/' --reverse -- .autoport/orchestrator.py 2>/dev/null | head -1)

LIVE=$(python3 - "$AP" "${FIX_TS:-0}" <<'PY' 2>/dev/null
import json, os, re, sys
from pathlib import Path
ap, fix_ts = Path(sys.argv[1]), int(sys.argv[2] or 0)
sys.path.insert(0, str(ap))
from lib import auth_outage
import yaml
AUTH_RE = re.compile(r"(?i)\b40[13]\b|authentif")
items = (yaml.safe_load((ap / "backlog.yaml").read_text()) or {}).get("items", [])
blocked, nb_blocked = [], 0
for it in items:
    if it.get("status") != "blocked":
        continue
    nb_blocked += 1
    logs = sorted((ap / "logs" / str(it.get("id"))).glob("attempt-*.jsonl"))
    last = auth_outage.refusal_in_file(logs[-1]) if logs else ""
    if AUTH_RE.search(str(it.get("block_reason") or "")) or last:
        blocked.append(str(it.get("id")))
print("live_blocked_total=%d" % nb_blocked)
print("live_blocked_by_auth=%d" % len(blocked))
print("live_blocked_by_auth_list=%s" % (",".join(blocked) or "-"))
before, after_counted, after_seen = [], [], 0
for p in sorted(ap.glob("logs/*/attempt-*.jsonl")):
    if not auth_outage.refusal_in_file(p):
        continue
    seq = p.stem.replace("attempt-", "")
    name = "%s/%s" % (p.parent.name, seq)
    counted = (p.parent / ("validator-%s.txt" % seq)).exists()
    if fix_ts and p.stat().st_mtime > fix_ts:
        after_seen += 1
        if counted:
            after_counted.append(name)
    else:
        before.append(name + (":compte" if counted else ""))
print("real_auth_attempts_after_fix=%d" % after_seen)
print("real_auth_counted_after_fix=%d" % len(after_counted))
print("real_auth_counted_after_fix_list=%s" % (",".join(after_counted) or "-"))
print("history_auth_attempts_before_fix=%d" % len(before))
print("history_auth_counted_before_fix=%d" % sum(1 for b in before if b.endswith(":compte")))
print("history_auth_before_fix_list=%s" % (",".join(before) or "-"))
ev = {}
jp = ap / "logs" / "auth-outage.jsonl"
for raw in (jp.read_text().splitlines() if jp.exists() else []):
    try:
        e = json.loads(raw).get("event", "?")
    except ValueError:
        continue
    ev[e] = ev.get(e, 0) + 1
for k in ("pause", "probe", "alert", "resume", "halt"):
    print("real_journal_%s=%d" % (k, ev.get(k, 0)))
PY
)
h(){ printf '%s\n' "$LIVE" | sed -n "s/^$1=//p" | tail -1; }
hn(){ local v; v=$(h "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

why=""
unknown=0
faute(){ unknown=$((unknown+1)); why="${why:+$why,}$1"; }
add(){ case "$1" in -1) echo 1 ;; 0) echo 0 ;; *) echo "$1" ;; esac; }

# --- 1. LE BANC, CODE NEUF : ni bloque, ni compte pour l'authentification.
[ "$(n neuf_ran)" = 1 ] || faute bras-neuf-absent
t_bench=$(( $(add "$(n neuf_items_blocked_by_auth)") + $(add "$(n neuf_auth_counted)") ))
[ "$(n neuf_auth_attempts)" = 2 ] || faute banc-sans-ses-deux-401

# --- CONTROLE POSITIF : pause, sondes, reprise seule, alerte UNE fois, statut, digest.
[ "$(n neuf_pauses)" = 2 ] || faute pauses-attendues-2
[ "$(n neuf_resumes)" = 2 ] || faute reprises-attendues-2
[ "$(n neuf_probes)" = 4 ] || faute sondes-attendues-4
[ "$(n neuf_alerts)" = 1 ] || faute alerte-pas-unique
[ "$(n neuf_journal_alert_lines)" = 1 ] || faute alerte-journal-pas-unique
[ "$(n neuf_journal_says_paused)" = 1 ] || faute journal-muet-pause
[ "$(n neuf_journal_says_resumed)" = 1 ] || faute journal-muet-reprise
case "$(s neuf_status_first_probe)" in
  En_pause_:_authentification_API_refusee_depuis_*) ;; *) faute statut-muet-pendant-la-pause ;; esac
[ "$(n neuf_status_has_alert_after)" = 1 ] || faute statut-sans-alerte
[ "$(s neuf_digest_before_alert)" = "-" ] || faute digest-reveille-avant-le-seuil
case "$(s neuf_digest_after_alert)" in auth-pause:*) ;; *) faute digest-muet-apres-le-seuil ;; esac
[ "$(s neuf_status_after_run)" = "-" ] || faute statut-perime-apres-reprise
[ "$(n neuf_rc)" = 0 ] || faute boucle-neuve-en-erreur

# --- CONTROLE NEGATIF : les trois VRAIS echecs restent comptes ; un 404 reste bloque.
[ "$(n neuf_genuine_counted)" = 3 ] || faute vrais-echecs-plus-comptes
[ "$(n neuf_validator_calls)" = 3 ] || faute validateur-appels-attendus-3
[ "$(s neuf_404_outcome)" = blocked ] || faute 404-plus-bloque

# --- LE BANC VOIT LE DEFAUT : le code d'avant bloque ou compte sur les 401.
[ -n "$(s bench_before_commit)" ] && [ "$(s bench_before_commit)" != "-" ] || faute pas-de-code-d-avant
[ "$(n vieux_ran)" = 1 ] || faute bras-vieux-absent
[ "$(n vieux_items_blocked_by_auth)" -ge 1 ] 2>/dev/null || faute banc-aveugle-blocage
[ "$(n vieux_auth_counted)" -ge 1 ] 2>/dev/null || faute banc-aveugle-compte

# --- LE BACKLOG VIVANT et LES ESSAIS REELS depuis le correctif.
t_live=$(add "$(hn live_blocked_by_auth)")
t_real=$(add "$(hn real_auth_counted_after_fix)")

TOTAL=$((t_bench + t_live + t_real + unknown))

pub auth_census_ran "$([ -n "$ST" ] && [ -n "$LIVE" ] && echo 1 || echo 0)"
pub auth_outage_items_blocked "$TOTAL"
pub auth_outage_items_blocked_terms "banc$t_bench+backlog$t_live+reels$t_real+inconnu$unknown${why:+:$why}"
pub auth_outage_bench_new_blocked "$(s neuf_items_blocked_by_auth)"
pub auth_outage_bench_new_counted "$(s neuf_auth_counted)"
pub auth_outage_bench_old_blocked "$(s vieux_items_blocked_by_auth)"
pub auth_outage_bench_old_counted "$(s vieux_auth_counted)"
pub auth_outage_live_blocked "$(h live_blocked_by_auth)"
pub auth_outage_live_blocked_list "$(h live_blocked_by_auth_list)"
pub auth_outage_real_counted_after_fix "$(h real_auth_counted_after_fix)"
pub auth_outage_unknown "$unknown"
pub auth_outage_fix_commit_ts "${FIX_TS:--}"
# L'HISTORIQUE, RECENSE ET NON ADDITIONNE (voir l'en-tete).
pub auth_outage_history_before_fix "$(h history_auth_attempts_before_fix)"
pub auth_outage_history_counted_before_fix "$(h history_auth_counted_before_fix)"
pub auth_outage_history_before_fix_list "$(h history_auth_before_fix_list)"
# LA PAUSE EN CE MOMENT, telle que `autoport status` la lit.
pub auth_outage_paused_now "$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); from lib import backlog; print(1 if backlog.auth_pause_line() else 0)" "$AP" 2>/dev/null || echo -1)"

printf '%s\n' "$ST" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/auth_st_\1=/p'
printf '%s\n' "$LIVE" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/auth_live_\1=/p'

for f in orchestrator.py lib/auth_outage.py lib/auth_outage_selftest.py lib/backlog.py \
         lib/census/harness-api-auth-outage-pauses-not-blocks.sh; do
  k="auth_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
