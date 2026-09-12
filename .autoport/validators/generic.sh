#!/usr/bin/env bash
# generic.sh — LE seul validateur. Il juge `reports/<id>/proof.txt` ecrit par la MACHINE
# (lib/proof_run.sh), jamais `report.txt` ecrit par le worker. Il ACCUMULE ses constats : une
# porte qui sort a la premiere erreur masque les suivantes. Aucune citation d'owner ici.
set -uo pipefail; cd "$(git rev-parse --show-toplevel)" || exit 1
P="${AUTOPORT_PHASE_ID:?AUTOPORT_PHASE_ID manquant}"; D=".autoport/reports/$P"; PF="$D/proof.txt"; N=0
bad(){ echo "[$P FAIL] $*" >&2; N=$((N+1)); }; kv(){ sed -n "s/^$1=//p" "$PF" 2>/dev/null | tail -1; }
eval "$(python3 - "$P" <<'PY'
import sys, yaml
sys.path.insert(0, '.autoport/lib')
try: it = __import__('backlog').load().get(sys.argv[1]) or {}
except Exception: it = next((c for c in ((yaml.safe_load(open('.autoport/backlog.yaml', encoding='utf-8')) or {}).get('items') or []) if c.get('id') == sys.argv[1]), {})
g = it.get('gate') or {}
q = lambda s: "'" + str(s).replace("'", "'\\''") + "'"
print("GK=%s GO=%s GV=%s DEV=%d FMIN=%s" % (q(g.get('key', '')), q(g.get('op', '')), q(g.get('value', '')), 1 if it.get('device') else 0, q(it.get('frames_min', 300))))
PY
)"
if [ ! -s "$PF" ]; then
  # NOMMAGE/premiere-ligne — LA CAUSE NOMMEE PASSE DEVANT (harness-impossible-single-namer, 12/09).
  # Ce juge ne peut voir qu'une chose quand aucune mesure n'etait possible : proof.txt absent. Il
  # l'ecrivait donc EN PREMIER, et qui lit sa sortie de haut en bas repartait chercher un defaut
  # de worker la ou il n'y avait qu'une machine indisponible. L'orchestrateur reecrivait bien
  # l'en-tete du JOURNAL, mais pas la sortie du juge lui-meme. Elle est ici, lue par le SEUL
  # lecteur de l'etat nomme — aucun nom de fichier code en dur — et elle ne masque rien : le
  # constat qui suit est le meme, au mot pres, et il compte toujours pour un.
  imp=$(python3 .autoport/lib/impossible.py why --reports .autoport/reports --item "$P" 2>/dev/null)
  [ -z "$imp" ] || echo "[$P PREUVE IMPOSSIBLE] $imp" >&2
  bad "proof.txt absent ou vide. Produis-le : .autoport/lib/proof_run.sh $P $([ "${DEV:-0}" = 1 ] && echo device || echo x86)"
else
  src=$(kv source); bin=build/game/gk; [ "$src" = device ] && bin=build-android/lib/arm64-v8a/libgk.so
  neuf=$(find game common android goal_src -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.gc' -o -name '*.vert' -o -name '*.frag' \) -newer "$PF" -print -quit 2>/dev/null)
  [ -z "$neuf" ] || bad "source moteur editee APRES la preuve ($neuf) : la preuve ne decrit pas ce binaire"
  # LA MEME FRAICHEUR POUR LES SOURCES DU VERDICT, `.autoport/` COMPRISE (harness-verdict-integrity).
  # La ligne ci-dessus ne regarde que le moteur. Le verdict d'un item de HARNAIS vit dans
  # `lib/census/<id>.sh` et dans les scripts qu'il appelle : ils pouvaient etre edites APRES la
  # course sans que rien ne le voie. L'empreinte est RECALCULEE ici, a la lecture — une valeur
  # recopiee de la preuve ne prouverait que la recopie — et la liste vient du MEME nommeur que
  # celui qui l'a publiee, `lib/verdict_sources.sh`. Une preuve plus vieille que son propre juge
  # est refusee, empreinte identique ou non : un `touch` ne se voit pas dans un sha.
  vs_now=$(bash .autoport/lib/verdict_sources.sh "$P" sha 2>/dev/null)
  vs_cnt=$(bash .autoport/lib/verdict_sources.sh "$P" count 2>/dev/null)
  vs_proof=$(kv verdict_sources_sha)
  if [ -z "$vs_proof" ]; then
    bad "la preuve ne porte pas 'verdict_sources_sha=' : elle vient d'un producteur qui n'epinglait pas les sources de son propre verdict. Reproduis-la."
  elif [ "$vs_proof" != "$vs_now" ]; then
    bad "verdict_sources_sha=$vs_proof recopie dans la preuve, $vs_now recalcule sur le disque ($vs_cnt fichier(s) epingle(s), liste=$(kv verdict_sources_list)) : une source du VERDICT a change depuis la course"
  fi
  [ "$(kv verdict_sources_count)" = "$vs_cnt" ] || bad "verdict_sources_count=$(kv verdict_sources_count) dans la preuve, $vs_cnt sur le disque : la liste des sources du verdict a change depuis la course"
  vsn=$(bash .autoport/lib/verdict_sources.sh "$P" newer "$PF" 2>/dev/null | paste -sd, -)
  [ -z "$vsn" ] || bad "source du VERDICT editee APRES la preuve ($vsn) : la preuve est plus vieille que son propre juge"
  # LE CRITERE PRODUIT LE VERDICT AUTANT QUE LE SCRIPT QUI LE CALCULE
  # (harness-verdict-sources-are-incomplete, 2026-09-12). `gate.key/op/value`, `frames_min` et
  # `device` vivent dans `backlog.yaml`, que l'orchestrateur reecrit toutes les secondes :
  # epingler le FICHIER ferait rougir des preuves que personne n'a touchees, et ne rien epingler
  # laissait DESSERRER un seuil apres la course sans temoin. On epingle le SOUS-ARBRE de l'item,
  # canonise par le meme nommeur que celui qui l'a publie, et recalcule ICI.
  vc_now=$(bash .autoport/lib/verdict_sources.sh "$P" criterion_sha 2>/dev/null)
  vc_proof=$(kv verdict_criterion_sha)
  if [ -z "$vc_proof" ]; then
    bad "la preuve ne porte pas 'verdict_criterion_sha=' : elle vient d'un producteur qui n'epinglait pas le CRITERE dont elle est jugee. Reproduis-la."
  elif [ "$vc_proof" != "$vc_now" ]; then
    bad "verdict_criterion_sha=$vc_proof recopie dans la preuve, $vc_now recalcule sur le disque : le CRITERE a change depuis la course (preuve: $(kv verdict_criterion) ; disque: $(bash .autoport/lib/verdict_sources.sh "$P" criterion 2>/dev/null))"
  fi
  # LES ACQUIS DE L'OWNER JUGENT A CHAQUE FERMETURE (GATE 3) et n'etaient epingles par rien.
  # Un compte de huit qui tombe a sept est un defaut, pas un detail : le nombre ET l'empreinte.
  va_now=$(bash .autoport/lib/verdict_sources.sh "$P" acquis_sha 2>/dev/null)
  va_cnt=$(bash .autoport/lib/verdict_sources.sh "$P" acquis_count 2>/dev/null)
  va_proof=$(kv verdict_acquis_sha)
  if [ -z "$va_proof" ]; then
    bad "la preuve ne porte pas 'verdict_acquis_sha=' : elle vient d'un producteur qui n'epinglait pas les gardes d'acquis de l'owner. Reproduis-la."
  elif [ "$va_proof" != "$va_now" ] || [ "$(kv verdict_acquis_count)" != "$va_cnt" ]; then
    bad "acquis : $(kv verdict_acquis_count) script(s)/$va_proof dans la preuve, $va_cnt/$va_now sur le disque — une garde d'acquis VALIDE PAR L'OWNER a change ou disparu depuis la course"
  fi
  [ "$(kv sha)" = "$(sha256sum "$bin" 2>/dev/null | cut -c1-16)" ] || bad "sha=$(kv sha) n'est pas celui de $bin sur le disque"
  [ "$(kv binary)" = "$bin" ] || bad "binary=$(kv binary) ne correspond pas a source=$src"
  [ "$(kv crash)" = 0 ] || bad "crash=$(kv crash)"
  f=$(kv frames); [ "${f:-0}" -ge "$FMIN" ] 2>/dev/null || bad "frames=${f:-absent} sous le seuil $FMIN : rien n'a ete dessine assez longtemps"
  [ "$DEV" = 0 ] || [ "$src" = device ] || bad "l'item exige l'appareil, la preuve est en source=$src"
  dm=$(kv device_lib_md5); case "${dm:-vide}" in vide|absent-*) ;; *) [ "$dm" = "$(kv local_lib_md5)" ] || bad "le libgk.so de l'appareil ($dm) n'est pas celui du build ($(kv local_lib_md5))" ;; esac
  # ---- LE TEMOIN « L'INSTRUMENT DE CET ITEM A TOURNE » (proof-feature-hits-is-vacuous, 12/09) ---
  # `hits=` de la ligne FEATURE est le compteur GLOBAL du binaire : `dead_probe_census()` le
  # remplissait a chaque passe, le recensement d'eclairage a chaque draw. « armed=1 hits>0 » etait
  # donc VRAI POUR N'IMPORTE QUEL ITEM, y compris ceux dont tout le travail vit dans
  # `lib/census/<id>.sh` et qui ne touchent pas une ligne du moteur. La porte lit desormais le
  # compte PROPRE a l'item, publie par le moteur a cote du global, et elle NOMME les deux zeros
  # que ce compteur confondait : un instrument ABSENT du binaire n'est pas un instrument PRESENT
  # que la course n'a pas atteint.
  grep -qE "^FEATURE $P armed=1 hits=[0-9]+$" "$PF" || bad "ligne 'FEATURE $P armed=1' absente : la course n'a pas ete lancee sur cet item, ou elle l'a lancee DESARME"
  own=$(kv proof_feature_own_hits); fstate=$(kv proof_feature_state); glob=$(kv proof_feature_global_hits)
  CEN=".autoport/lib/census/$P.sh"
  if [ -z "$fstate" ] || [ -z "$own" ]; then
    bad "la preuve ne porte ni 'proof_feature_state=' ni 'proof_feature_own_hits=' : elle sort d'un moteur qui ne sait pas attribuer une prise a un item, et son 'hits=' ne prouve donc rien. Rebatis gk et reproduis-la."
  else
    case "$fstate" in
      hit)
        [ "${own:-0}" -gt 0 ] 2>/dev/null || bad "proof_feature_state=hit avec proof_feature_own_hits=$own : l'etat et le compte se contredisent" ;;
      declared_unreached)
        bad "un site moteur nomme $P est bien compile dans ce binaire, mais il n'a JAMAIS tire pendant la course (proof_feature_own_hits=0, compteur global=$glob) : l'instrument de l'item n'a pas ete atteint" ;;
      absent)
        if [ -f "$CEN" ]; then
          # Item de HARNAIS : aucun site moteur, c'est normal — son verdict vit dans son
          # recensement. Le temoin devient donc « ce recensement a tourne et a publie », et il
          # sort de la MACHINE (proof_run.sh), pas du recensement lui-meme.
          [ "$(kv proof_census_present)" = 1 ] || bad "aucun site moteur ne nomme $P : son temoin est son recensement, et la preuve ne dit pas qu'il a ete lance (proof_census_present=$(kv proof_census_present))"
          [ "$(kv proof_census_rc)" = 0 ] || bad "aucun site moteur ne nomme $P : son recensement est son seul temoin, et il est sorti en $(kv proof_census_rc)"
          [ "$(kv proof_census_keys)" -gt 0 ] 2>/dev/null || bad "aucun site moteur ne nomme $P : son recensement n'a publie AUCUNE cle (proof_census_keys=$(kv proof_census_keys))"
        else
          bad "aucun site moteur ne nomme $P dans ce binaire (proof_feature_state=absent) et cet item n'a pas de recensement : rien ne prouve que l'instrument de CET item a tourne. 'hits=$glob' est le compteur GLOBAL, il monte pour tout le monde. Attribue la prise de ton instrument — note_hit_for(\"$P\", ...) et AUTOPORT_FEATURE_SITE(\"$P\") — ou publie ton verdict par un recensement."
        fi ;;
      sans_item)
        bad "proof_feature_state=sans_item : le moteur n'a recu ni AUTOPORT_FEATURE ni debug.opengoal.feature, la course ne se rattache a aucun item" ;;
      *)
        bad "proof_feature_state=$fstate : etat que le validateur ne connait pas" ;;
    esac
  fi
  if [ -n "$GK" ]; then v=$(kv "$GK")
    if [ -z "$v" ]; then bad "le proof ne porte pas '$GK=' : le moteur doit emettre cette grandeur"
    else awk -v a="$v" -v b="$GV" -v o="$GO" 'BEGIN{n=(a+0==a&&b+0==b);r=(o=="=="?(n?a+0==b+0:a==b):o=="!="?(n?a+0!=b+0:a!=b):o=="<"?a+0<b+0:o=="<="?a+0<=b+0:o==">"?a+0>b+0:o==">="?a+0>=b+0:0);exit r?0:1}' \
           || bad "$GK=$v viole le critere $GK $GO $GV"; fi
  fi
  OFF="$D/proof-off.txt"
  [ ! -s "$OFF" ] || grep -qE "^FEATURE $P armed=0 hits=0$" "$OFF" || bad "ablation : proof-off.txt ne montre pas 'armed=0 hits=0' — la feature tire encore desarmee"
fi
[ "$N" = 0 ] || { echo "[$P FAIL] $N constat(s) ci-dessus, aucun n'a ete masque par un autre." >&2; exit 1; }
echo "[$P ok] source=$(kv source) sha=$(kv sha) frames=$(kv frames) crash=0${GK:+ ; $GK $GO $GV tenu}"
