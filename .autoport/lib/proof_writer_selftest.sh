#!/usr/bin/env bash
# lib/proof_writer_selftest.sh — LE BANC DE L'ECRIVAIN UNIQUE.
#
# POURQUOI (harness-proof-file-has-no-writer-lock, 2026-09-12). Deux signalements du 12/09,
# dont un CHIFFRE et reproduit dans l'heure :
#   1. aucun ecrivain unique, aucun verrou sur `reports/<id>/proof.txt`. Un essai TUE laissait
#      son `proof_run.sh` VIVANT ; il finissait sa course et ecrivait sa preuve PAR-DESSUS
#      celle de l'essai suivant (`started_at=14:16:05Z`, `crash=1`, alors que la course de
#      l'essai 3 etait en vol depuis 16:23:25). Seul l'ordre d'arrivee decidait du verdict.
#   2. rien ne disait qu'un commit exterieur etait tombe pendant une course : le superviseur a
#      commite a 16:12:59, l'empreinte des sources de verdict a bouge entre la mesure et son
#      jugement, et l'essai a ete refuse pour un defaut qui n'etait pas le sien.
#
# CE QUE CE BANC NE FAIT PAS : il ne RECOPIE aucune des regles qu'il juge. Il LEVE les blocs
# marques dans `lib/proof_run.sh` et `validators/generic.sh` et les rejoue tels quels dans un
# bac a sable. Une recopie mesurerait la recopie. Chaque geste a DEUX bras — l'etat livre et
# l'etat d'AVANT, ancre par MARQUEUR sur `lib/ablation_anchor.sh`, jamais lu a `HEAD:` (il
# s'accuserait lui-meme des le commit qui corrige) — et un CONTROLE SAIN, sans quoi « ca
# refuse » serait vert pour une porte qui refuse tout.
#
# Sortie : des `cle=valeur`, une par ligne, aucune espace dans une valeur.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "selftest_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || { echo "selftest_ran=0"; exit 1; }

BAC=$(mktemp -d "${TMPDIR:-/tmp}/proof-writer-banc.XXXXXX") || { echo "selftest_ran=0"; exit 1; }
# LE BAC A SABLE S'EN VA QUOI QU'IL ARRIVE, et les ecrivains qu'il a semes avec lui : un banc
# qui laisse des processus derriere lui devient la panne suivante.
SEMES=""
nettoyer(){
  local p
  for p in $SEMES; do
    kill -KILL "$p" 2>/dev/null || true
  done
  rm -rf "$BAC" 2>/dev/null || true
}
trap nettoyer EXIT

pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ================================================================== LEVER UN BLOC, TEL QUEL ==
# Entre `<marqueur>/debut` et `<marqueur>/fin`, bornes exclues. Zero ligne rendue est un fait
# publie, pas une erreur avalee : c'est exactement ce que doit rendre le bras d'AVANT.
lever(){  # lever <fichier-ou-"-"> <marqueur>
  [ "$1" = "-" ] && return 0
  awk -v a="$2/debut" -v b="$2/fin" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1" 2>/dev/null
}
lever_blob(){  # lever_blob <texte> <marqueur>
  printf '%s\n' "$1" | awk -v a="$2/debut" -v b="$2/fin" 'index($0,a){f=1;next} index($0,b){f=0} f'
}
octets(){ printf '%s' "$1" | wc -c | tr -d ' '; }

# L'ETAT D'AVANT, ANCRE SUR LE MARQUEUR — jamais `HEAD:`, jamais un compte de commits.
ancre(){  # ancre <chemin-relatif> <marqueur> -> "commit methode"
  local s
  s=$(timeout 300 bash "$AP/lib/ablation_anchor.sh" "$ROOT" "$1" "$2" kv 2>/dev/null)
  printf '%s %s\n' \
    "$(printf '%s\n' "$s" | sed -n 's/^anchor_commit=//p' | tail -1)" \
    "$(printf '%s\n' "$s" | sed -n 's/^anchor_method=//p' | tail -1)"
}
blob_a(){  # blob_a <commit> <chemin> -> le contenu, vide si introuvable
  [ -n "$1" ] && [ "$1" != "-" ] || return 0
  git -C "$ROOT" show "$1:$2" 2>/dev/null
}

BLOC_VERROU=$(lever "$AP/lib/proof_run.sh" VERROU-ECRIVAIN)
BLOC_IDENT=$(lever "$AP/validators/generic.sh" IDENTITE-DE-LA-COURSE)
BLOC_ENVOL=$(lever "$AP/validators/generic.sh" COURSE-EN-VOL)
pub bloc_verrou_octets   "$(octets "$BLOC_VERROU")"
pub bloc_verrou_lignes   "$(printf '%s\n' "$BLOC_VERROU" | grep -c .)"
pub bloc_identite_octets "$(octets "$BLOC_IDENT")"
pub bloc_envol_octets    "$(octets "$BLOC_ENVOL")"

read -r AV_PR_COMMIT AV_PR_METHODE <<<"$(ancre .autoport/lib/proof_run.sh VERROU-ECRIVAIN)"
read -r AV_GV_COMMIT AV_GV_METHODE <<<"$(ancre .autoport/validators/generic.sh IDENTITE-DE-LA-COURSE)"
AV_PR_BLOB=$(blob_a "$AV_PR_COMMIT" .autoport/lib/proof_run.sh)
AV_GV_BLOB=$(blob_a "$AV_GV_COMMIT" .autoport/validators/generic.sh)
pub avant_proof_run_ref     "${AV_PR_COMMIT:0:12}"
pub avant_proof_run_methode "$AV_PR_METHODE"
pub avant_proof_run_octets  "$(octets "$AV_PR_BLOB")"
pub avant_generic_ref       "${AV_GV_COMMIT:0:12}"
pub avant_generic_methode   "$AV_GV_METHODE"
pub avant_generic_octets    "$(octets "$AV_GV_BLOB")"
# CE QUE L'ETAT D'AVANT NE PORTAIT PAS, COMPTE SUR SON PROPRE BLOB. Un « ca n'existait pas »
# affirme dans une prose ne vaut rien ; celui-ci est un nombre, lu dans le fichier d'alors.
pub avant_verrou_octets   "$(octets "$(lever_blob "$AV_PR_BLOB" VERROU-ECRIVAIN)")"
pub avant_flock_sites     "$(printf '%s\n' "$AV_PR_BLOB" | grep -c 'flock')"
pub avant_identite_octets "$(octets "$(lever_blob "$AV_GV_BLOB" IDENTITE-DE-LA-COURSE)")"
pub avant_identite_sites  "$(printf '%s\n' "$AV_GV_BLOB" | grep -c 'proof_attempt_id')"

# ============================================================ SECTION A — LE VERROU, EN VRAI ==
# Deux ecrivains sur LE MEME fichier de preuve. A est lent (il tient la place), B arrive apres.
# Le bras d'AVANT est le meme geste sans le bloc leve : c'est litteralement ce que faisait
# `proof_run.sh`, et il ECRASE. Le bras d'APRES rejoue le bloc du disque.
mkdir -p "$BAC/lib"
printf '%s\n' "$BLOC_VERROU" > "$BAC/lib/bloc-verrou.sh"

cat > "$BAC/ecrivain.sh" <<'ECRIVAIN'
#!/usr/bin/env bash
# L'ECRIVAIN DU BAC A SABLE. Il fait le geste de `proof_run.sh` et rien d'autre : il prend (ou
# ne prend pas) le verrou, il tient la place, il ecrit sa preuve, il libere.
#   $1 dossier   $2 nom de l'ecrivain   $3 secondes tenues   $4 borne d'attente   $5 avec-verrou
set -uo pipefail
D=$1; NOM=$2; TENU=$3; BORNE=$4; AVEC=$5
AP="$D/.."
ID=bac-a-sable; SUF=""
PW_RUNID="course-$NOM"; PW_ATTEMPT="essai-$NOM"
log(){ printf '[ecrivain %s] %s\n' "$NOM" "$*" >&2; }
extra(){ :; }
PW_LOCKF="$D/verrou.lock"
if [ "$AVEC" = 1 ]; then
  . "$D/lib/bloc-verrou.sh"
  pw_orphelin "$PW_LOCKF"
  printf 'orph_trouves=%s\norph_arretes=%s\norph_restes=%s\n' \
    "$PW_ORPH_TROUVES" "$PW_ORPH_ARRETES" "$PW_ORPH_RESTES" > "$D/orph-$NOM.txt"
  if ! pw_prendre "$PW_LOCKF" "$BORNE"; then
    printf 'concurrent=%s\nattendu=%s\n' "$PW_CONCURRENT" "$PW_ATTENDU" > "$D/pris-$NOM.txt"
    log "REFUS : verrou tenu par pid=$(pw_lit "$PW_LOCKF" pid) apres ${PW_ATTENDU}s"
    exit 7
  fi
  pw_marquer "$PW_LOCKF"
  trap 'rm -f "$PW_LOCKF"' EXIT
  printf 'concurrent=%s\nattendu=%s\n' "$PW_CONCURRENT" "$PW_ATTENDU" > "$D/pris-$NOM.txt"
fi
sleep "$TENU"
printf 'ecrivain=%s\npid=%s\n' "$NOM" "$$" > "$D/.preuve.tmp.$$"
mv -f "$D/.preuve.tmp.$$" "$D/preuve.txt"
echo "$NOM" >> "$D/ordre.txt"
exit 0
ECRIVAIN

# semer <dossier> <nom> <tenu> <borne> <avec> <orphelin 0|1> -> le pid de l'ecrivain
semer(){
  local d=$1 nom=$2 tenu=$3 borne=$4 avec=$5 orph=$6 pidf="$1/pid-$2.txt"
  rm -f "$pidf"
  if [ "$orph" = 1 ]; then
    # SON LANCEUR MEURT : c'est la definition de l'orphelin, et c'est l'etat exact du 12/09 —
    # un `proof_run.sh` vivant dont l'essai a ete tue. Il tient DEUX SECONDES avant de mourir,
    # et ce n'est pas un confort : `$PPID` est lu par bash au DEMARRAGE, donc apres l'exec. Un
    # lanceur qui sort avant que l'exec finisse fait lire au fils le pid du SUBREAPER (mesure
    # du 12/09 : `launcher=1158`, bien vivant) — l'orphelin passerait pour une course
    # surveillee, et le banc rendrait un vert qui ne mesure que sa propre mise en place.
    setsid bash -c "bash '$BAC/ecrivain.sh' '$d' '$nom' '$tenu' '$borne' '$avec' >'$d/log-$nom.txt' 2>&1 & echo \$! > '$pidf'; sleep 2" >/dev/null 2>&1 &
  else
    # SON LANCEUR RESTE : ce n'est pas un orphelin, et rien ne doit l'arreter.
    setsid bash -c "bash '$BAC/ecrivain.sh' '$d' '$nom' '$tenu' '$borne' '$avec' >'$d/log-$nom.txt' 2>&1 & echo \$! > '$pidf'; wait" >/dev/null 2>&1 &
  fi
  for _ in $(seq 1 40); do [ -s "$pidf" ] && break; sleep 0.1; done
  local p; p=$(cat "$pidf" 2>/dev/null)
  SEMES="$SEMES $p"
  printf '%s' "$p"
}
attendre_mort(){ local p=$1 n=0; while kill -0 "$p" 2>/dev/null && [ "$n" -lt 60 ]; do sleep 0.5; n=$((n+1)); done; }
lis(){ sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -1; }
# `grep -c` SUR UN FICHIER SANS OCCURRENCE REND 0 **ET** SORT EN 1 : un `|| echo 0` derriere
# publie alors « 0 0 », que la publication colle en « 0_0 » — une valeur qui n'est plus un
# nombre, donc un terme du verdict qui ne se compare plus a rien.
compte(){ local n; n=$(grep -c "$1" "$2" 2>/dev/null); case "$n" in ''|*[!0-9]*) n=0 ;; esac; printf '%s' "$n"; }

# --- bras AVANT : aucun verrou. A (lent) ECRASE B (arrive apres, ecrit tout de suite).
A1="$BAC/avant"; mkdir -p "$A1/lib"; cp "$BAC/lib/bloc-verrou.sh" "$A1/lib/"
PA=$(semer "$A1" A 6 5 0 0); sleep 2
PB=$(semer "$A1" B 0 5 0 0)
attendre_mort "$PA"; attendre_mort "$PB"
pub vr_avant_final      "$(lis "$A1/preuve.txt" ecrivain)"
pub vr_avant_ordre      "$(paste -sd, - < "$A1/ordre.txt" 2>/dev/null)"
pub vr_avant_ecrasement "$([ "$(lis "$A1/preuve.txt" ecrivain)" = A ] && echo 1 || echo 0)"

# --- bras APRES / ATTENTE : B attend que A finisse, puis ecrit. B gagne, sans course.
A2="$BAC/attente"; mkdir -p "$A2/lib"; cp "$BAC/lib/bloc-verrou.sh" "$A2/lib/"
PA=$(semer "$A2" A 6 60 1 0); sleep 2
PB=$(semer "$A2" B 0 60 1 0)
attendre_mort "$PA"; attendre_mort "$PB"
pub vr_attente_final      "$(lis "$A2/preuve.txt" ecrivain)"
pub vr_attente_ordre      "$(paste -sd, - < "$A2/ordre.txt" 2>/dev/null)"
pub vr_attente_concurrent "$(lis "$A2/pris-B.txt" concurrent)"
pub vr_attente_s          "$(lis "$A2/pris-B.txt" attendu)"

# --- bras APRES / REFUS : la borne de B est trop courte. Il REFUSE et n'ecrit rien.
A3="$BAC/refus"; mkdir -p "$A3/lib"; cp "$BAC/lib/bloc-verrou.sh" "$A3/lib/"
PA=$(semer "$A3" A 8 60 1 0); sleep 2
bash "$BAC/ecrivain.sh" "$A3" B 0 1 1 >"$A3/log-B.txt" 2>&1; RCB=$?
pub vr_refus_rc         "$RCB"
pub vr_refus_b_ecrit    "$(compte '^B$' "$A3/ordre.txt")"
pub vr_refus_concurrent "$(lis "$A3/pris-B.txt" concurrent)"
attendre_mort "$PA"
pub vr_refus_final      "$(lis "$A3/preuve.txt" ecrivain)"

# --- bras APRES / ORPHELIN : A est vivant, son LANCEUR est mort. B le trouve, l'arrete, ecrit.
A4="$BAC/orphelin"; mkdir -p "$A4/lib"; cp "$BAC/lib/bloc-verrou.sh" "$A4/lib/"
PA=$(semer "$A4" A 25 60 1 1); sleep 3
bash "$BAC/ecrivain.sh" "$A4" B 0 20 1 >"$A4/log-B.txt" 2>&1; RCB=$?
pub vr_orph_b_rc      "$RCB"
pub vr_orph_trouves   "$(lis "$A4/orph-B.txt" orph_trouves)"
pub vr_orph_arretes   "$(lis "$A4/orph-B.txt" orph_arretes)"
pub vr_orph_restes    "$(lis "$A4/orph-B.txt" orph_restes)"
pub vr_orph_a_vivant  "$(kill -0 "$PA" 2>/dev/null && echo 1 || echo 0)"
pub vr_orph_final     "$(lis "$A4/preuve.txt" ecrivain)"
pub vr_orph_a_ecrit   "$(compte '^A$' "$A4/ordre.txt")"

# --- CONTROLE SAIN : A est vivant et son LANCEUR repond. Rien ne doit l'arreter.
# Sans cette population, « l'orphelin est arrete » serait vert pour un balayage qui tue tout.
A5="$BAC/sain"; mkdir -p "$A5/lib"; cp "$BAC/lib/bloc-verrou.sh" "$A5/lib/"
PA=$(semer "$A5" A 10 60 1 0); sleep 3
bash "$BAC/ecrivain.sh" "$A5" B 0 1 1 >"$A5/log-B.txt" 2>&1; RCB=$?
pub vr_sain_b_rc     "$RCB"
pub vr_sain_trouves  "$(lis "$A5/orph-B.txt" orph_trouves)"
pub vr_sain_a_vivant "$(kill -0 "$PA" 2>/dev/null && echo 1 || echo 0)"
attendre_mort "$PA"
pub vr_sain_final    "$(lis "$A5/preuve.txt" ecrivain)"
pub vr_sain_a_ecrit  "$(compte '^A$' "$A5/ordre.txt")"

# ========================================================= SECTION B — L'IDENTITE, DEUX BRAS ==
# Une preuve SEMEE, celle d'un essai precedent. Le bras d'APRES doit la REFUSER ; le bras
# d'AVANT — le bloc du fichier d'alors, vide — doit l'ACCEPTER, sinon l'ablation est sans objet.
mkdir -p "$BAC/ident"
printf 'started_at=2026-09-12T14:16:05Z\nproof_run_id=course-perimee\nproof_run_pid=403112\nproof_attempt_id=essai-A\n' > "$BAC/ident/perime.txt"
printf 'started_at=2026-09-12T16:23:25Z\nproof_run_id=course-courante\nproof_run_pid=999\nproof_attempt_id=essai-B\n' > "$BAC/ident/courant.txt"
printf 'started_at=2026-09-12T16:23:25Z\nproof_run_id=course-muette\nproof_run_pid=999\n' > "$BAC/ident/sans-cle.txt"

juger_identite(){  # juger_identite <bloc> <fichier-preuve> <essai-courant> -> accepte|refuse
  local bloc=$1 pf=$2 essai=$3 rc
  { printf 'set -uo pipefail\nN=0\nbad(){ N=$((N+1)); }\n'
    printf 'PF=%s\nkv(){ sed -n "s/^$1=//p" "$PF" 2>/dev/null | tail -1; }\n' "$pf"
    printf '%s\n' "$bloc"
    printf 'exit $(( N > 0 ))\n'
  } > "$BAC/ident/juge.sh"
  AUTOPORT_ATTEMPT_ID="$essai" bash "$BAC/ident/juge.sh" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && echo accepte || echo refuse
}
AV_IDENT=$(lever_blob "$AV_GV_BLOB" IDENTITE-DE-LA-COURSE)
pub id_avant_perime      "$(juger_identite "$AV_IDENT"   "$BAC/ident/perime.txt"   essai-B)"
pub id_avant_courant     "$(juger_identite "$AV_IDENT"   "$BAC/ident/courant.txt"  essai-B)"
pub id_apres_perime      "$(juger_identite "$BLOC_IDENT" "$BAC/ident/perime.txt"   essai-B)"
pub id_apres_courant     "$(juger_identite "$BLOC_IDENT" "$BAC/ident/courant.txt"  essai-B)"
pub id_apres_sans_cle    "$(juger_identite "$BLOC_IDENT" "$BAC/ident/sans-cle.txt" essai-B)"
# AUCUN ESSAI COURANT = RIEN A CONTREDIRE : une course lancee a la main ne doit pas rougir.
pub id_apres_sans_essai  "$(juger_identite "$BLOC_IDENT" "$BAC/ident/perime.txt"   "")"

# ===================================================== SECTION C — LA COURSE EN VOL, NOMMEE ==
# Le juge passait AVANT la fin de la chaine et ne pouvait dire qu'une chose : « proof.txt absent
# ou vide ». Trois fois de suite le 12/09 a 18:12, sur un travail deja commite. Le verrou
# d'ecriture sait, lui, qu'une course ECRIT.
mkdir -p "$BAC/envol/reports"
dire_envol(){  # dire_envol <pid> -> nomme|muet
  local pid=$1
  mkdir -p "$BAC/envol/d"
  printf 'pid=%s\nlauncher=1\nitem=bac\narm=livre\nrun=course-x\nattempt=essai-B\nat=2026-09-12T18:12:00Z\n' \
    "$pid" > "$BAC/envol/d/verrou.lock"
  { printf 'set -uo pipefail\nP=bac\nD=%s\nWRN=verrou.lock\n' "$BAC/envol/d"
    printf '%s\n' "$BLOC_ENVOL"
  } > "$BAC/envol/juge.sh"
  if bash "$BAC/envol/juge.sh" 2>&1 | grep -q 'COURSE EN VOL'; then echo nomme; else echo muet; fi
}
sleep 90 & DORMEUR=$!; SEMES="$SEMES $DORMEUR"
pub ev_vivant "$(dire_envol "$DORMEUR")"
kill -KILL "$DORMEUR" 2>/dev/null; wait "$DORMEUR" 2>/dev/null
# UN PID MORT NE VAUT RIEN : un verrou qui nomme un cadavre ne doit rien annoncer.
pub ev_mort   "$(dire_envol "$DORMEUR")"

# ================================================ SECTION D — LES COMMITS PENDANT LA COURSE ==
# Pas de depot jetable : on interroge l'HISTOIRE REELLE avec le VRAI nommeur des sources de
# verdict. On remonte le premier parent commit par commit — le depart de la course est
# `HEAD~i`, donc le compte attendu est EXACTEMENT `i` — et on regarde, a chaque cran, si le
# nombre de commits touchant une source de verdict MONTE. Les deux populations doivent exister :
# sans un seul commit qui touche le juge, « 0 » ne prouverait rien ; sans un seul qui n'y touche
# pas, le classement serait un compteur deguise.
RC_ID="${AUTOPORT_CENSUS_ID:-harness-proof-file-has-no-writer-lock}"
RC_AVEC=0; RC_SANS=0; RC_POP=0; RC_EXACT=0; RC_LISTE=""; RC_PREC=0; RC_TOTAL=0
for i in $(seq 1 25); do
  p=$(git -C "$ROOT" rev-parse --verify --quiet "HEAD~$i" 2>/dev/null) || break
  [ -n "$p" ] || break
  kv=$(bash "$AP/lib/run_commits.sh" "$RC_ID" "$p" kv 2>/dev/null)
  n=$(printf '%s\n' "$kv" | sed -n 's/^proof_commits_during_run=//p' | tail -1)
  v=$(printf '%s\n' "$kv" | sed -n 's/^proof_commits_verdict_sources=//p' | tail -1)
  case "${v:-}" in ''|*[!0-9]*) break ;; esac
  RC_POP=$((RC_POP+1))
  [ "${n:--1}" = "$i" ] && RC_EXACT=$((RC_EXACT+1))
  if [ "$v" -gt "$RC_PREC" ]; then
    RC_AVEC=$((RC_AVEC+1))
    RC_LISTE="${RC_LISTE:+$RC_LISTE,}$(git -C "$ROOT" rev-parse --short=10 "HEAD~$((i-1))" 2>/dev/null)"
  else
    RC_SANS=$((RC_SANS+1))
  fi
  RC_PREC=$v; RC_TOTAL=$v
done
pub rc_population    "$RC_POP"
pub rc_compte_exact  "$RC_EXACT"
pub rc_avec_source   "$RC_AVEC"
pub rc_sans_source   "$RC_SANS"
pub rc_total_verdict "$RC_TOTAL"
pub rc_avec_liste    "${RC_LISTE:--}"
# UN DEPART INCONNU REND -1, JAMAIS 0. Un zero se lirait « rien n'a bouge » alors qu'on ne sait
# pas d'ou la course est partie — c'est la meme faute que « preuve absente » pour « pas encore
# ecrite ». Et un depart egal a HEAD rend 0 : la, rien n'a VRAIMENT bouge.
pub rc_inconnu "$(bash "$AP/lib/run_commits.sh" "$RC_ID" - count 2>/dev/null)"
pub rc_zero    "$(bash "$AP/lib/run_commits.sh" "$RC_ID" "$(git -C "$ROOT" rev-parse HEAD)" count 2>/dev/null)"

pub selftest_ran 1
