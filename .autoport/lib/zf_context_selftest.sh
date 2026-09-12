#!/usr/bin/env bash
# lib/zf_context_selftest.sh — LE BANC DE `lib/zf_context.sh`, AVEC SES CONTROLES SEMES.
#
# POURQUOI IL EXISTE. Le corpus des preuves du depot ne contient AUCUNE course a `frames=0` :
# la population que l'instrument doit couvrir est VIDE, et une porte « combien de courses a
# zero image sans contexte » y serait verte par INACTION, sans qu'une seule ligne de
# l'instrument ait tourne. On SEME donc les deux populations dans un bac a sable jetable :
# des cas que le detecteur DOIT accuser, et des cas qu'il doit LAISSER passer. Un detecteur
# aveugle rate les premiers ; un detecteur qui accuse tout rate les seconds. Les deux comptent
# dans la porte.
#
# IL NE RECOPIE RIEN. Il SOURCE `lib/zf_context.sh` : la lecture, la table des composants et le
# detecteur juges ici sont, au bit pres, ceux que `lib/proof_run.sh` appelle en course. Un banc
# qui recopie la regle mesure la recopie.
#
# L'APPAREIL N'EST PAS DANS LA BOUCLE. Les sondes tapent un `adb` FACTICE qui rend des reponses
# figees — y compris une variante MUETTE. C'est ce qui rend le cas « la sonde n'a pas repondu »
# reproductible : sur un vrai telephone il faudrait debrancher le cable au bon moment. La preuve
# que les sondes lisent un VRAI appareil vient d'ailleurs : de la course elle-meme, dont le
# recensement exige le bloc complet.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "banc_ran=0"; exit 1; }
cd "$ROOT" || exit 1
AP="$ROOT/.autoport"

LIB="$AP/lib/zf_context.sh"
[ -s "$LIB" ] || { echo "banc_ran=0"; echo "banc_lib_present=0"; exit 1; }
# shellcheck source=/dev/null
. "$LIB" || { echo "banc_ran=0"; echo "banc_lib_present=0"; exit 1; }
if ! declare -F zf_contexte >/dev/null || ! declare -F zf_juger_preuve >/dev/null \
   || ! declare -F zf_sonder_systeme >/dev/null; then
  echo "banc_ran=0"; echo "banc_lib_sourced=0"; exit 1
fi

BAC=$(mktemp -d) || { echo "banc_ran=0"; exit 1; }
trap 'rm -rf "$BAC"' EXIT

TOTAL=0; PASSES=0; RATES=0; LIGNES=""
verif(){   # verif <nom> <attendu> <obtenu>
  TOTAL=$((TOTAL+1))
  if [ "$2" = "$3" ]; then PASSES=$((PASSES+1)); LIGNES="$LIGNES
banc_cas_$1=ok"
  else RATES=$((RATES+1)); LIGNES="$LIGNES
banc_cas_$1=KO_attendu_${2}_obtenu_${3}"; fi
}

# ------------------------------------------------------------------ le faux appareil -------
mkdir -p "$BAC/rep"
cat > "$BAC/rep/window-nominal" <<'EOF'
  mCurrentFocus=Window{47ee774 u0 org.opengoal.gk.jak1/org.opengoal.gk.MainActivity}
    mKeyguardOccluded=true mKeyguardOccludedChanged=false
    mShowingDream=false mDreamingLockscreen=false
    isKeyguardShowing=false
EOF
cat > "$BAC/rep/window-verrouille" <<'EOF'
  mCurrentFocus=Window{1a2b3c u0 com.miui.home/com.miui.home.launcher.Launcher}
    mKeyguardOccluded=false mKeyguardOccludedChanged=false
    isKeyguardShowing=true
EOF
printf '  mWakefulness=Awake\n'  > "$BAC/rep/power-awake"
printf '  mWakefulness=Asleep\n' > "$BAC/rep/power-asleep"
printf 'MIUIOP(10020): allow; time=+3m16s958ms ago\n'  > "$BAC/rep/appops-allow"
printf 'MIUIOP(10020): ignore\n'                        > "$BAC/rep/appops-ignore"
printf 'MIUIOP(10020): ask\n'                           > "$BAC/rep/appops-ask"
printf 'MIUIOP(10008): ignore\nMIUIOP(10023): allow\n'  > "$BAC/rep/appops-sans-op"
printf '24033\n' > "$BAC/rep/pid"

cat > "$BAC/adb" <<'EOF'
#!/usr/bin/env bash
# adb FACTICE. Il ne connait que la forme `-s <serial> shell <commande>` que la sonde emploie.
cmd="${!#}"
case "$cmd" in
  "dumpsys window") cat "$ZF_REP/$ZF_WINDOW" ;;
  "dumpsys power")  cat "$ZF_REP/$ZF_POWER" ;;
  appops*)          cat "$ZF_REP/$ZF_APPOPS" ;;
  pidof*)           cat "$ZF_REP/pid" ;;
  *) exit 1 ;;
esac
EOF
cat > "$BAC/adb-muet" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$BAC/adb" "$BAC/adb-muet"

# ------------------------------------------------------------------ les journaux semes -----
ech(){ printf '09-12 21:57:5%s.000 %s\n' "$1" "$2"; }
{
  ech 1 'V/SDL     (24033): surfaceCreated()'
  ech 2 'I/GK_STDOUT(24033): gk_log_pipe: stdout routing active (printf test marker)'
  ech 3 'I/GK      (24033): A35-RENDER glad loaded GL entry points via SDL_GL_GetProcAddress'
  ech 4 'I/GK      (24033): A35-RENDER AndroidOpenGLRenderer init: game=jak1 GL_VERSION=OpenGL ES 3.2'
  ech 5 'I/GK      (24033): A35-RENDER jak1 bucket table ready: 60 buckets, direct=3'
  ech 6 'I/GK      (24033): A35-RENDER renderer ready (window 2400x1080)'
  ech 7 'I/GK      (24033): A35-RENDER send_chain #1 offset=0x0'
  ech 8 'I/GK      (24033): A35-RENDER frame=1 draws=10 tris=900'
} > "$BAC/log-sain"
{
  ech 1 'V/SDL     (24033): surfaceCreated()'
  ech 2 'I/GK_STDOUT(24033): gk_log_pipe: stdout routing active (printf test marker)'
  ech 3 'V/SDL     (24033): surfaceDestroyed()'
  for i in 1 2 3; do
    printf '09-12 21:57:59.%03d W/WindowManager( 1234): MIUILOG- Show when locked PermissionDenied pkg : org.opengoal.gk.jak1\n' "$i"
  done
} > "$BAC/log-appop"
sed -n '1,6p' "$BAC/log-sain" > "$BAC/log-moteur"
sed -n '1,3p' "$BAC/log-sain" > "$BAC/log-glad"

ctx(){   # ctx <window> <power> <appops> <log> <frames> [adb]
  ZF_REP="$BAC/rep" ZF_WINDOW="$1" ZF_POWER="$2" ZF_APPOPS="$3" \
  bash -c '. "$1" ; zf_sonder_systeme "$2" BANC org.opengoal.gk.jak1 "$3" ; \
           zf_contexte device "$3" "$4" "$5" org.opengoal.gk.jak1' \
       _ "$LIB" "${6:-$BAC/adb}" "$BAC/brut" "$4" "$5"
}
g(){ printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }

# =============================================================== 1. LA SONDE LIT ============
O=$(ctx window-nominal power-awake appops-allow "$BAC/log-sain" 12000)
verif sonde_complete       1 "$(g "$O" zf_context_complete)"
verif sonde_temoins        6 "$(g "$O" zf_witness_known)"
verif sonde_composants     4 "$(g "$O" zf_witness_components)"
verif sonde_paires_source  2 "$(g "$O" zf_witness_shared_pairs)"
verif sonde_dessine        sans-objet "$(g "$O" zf_verdict)"
verif sonde_echelle        premiere_image "$(g "$O" zf_last_render_marker)"

# =============================================================== 2. LA SONDE SE TAIT ========
# INCONNU EST UN DEFAUT : quatre temoins muets, bloc INCOMPLET, et le detecteur accuse.
O=$(ctx window-nominal power-awake appops-allow "$BAC/log-sain" 0 "$BAC/adb-muet")
verif muette_complete      0 "$(g "$O" zf_context_complete)"
verif muette_inconnus      4 "$(g "$O" zf_witness_unknown)"
verif muette_focus         inconnu "$(g "$O" zf_focused_window)"
verif muette_verdict       indetermine "$(g "$O" zf_verdict)"
{ echo "frames=0"; printf '%s\n' "$O"; } > "$BAC/preuve-muette"
verif muette_detectee      1 "$(g "$(zf_juger_preuve "$BAC/preuve-muette")" zfd_defaut)"

# =============================================================== 3. LA CAUSE CONNUE =========
# L'app-op 10020 a `ignore` : exactement ce qui a brule cinq courses le 11/09.
O=$(ctx window-nominal power-awake appops-ignore "$BAC/log-appop" 0)
verif appop_verdict        explique "$(g "$O" zf_verdict)"
verif appop_cause          appop-10020-ignore,refus-affichage-ecran-verrouille,surface-detruite "$(g "$O" zf_verdict_causes)"
verif appop_complete       1 "$(g "$O" zf_context_complete)"
verif appop_surface_det    1 "$(g "$O" zf_surface_destroyed)"
verif appop_refus          3 "$(g "$O" zf_appop_denials)"
# LE REFUS N'EST PAS NOTRE PROPRE VOIX : il porte le pid du serveur systeme, pas le notre.
verif appop_refus_source   system_log "$(g "$O" zf_appop_denial_component)"
verif appop_independants   3 "$(g "$O" zf_verdict_independent)"
{ echo "frames=0"; printf '%s\n' "$O"; } > "$BAC/preuve-explique"
verif appop_laissee        0 "$(g "$(zf_juger_preuve "$BAC/preuve-explique")" zfd_defaut)"
verif appop_classe         zero-explique "$(g "$(zf_juger_preuve "$BAC/preuve-explique")" zfd_classe)"

# =============================================================== 4. LE SYSTEME EST HORS DE CAUSE
O=$(ctx window-nominal power-awake appops-allow "$BAC/log-moteur" 0)
verif moteur_verdict       exclut-le-systeme "$(g "$O" zf_verdict)"
verif moteur_marqueur      renderer_pret "$(g "$O" zf_last_render_marker)"
verif moteur_rang          6 "$(g "$O" zf_render_ladder)"
O=$(ctx window-nominal power-awake appops-allow "$BAC/log-glad" 0)
verif glad_marqueur        glad_charge "$(g "$O" zf_last_render_marker)"
verif glad_rang            3 "$(g "$O" zf_render_ladder)"

# =============================================================== 5. DEUX VOIX, UN COMPOSANT =
# Trois causes dont DEUX sortent de `dumpsys window` : le verdict n'est soutenu que par DEUX
# composants distincts, jamais trois. C'est la faute proximite+lumiere, en une grandeur.
O=$(ctx window-verrouille power-awake appops-ask "$BAC/log-moteur" 0)
verif partage_causes       3 "$(g "$O" zf_verdict_cause_count)"
verif partage_independants 2 "$(g "$O" zf_verdict_independent)"
verif partage_paires       1 "$(g "$O" zf_verdict_shared_pairs)"
# Deux causes de DEUX composants : aucune paire partagee.
O=$(ctx window-nominal power-asleep appops-ignore "$BAC/log-moteur" 0)
verif distinct_causes      2 "$(g "$O" zf_verdict_cause_count)"
verif distinct_independants 2 "$(g "$O" zf_verdict_independent)"
verif distinct_paires      0 "$(g "$O" zf_verdict_shared_pairs)"

# =============================================================== 6. L'OP QUI N'EXISTE PAS ===
# Un telephone sans MIUI : le service a REPONDU, l'op n'y est pas. « absent » n'est pas
# « inconnu » — sinon tout appareil non-MIUI se lirait comme un instrument casse.
O=$(ctx window-nominal power-awake appops-sans-op "$BAC/log-sain" 12000)
verif sansop_valeur        absent "$(g "$O" zf_appop_10020)"
verif sansop_complete      1 "$(g "$O" zf_context_complete)"

# =============================================================== 7. LE DETECTEUR ============
{ echo "frames=12000"; echo "crash=0"; } > "$BAC/p-dessine"
verif det_dessine          dessine "$(g "$(zf_juger_preuve "$BAC/p-dessine")" zfd_classe)"
{ echo "frames=0"; echo "crash=0"; } > "$BAC/p-legacy"
verif det_legacy           zero-legacy "$(g "$(zf_juger_preuve "$BAC/p-legacy")" zfd_classe)"
verif det_legacy_laissee   0 "$(g "$(zf_juger_preuve "$BAC/p-legacy")" zfd_defaut)"
# BLOC AMPUTE : un producteur qui PORTE l'instrument et publie un bloc a trou est un defaut,
# pas un ancien. Sans ce cas, retirer une ligne du bloc passerait pour une preuve legacy.
grep -v '^zf_context_complete=' "$BAC/preuve-explique" > "$BAC/p-ampute"
verif det_ampute           zero-sans-contexte "$(g "$(zf_juger_preuve "$BAC/p-ampute")" zfd_classe)"
verif det_ampute_accusee   1 "$(g "$(zf_juger_preuve "$BAC/p-ampute")" zfd_defaut)"

printf 'banc_ran=1\n'
printf 'banc_lib_present=1\n'
printf 'banc_lib_sourced=1\n'
printf 'banc_lib_sha=%s\n' "$(sha256sum "$LIB" | cut -c1-16)"
printf 'banc_cas_total=%s\n' "$TOTAL"
printf 'banc_cas_passes=%s\n' "$PASSES"
printf 'banc_cas_rates=%s\n' "$RATES"
printf '%s\n' "$LIGNES" | grep -a .
