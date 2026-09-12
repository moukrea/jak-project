#!/usr/bin/env bash
# verdict_integrity_selftest.sh — LE BANC DE L'INTEGRITE DES VERDICTS (harness-verdict-integrity).
#
# CE QU'IL MESURE, cinq axes, un par point du livrable. Il ne JUGE rien : la somme et la
# polarite « inconnu = defaut » sont dans lib/census/harness-verdict-integrity.sh.
#
#   A. LE JUGE EPINGLE SES PROPRES SOURCES. Cinq jambes sur le VRAI `validators/generic.sh`,
#      dans un depot jetable : une preuve a jour passe, une preuve dont le recensement a ete
#      EDITE apres la course est refusee, une preuve qui ne porte pas l'empreinte est refusee,
#      une preuve dont une source a ete seulement TOUCHEE est refusee, et une preuve dont le
#      fichier AIDE — atteint par la derivation, jamais nomme a la main — a change est refusee.
#      La jambe `ok` est le controle a laisser : sans elle, un juge qui refuse tout passerait.
#   B. UN `getprop` GLOBAL MUET N'EST PAS UN APPAREIL SANS PROPRIETES. Deux jambes sur le VRAI
#      `lib/device_teardown.sh` contre un faux adb : enumeration qui repond, enumeration muette.
#      Dans la seconde, une propriete ABSENTE de la liste de secours est ratee — c'est le cas
#      qui se lisait « rien n'etait pose ».
#   C. LA FENETRE D'ABLATION N'EST PLUS UN COMPTE DE COMMITS. Un depot synthetique ou
#      l'introduction du marqueur est a 66 commits de HEAD : l'ancienne fenetre de 60 est
#      AVEUGLE, l'ancre de contenu trouve. C'est la meche, allumee pour de vrai.
#   D. ET ELLE NE CHANGE LE VERDICT DE PERSONNE : sur le depot REEL, les cinq couples
#      (chemin, marqueur) du harnais rendent le MEME commit qu'avec l'ancienne fenetre.
#   E. PLUS AUCUNE FENETRE PLAFONNEE chez les lecteurs d'ablation. Les sites `-n 1` sont
#      publies eux aussi : un `-n 1` rend le commit le plus recent, il ne balaye rien.
#
#   F. LE BAC A SABLE DE L'EPINGLAGE, relaye tel quel : c'est lui qui lance le VRAI
#      `proof_run.sh` en mode appareil et qui rend donc le teardown de FIN de course observable.
#
# Sortie : des `cle=valeur` sur stdout, les explications sur stderr.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "vi_selftest_ran=0"; exit 1; }
AP="$ROOT/.autoport"
SB=$(mktemp -d -t verdictint.XXXXXX) || { echo "vi_selftest_ran=0"; exit 1; }
trap 'rm -rf "$SB"' EXIT
note(){ printf '[vi-selftest] %s\n' "$*" >&2; }
kv(){ printf '%s=%s\n' "$1" "$2"; }

# ================================================= A. LE JUGE EPINGLE SES PROPRES SOURCES =====
SBID=sandbox-verdict
VAL="$SB/val"

monte_validateur(){  # monte_validateur <dossier>
  local d=$1
  mkdir -p "$d/.autoport/lib/census" "$d/.autoport/validators" "$d/.autoport/reports/$SBID" \
           "$d/build/game" "$d/game" "$d/common" "$d/android" "$d/goal_src" || return 1
  git -C "$d" init -q >/dev/null 2>&1 || return 1        # git-sandbox-ok
  git -C "$d" config user.email vi@sandbox >/dev/null 2>&1  # git-sandbox-ok
  git -C "$d" config user.name vi >/dev/null 2>&1           # git-sandbox-ok
  cp "$AP/validators/generic.sh" "$d/.autoport/validators/" || return 1
  cp "$AP/lib/verdict_sources.sh" "$d/.autoport/lib/" || return 1
  # LE FICHIER AIDE : il n'est nomme nulle part a la main. Le recensement le CITE, et c'est la
  # derivation de `verdict_sources.sh` qui doit l'attraper.
  printf '#!/usr/bin/env bash\necho aide_du_bac_a_sable\n' > "$d/.autoport/lib/sb_helper.sh"
  cat > "$d/.autoport/lib/census/$SBID.sh" <<CENSUS
#!/usr/bin/env bash
# recensement jetable : il appelle lib/sb_helper.sh, donc ce fichier fait partie du verdict.
bash "\$(dirname "\$0")/../sb_helper.sh" >/dev/null
echo "sb_gate=1"
CENSUS
  cat > "$d/.autoport/backlog.yaml" <<YAML
version: 1
items:
  - id: $SBID
    status: in-progress
    device: false
    owner_test: false
    frames_min: 1
    feature: bac a sable de l'integrite des verdicts
    gate:
      key: sb_gate
      op: "=="
      value: 0
YAML
  printf 'faux gk pour le bac a sable\n' > "$d/build/game/gk"
  chmod +x "$d/.autoport/lib/"*.sh "$d/.autoport/lib/census/"*.sh "$d/build/game/gk"
}

ecrit_preuve(){  # ecrit_preuve <dossier> <avec-empreinte:0|1>
  local d=$1 avec=$2 pf="$1/.autoport/reports/$SBID/proof.txt"
  {
    echo "source=x86"
    echo "binary=build/game/gk"
    echo "sha=$(sha256sum "$d/build/game/gk" | cut -c1-16)"
    echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "duration_s=1"
    echo "crash=0"
    echo "frames=10"
    # L'EMPREINTE SORT DU NOMMEUR, elle n'est pas tapee ici : une valeur ecrite a la main ne
    # prouverait que la frappe. C'est le meme script que celui que le juge rappellera.
    [ "$avec" = 1 ] && ( cd "$d" && bash .autoport/lib/verdict_sources.sh "$SBID" kv )
    echo "FEATURE $SBID armed=1 hits=7"
    echo "sb_gate=0"
  } > "$pf"
}

juge(){  # juge <dossier> -> "<rc>|<stderr sur une ligne>"
  local d=$1 out rc
  out=$( cd "$d" && AUTOPORT_PHASE_ID="$SBID" bash .autoport/validators/generic.sh 2>&1 )
  rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ';')"
}

jambe(){  # jambe <nom> <geste-apres-la-preuve>
  local nom=$1 geste=$2 r rc msg d
  d="$VAL-$nom"
  monte_validateur "$d" || { kv "va_${nom}_monte" 0; return 1; }
  kv "va_${nom}_monte" 1
  ecrit_preuve "$d" "$([ "$nom" = absent ] && echo 0 || echo 1)"
  case "$geste" in
    rien) : ;;
    edite)  printf 'echo "sb_gate=1"  # edite APRES la course\n' >> "$d/.autoport/lib/census/$SBID.sh" ;;
    aide)   printf 'echo "aide changee APRES la course"\n' >> "$d/.autoport/lib/sb_helper.sh" ;;
    # DATE EXPLICITE, jamais « maintenant » : la preuve vient d'etre ecrite a la microseconde
    # pres et la granularite des horodatages n'est pas garantie. Un `touch` nu rendait cette
    # jambe INTERMITTENTE — elle passait une fois sur deux, ce qui est pire qu'un rouge franc.
    touche) touch -d "@$(( $(date +%s) + 5 ))" "$d/.autoport/lib/census/$SBID.sh" ;;
  esac
  r=$(juge "$d"); rc=${r%%|*}; msg=${r#*|}
  kv "va_${nom}_rc" "$rc"
  kv "va_${nom}_change"  "$(printf '%s' "$msg" | grep -c 'a change depuis la course')"
  kv "va_${nom}_absente" "$(printf '%s' "$msg" | grep -c "ne porte pas 'verdict_sources_sha='")"
  kv "va_${nom}_vieille" "$(printf '%s' "$msg" | grep -c 'plus vieille que son propre juge')"
  # Le nombre de fichiers que le juge a epingles pour cette jambe : un zero dirait que la
  # derivation n'a rien trouve, et toutes les jambes passeraient pour une raison sans rapport.
  kv "va_${nom}_epingles" "$( cd "$d" && bash .autoport/lib/verdict_sources.sh "$SBID" count )"
  note "jambe $nom : rc=$rc $msg"
}

jambe ok     rien
jambe edite  edite
jambe aide   aide
jambe touche touche
jambe absent rien

# ============================================ B. `getprop` MUET vs APPAREIL SANS PROPRIETES ====
monte_faux_adb(){  # monte_faux_adb <dossier> <muet:0|1>
  local d=$1
  mkdir -p "$d" || return 1
  printf 'debug.opengoal.cpad_inject=1\ndebug.opengoal.zzz_inconnue=1\nro.product.model=BANC\n' > "$d/props"
  [ "$2" = 1 ] && : > "$d/muet"
  cat > "$d/adb" <<'ADB_EOF'
#!/usr/bin/env bash
D=$(cd "$(dirname "$0")" && pwd); P="$D/props"
esc(){ printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }
[ "${1:-}" = -s ] || exit 1
shift 2
case "${1:-}" in
  get-state) echo device ;;
  shell|exec-out)
    shift
    [ "${1:-}" = run-as ] && shift 2
    [ "${1:-}" = sh ] && shift 2
    # shellcheck disable=SC2046
    set -- $(printf '%s ' "$@" | sed "s/''/ /g; s/'//g")
    case "${1:-}" in
      getprop)
        if [ -z "${2:-}" ]; then
          # MUET : l'enumeration globale ne rend RIEN, alors que les proprietes sont bien la.
          [ -f "$D/muet" ] && exit 0
          while IFS= read -r l; do [ -n "$l" ] && printf '[%s]: [%s]\n' "${l%%=*}" "${l#*=}"; done < "$P"
        else
          sed -n "s/^$(esc "$2")=//p" "$P" | tail -1
        fi ;;
      setprop)
        t=$(mktemp); grep -v "^$(esc "$2")=" "$P" > "$t" 2>/dev/null
        [ -n "${3:-}" ] && printf '%s=%s\n' "$2" "$3" >> "$t"
        mv -f "$t" "$P" ;;
      *) : ;;
    esac ;;
  *) : ;;
esac
exit 0
ADB_EOF
  chmod +x "$d/adb"
}

jambe_teardown(){  # jambe_teardown <nom> <muet:0|1>
  local nom=$1 d rep
  d="$SB/td-$nom"; rep="$SB/td-$nom.rapport"
  monte_faux_adb "$d" "$2" || { kv "td_${nom}_monte" 0; return 1; }
  kv "td_${nom}_monte" 1
  AUTOPORT_TEARDOWN_REPORT="$rep" ADB="$d/adb" AUTOPORT_LOGCAT_PIDDIR="$d/pids" \
    bash "$AP/lib/device_teardown.sh" BANCVERDICT01 >/dev/null 2>&1 || true
  local k
  for k in teardown_ran teardown_props_found teardown_props_list teardown_props_cleared \
           teardown_getprop_ok teardown_getprop_total teardown_props_source; do
    kv "td_${nom}_${k#teardown_}" "$(sed -n "s/^$k=//p" "$rep" 2>/dev/null | tail -1)"
  done
  # LA PROPRIETE QUE LA LISTE DE SECOURS NE CONNAIT PAS. C'est elle qui disparaissait en
  # silence : `found` faible se lisait « rien n'etait pose ».
  if grep -q '^teardown_props_list=.*zzz_inconnue' "$rep" 2>/dev/null; then
    kv "td_${nom}_inconnue_vue" 1
  else
    kv "td_${nom}_inconnue_vue" 0
  fi
}

jambe_teardown plein 0
jambe_teardown muet  1

# ============================== C. LA MECHE, ALLUMEE POUR DE VRAI DANS UN DEPOT SYNTHETIQUE ====
# L'introduction du marqueur est a 66 commits de HEAD sur le chemin. L'ancienne fenetre en
# regardait 60 : elle ne pouvait PAS voir l'etat d'avant. C'est le faux rouge programme.
HIST="$SB/hist"; MARQ="MARQUEUR-DU-BANC"
mkdir -p "$HIST" && git -C "$HIST" init -q >/dev/null 2>&1        # git-sandbox-ok
git -C "$HIST" config user.email vi@sandbox >/dev/null 2>&1       # git-sandbox-ok
git -C "$HIST" config user.name vi >/dev/null 2>&1                # git-sandbox-ok
hcommit(){ git -C "$HIST" add f.txt >/dev/null 2>&1 && git -C "$HIST" commit -qm "$1" >/dev/null 2>&1; }
printf 'etat d avant, sans marqueur\n' > "$HIST/f.txt"; hcommit avant
AVANT_ATTENDU=$(git -C "$HIST" rev-parse HEAD)
printf '%s\n' "$MARQ" >> "$HIST/f.txt"; hcommit introduction
for i in $(seq 1 65); do
  printf 'bruit %s\n' "$i" >> "$HIST/f.txt"; hcommit "bruit $i"
done
kv win_hist_commits "$(git -C "$HIST" log --format=%H -- f.txt | wc -l)"
# LE BRAS D'AVANT, recopie tel qu'il vivait dans les trois lecteurs (60 commits, balayage).
WIN_OLD=""
# La replique ne differe du bras neuf que par LA FENETRE : elle lit le blob comme lui, par une
# variable et non par un tube (`git show | grep -q` sous pipefail rend un faux negatif sur les
# gros fichiers). Sinon on mesurerait ce defaut-la, pas le plafond de commits.
for c in $(git -C "$HIST" log --format=%H -n 60 -- f.txt 2>/dev/null); do  # fenetre-ablation-replique
  blob=$(git -C "$HIST" show "$c:f.txt" 2>/dev/null)
  if ! grep -qF -- "$MARQ" <<<"$blob"; then WIN_OLD="$c"; break; fi
done
WIN_NEW_KV=$(bash "$AP/lib/ablation_anchor.sh" "$HIST" f.txt "$MARQ" kv 2>/dev/null) || true
WIN_NEW=$(printf '%s\n' "$WIN_NEW_KV" | sed -n 's/^anchor_commit=//p' | tail -1)
kv win_old_found "$([ -n "$WIN_OLD" ] && echo 1 || echo 0)"
kv win_new_found "$([ -n "$WIN_NEW" ] && [ "$WIN_NEW" != "-" ] && echo 1 || echo 0)"
kv win_new_juste "$([ "$WIN_NEW" = "$AVANT_ATTENDU" ] && echo 1 || echo 0)"
kv win_new_method "$(printf '%s\n' "$WIN_NEW_KV" | sed -n 's/^anchor_method=//p' | tail -1)"
kv win_new_depth  "$(printf '%s\n' "$WIN_NEW_KV" | sed -n 's/^anchor_depth=//p' | tail -1)"
kv win_legacy_window "$(printf '%s\n' "$WIN_NEW_KV" | sed -n 's/^anchor_legacy_window=//p' | tail -1)"

# ================== D. SUR LE DEPOT REEL, L'ANCRE REND LE MEME COMMIT QUE L'ANCIENNE FENETRE ===
# « Ne change le verdict d'aucun item deja ferme » se MESURE : les cinq couples du harnais.
COUPLES="
.autoport/lib/proof_run.sh|proof_props_effective
.autoport/lib/device_teardown.sh|AUTOPORT_TEARDOWN_REPORT
.autoport/lib/backlog.py|def parked_for_owner
.autoport/orchestrator.py|free_machine_proved
.autoport/tests/harness/test_proof_busy.py|liste-injectee-2026-09-12
"
par_total=0; par_same=0; par_new_ok=0; par_detail=""; par_diff=""
while IFS= read -r couple; do
  [ -n "$couple" ] || continue
  cp_path=${couple%%|*}; cp_marq=${couple#*|}
  old=""
  for c in $(git -C "$ROOT" log --format=%H -n 60 -- "$cp_path" 2>/dev/null); do  # fenetre-ablation-replique
    blob=$(git -C "$ROOT" show "$c:$cp_path" 2>/dev/null)
    if ! grep -qF -- "$cp_marq" <<<"$blob"; then old="$c"; break; fi
  done
  nk=$(bash "$AP/lib/ablation_anchor.sh" "$ROOT" "$cp_path" "$cp_marq" kv 2>/dev/null) || true
  new=$(printf '%s\n' "$nk" | sed -n 's/^anchor_commit=//p' | tail -1)
  dep=$(printf '%s\n' "$nk" | sed -n 's/^anchor_depth=//p' | tail -1)
  par_total=$((par_total+1))
  [ -n "$new" ] && [ "$new" != "-" ] && par_new_ok=$((par_new_ok+1))
  if [ "$old" = "$new" ]; then par_same=$((par_same+1))
  else par_diff="${par_diff:+$par_diff,}$(basename "$cp_path"):${old:0:8}/${new:0:8}"; fi
  par_detail="${par_detail:+$par_detail,}$(basename "$cp_path"):${dep:--}"
done <<COUPLES_EOF
$COUPLES
COUPLES_EOF
kv par_total "$par_total"
kv par_same "$par_same"
kv par_new_ok "$par_new_ok"
kv par_depths "${par_detail:--}"
kv par_diff_list "${par_diff:--}"

# ============================ E. PLUS AUCUNE FENETRE PLAFONNEE CHEZ LES LECTEURS D'ABLATION ====
# La signature d'un balayage d'historique, c'est `git log --format=%H` avec un `-n`. Un `-n 1`
# n'est pas une fenetre : il rend LE commit le plus recent. Les deux comptes sont publies —
# on ne cache pas ce qu'on ecarte.
# LES DEUX BRAS D'ABLATION DE CE BANC SONT, EUX, DES REPLIQUES VOLONTAIRES de la fenetre
# supprimee : sans elles il n'y aurait rien a comparer. Elles portent un marqueur en clair et se
# comptent A PART. Les trois comptes sont publies : rien n'est ecarte en silence.
capped=0; capped_list=""; n1=0; repl=0; repl_list=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  while IFS= read -r ligne; do
    case "$ligne" in *--format=%H*) ;; *) continue ;; esac
    n=$(printf '%s' "$ligne" | sed -n "s/.*-n[', ]\{1,\}\([0-9]\{1,\}\).*/\1/p" | head -1)
    [ -n "$n" ] || continue
    if [ "$n" -le 1 ]; then n1=$((n1+1)); continue; fi
    case "$ligne" in
      *fenetre-ablation-replique*)
        repl=$((repl+1)); repl_list="${repl_list:+$repl_list,}$(basename "$f"):$n" ;;
      *)
        capped=$((capped+1)); capped_list="${capped_list:+$capped_list,}$(basename "$f"):$n" ;;
    esac
  done < "$f"
done <<AUDIT_EOF
$(ls "$AP"/lib/*.sh "$AP"/lib/*.py "$AP"/lib/census/*.sh 2>/dev/null)
AUDIT_EOF
kv audit_capped "$capped"
kv audit_capped_list "${capped_list:--}"
kv audit_ablation_replicas "$repl"
kv audit_ablation_replicas_list "${repl_list:--}"
kv audit_n1_sites "$n1"

# ==================================== F. LE BAC A SABLE DE L'EPINGLAGE, RELAYE TEL QUEL ========
# C'est lui, et lui seul, qui lance le VRAI `proof_run.sh` en mode appareil : le teardown de FIN
# de course n'est observable nulle part ailleurs sans telephone.
PIN=$(bash "$AP/lib/pin_props_selftest.sh" 2>/dev/null) || PIN=""
printf '%s\n' "$PIN" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/vi_pin_\1=/p'
kv vi_pin_lu "$([ -n "$PIN" ] && echo 1 || echo 0)"

kv vi_selftest_ran 1
