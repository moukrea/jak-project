#!/usr/bin/env bash
# lib/zf_context.sh — POURQUOI UNE COURSE N'A RIEN DESSINE, MESURE AU LIEU D'ETRE DEVINE.
#
# CE QUI EST ARRIVE (proof-context-on-zero-frames ; signalement du worker lighting-legacy-purge
# du 11/09). `frames=0` se lit exactement comme « le moteur est mort ». Il a fallu SIX essais
# pour trouver que la cause etait l'app-op MIUI 10020 a `ignore` — le systeme refusait la
# surface a notre paquet, ecran verrouille. CINQ courses ont ete brulees, trois essais entiers
# ont rediagnostique a partir de zero. Le worker s'est aussi trompe en chemin : proximite et
# lumiere ambiante ne sont PAS deux temoins independants, c'est la MEME puce.
#
# CE QUE CE FICHIER POSE. Un seul endroit definit (a) ce qu'on interroge, (b) de QUEL composant
# vient chaque reponse, (c) la lecture qu'on en fait, (d) ce qui compte comme defaut. Le
# PRODUCTEUR (`lib/proof_run.sh`) l'appelle a chaque course ; le RECENSEMENT de l'item le
# rappelle pour juger ; le BANC (`lib/zf_context_selftest.sh`) source CE fichier, il n'en
# recopie pas une ligne — une recopie mesurerait la recopie.
#
# LE CONTEXTE EST PUBLIE A CHAQUE COURSE, PAS SEULEMENT QUAND frames=0. Un collecteur qui ne
# tire que sous `if frames -eq 0` confond « rien a expliquer » et « jamais appele » : c'est le
# compteur pose apres un retour anticipe, et la course courante ne pourrait plus servir de
# temoin. La perte est rendue impossible AU POINT DE PRODUCTION ; le recensement ne fait que
# le constater.
#
# DEUX TEMOINS NE SE CORROBORENT QUE S'ILS VIENNENT DE COMPOSANTS DIFFERENTS. `mCurrentFocus`
# et `isKeyguardShowing` sortent tous les deux de `dumpsys window` : c'est UN composant, une
# seule voix. La table ci-dessous NOMME le composant de chaque temoin, et le verdict publie
# combien de composants DISTINCTS le soutiennent. C'est la meme faute que proximite+lumiere.
#
# INCONNU EST UN DEFAUT. Une sonde qui n'a pas repondu rend `inconnu`, jamais une valeur
# plausible, et le bloc est alors INCOMPLET — donc rouge. Un contexte qui invente est pire que
# pas de contexte : il ferme la piste au lieu de l'ouvrir.
#
# AUCUNE VALEUR NE PORTE D'ESPACE : `proof.txt` jette une ligne `cle=valeur` qui en contient un.
set -uo pipefail

ZF_VERSION=1

# ---- LA TABLE DES TEMOINS : nom|composant|obligatoire ----------------------------------
# Le composant est le SERVICE qui produit la reponse, pas le canal par lequel on la lit.
ZF_TEMOINS_DEVICE='focus|window_manager|1
keyguard|window_manager|1
wake|power_manager|1
appop10020|appops|1
surface|app_log|1
ladder|app_log|1'
ZF_TEMOINS_X86='display|x11_session|1
gl|engine_log|1
ladder|engine_log|1'

# ---- L'ECHELLE DE RENDU : le plus haut barreau ATTEINT dit ou ca s'est arrete ------------
# Chaque barreau est un litteral que le moteur ECRIT. Un barreau saute (present plus haut,
# absent plus bas) se lit dans `zf_render_ladder_hits`, qu'on publie a cote du rang.
ZF_ECHELLE_DEVICE='surface_creee|surfaceCreated()
stdout_branche|gk_log_pipe: stdout routing active
glad_charge|A35-RENDER glad loaded
renderer_init|A35-RENDER AndroidOpenGLRenderer init
buckets_prets|bucket table ready
renderer_pret|A35-RENDER renderer ready
chaine_envoyee|A35-RENDER send_chain #
premiere_image|A35-RENDER frame='
ZF_ECHELLE_X86='sdl_init|SDL Initialized, compiled with version
gl_init|gl init took
gl_contexte|OpenGL context version:
gpu_caps|gpu caps:
premiere_image|PACE-SWAP-X86 n='

# ---- LE COMPOSANT D'UN TEMOIN SORT DE LA TABLE, JAMAIS D'UNE SECONDE ECRITURE -------------
# Le verdict nommait le composant de chaque cause a la main, a cote de la table : deux ecritures
# de la meme regle, qui divergent en silence. Mesure du 12/09 : deplacer `keyguard` dans un
# composant a lui faisait bouger `zf_witness_components` et PAS `zf_verdict_independent` — le
# verdict continuait a jurer que deux causes de `dumpsys window` etaient une seule voix apres
# qu'on les eut separees. La cause nomme desormais SON TEMOIN, et le composant se lit ici.
# Un second argument qui n'est pas un temoin connu est pris pour un composant LITTERAL : c'est
# le cas du refus d'affichage, dont la source est MESUREE dans le journal, pas declaree.
zf_composant(){   # <nom-de-temoin-ou-composant>
  local t c o=$1
  while IFS='|' read -r t c _; do
    [ "$t" = "$o" ] && { printf '%s' "$c"; return 0; }
  done <<< "$ZF_TEMOINS_DEVICE
$ZF_TEMOINS_X86"
  printf '%s' "$o"
}

# ---- publication -------------------------------------------------------------------------
# Une valeur vide se publie `-`, jamais rien : une case vide se lit « verifie » alors qu'elle
# veut dire « pas regarde ». Les espaces sont colles AU POINT DE PUBLICATION.
zf_pub(){
  local v; v=$(printf '%s' "${2-}" | tr -s '[:space:]' '_')
  [ -n "$v" ] || v='-'
  printf '%s=%s\n' "$1" "$v"
}

# ---- le brut des sondes : sections nommees, avec leur code de retour ET leur taille --------
# `rc=0 bytes=0` et `rc=124 bytes=0` ne veulent pas dire la meme chose : la premiere est une
# reponse VIDE (le service a parle), la seconde une sonde MUETTE.
zf_section(){      # <fichier> <nom>
  [ -s "${1:-}" ] || return 0
  awk -v t="$2" 'substr($0,1,3)=="<<<"{f=(index($0,"<<<" t " ")==1); next} f' "$1"
}
zf_section_rc(){   # <fichier> <nom> -> code, ou 99 si la section n'existe pas
  local v; v=$(sed -n -E "s/^<<<$2 rc=(-?[0-9]+) bytes=[0-9]+>>>$/\1/p" "${1:-/dev/null}" 2>/dev/null | head -1)
  printf '%s' "${v:-99}"
}
zf_section_bytes(){
  local v; v=$(sed -n -E "s/^<<<$2 rc=-?[0-9]+ bytes=([0-9]+)>>>$/\1/p" "${1:-/dev/null}" 2>/dev/null | head -1)
  printf '%s' "${v:--1}"
}

# ============================================================== SONDER LE SYSTEME ===========
# Appele PENDANT que le processus mesure est encore vivant : une fenetre focalisee relue apres
# `am force-stop` nommerait le lanceur d'applications, pas notre course.
zf_sonder_systeme(){   # <adb> <serial> <pkg> <fichier-sortie>
  local adb=$1 serial=$2 pkg=$3 out=$4
  : > "$out" || return 1
  local nom cmd filtre txt rc essai n
  while IFS='|' read -r nom cmd filtre; do
    [ -n "$nom" ] || continue
    txt=""; rc=99
    for essai in 1 2; do
      # `</dev/null` : `adb shell` LIT SON ENTREE et avalerait le reste de la liste des
      # sondes. Mesure du 12/09 : sans cette redirection, seule la PREMIERE sonde etait
      # ecrite et les trois autres se lisaient « inconnu » — un instrument qui s'ampute.
      txt=$(timeout 40 "$adb" -s "$serial" shell "$cmd" </dev/null 2>/dev/null); rc=$?
      txt=$(printf '%s' "$txt" | tr -d '\r')
      [ -n "$txt" ] && break
      sleep 1
    done
    n=${#txt}
    if [ -n "$filtre" ] && [ -n "$txt" ]; then
      txt=$(printf '%s\n' "$txt" | grep -aE "$filtre" || true)
    fi
    printf '<<<%s rc=%s bytes=%s>>>\n' "$nom" "$rc" "$n" >> "$out"
    [ -n "$txt" ] && printf '%s\n' "$txt" >> "$out"
  done <<SONDES
window|dumpsys window|mCurrentFocus|isKeyguardShowing|mKeyguardOccluded|mDreamingLockscreen
power|dumpsys power|mWakefulness=
appops|appops get $pkg|MIUIOP
pid|pidof $pkg|
SONDES
  return 0
}

# ============================================================== LIRE ET JUGER ===============
# `zf_contexte <mode> <brut|-> <rawlog|-> <frames> <pkg> [rc-processus]` -> des `zf_*=...`.
# Il n'ecrit rien : il IMPRIME. Le producteur decide ou vont ces lignes.
zf_contexte(){
  local mode=$1 brut=${2:--} rawlog=${3:--} frames=${4:--1} pkg=${5:-} prc=${6:--}
  local focus="inconnu" focus_ours=-1 keyguard="inconnu" occluded="inconnu"
  local wake="inconnu" appop="inconnu" denials=-1 denial_comp="-"
  local scree=-1 sdes=-1 rang=0 hits=0 marqueur="aucun" total=0
  local display="inconnu" gl="inconnu"
  local ligne nom motif i

  case "$frames" in ''|*[!0-9-]*) frames=-1 ;; esac

  # ---------------------------------------------------------------- les sondes systeme ----
  if [ "$mode" = device ] && [ -s "$brut" ]; then
    local wrc wby arc aby prc_txt
    wrc=$(zf_section_rc "$brut" window); wby=$(zf_section_bytes "$brut" window)
    if [ "$wrc" = 0 ] && [ "${wby:-0}" -gt 0 ] 2>/dev/null; then
      ligne=$(zf_section "$brut" window | sed -n 's/.*mCurrentFocus=\(.*\)/\1/p' | head -1)
      if [ -n "$ligne" ]; then
        case "$ligne" in
          *null*) focus="aucune"; focus_ours=0 ;;
          *) focus=$(printf '%s' "$ligne" | sed -E 's/^Window\{[^ ]* [^ ]* //; s/\}.*$//')
             [ -n "$focus" ] || focus="illisible"
             case "$focus" in *"$pkg/"*) focus_ours=1 ;; *) focus_ours=0 ;; esac ;;
        esac
      fi
      ligne=$(zf_section "$brut" window | sed -n 's/.*isKeyguardShowing=\([a-z]*\).*/\1/p' | head -1)
      case "$ligne" in true) keyguard="verrouille" ;; false) keyguard="deverrouille" ;; esac
      ligne=$(zf_section "$brut" window | sed -n 's/.*mKeyguardOccluded=\([a-z]*\).*/\1/p' | head -1)
      case "$ligne" in true) occluded="occulte" ;; false) occluded="non-occulte" ;; esac
    fi
    if [ "$(zf_section_rc "$brut" power)" = 0 ] && [ "$(zf_section_bytes "$brut" power)" -gt 0 ] 2>/dev/null; then
      ligne=$(zf_section "$brut" power | sed -n 's/.*mWakefulness=\([A-Za-z]*\).*/\1/p' | head -1)
      [ -n "$ligne" ] && wake="$ligne"
    fi
    arc=$(zf_section_rc "$brut" appops); aby=$(zf_section_bytes "$brut" appops)
    if [ "$arc" = 0 ] && [ "${aby:-0}" -gt 0 ] 2>/dev/null; then
      ligne=$(zf_section "$brut" appops | sed -n 's/^MIUIOP(10020): \([a-z]*\).*/\1/p' | head -1)
      # LE SERVICE A PARLE : l'op est soit dans sa reponse, soit ABSENTE de cet appareil.
      # « absent » est une connaissance ; « inconnu » est une sonde muette. Les confondre
      # ferait passer un telephone sans MIUI pour un instrument casse.
      if [ -n "$ligne" ]; then appop="$ligne"; else appop="absent"; fi
    fi
    prc_txt=$(zf_section "$brut" pid | tr -d ' \n')
    [ -n "$prc_txt" ] && prc="$prc_txt"
  fi

  if [ "$mode" = x86 ]; then
    if [ -n "${DISPLAY:-}" ] && [ -d /tmp/.X11-unix ]; then display="${DISPLAY}"
    elif [ -n "${DISPLAY:-}" ]; then display="sans-socket"
    else display="aucun"; fi
  fi

  # ---------------------------------------------------------------- le journal du moteur --
  local echelle
  if [ "$mode" = device ]; then echelle="$ZF_ECHELLE_DEVICE"; else echelle="$ZF_ECHELLE_X86"; fi
  total=$(printf '%s\n' "$echelle" | grep -c .)
  if [ -s "$rawlog" ]; then
    i=0
    while IFS='|' read -r nom motif; do
      [ -n "$nom" ] || continue
      i=$((i+1))
      if grep -qaF -- "$motif" "$rawlog"; then
        hits=$((hits+1)); rang=$i; marqueur="$nom"
      fi
    done <<< "$echelle"
    if [ "$mode" = device ]; then
      scree=$(grep -acF 'surfaceCreated()' "$rawlog" || true); scree=$((scree+0))
      sdes=$(grep -acF 'surfaceDestroyed()' "$rawlog" || true); sdes=$((sdes+0))
      denials=$(grep -acF 'Show when locked PermissionDenied' "$rawlog" || true); denials=$((denials+0))
      if [ "$denials" -gt 0 ]; then
        # DE QUEL PROCESSUS VIENT CE REFUS : on le LIT dans le prefixe logcat, on ne le
        # suppose pas. Notre paquet et le serveur systeme ne sont pas le meme temoin.
        local dpid apid
        dpid=$(grep -aF 'Show when locked PermissionDenied' "$rawlog" | head -1 \
               | sed -n -E 's/^[0-9-]+ [0-9:.]+ +[A-Z]\/[^(]*\( *([0-9]+)\).*/\1/p')
        apid=$(printf '%s' "$prc" | tr -dc '0-9')
        if [ -n "$dpid" ] && [ -n "$apid" ] && [ "$dpid" = "$apid" ]; then denial_comp="app_log"
        elif [ -n "$dpid" ]; then denial_comp="system_log"
        else denial_comp="log_indetermine"; fi
      else
        denial_comp="sans-objet"
      fi
    else
      if grep -qaE 'gl init took|OpenGL context version:' "$rawlog"; then gl="initialise"
      elif grep -qaiE 'failed to create.*(window|context)|could not create|GLFW|SDL_Init.*fail' "$rawlog"; then gl="echec"
      else gl="jamais-atteint"; fi
    fi
  fi

  # ---------------------------------------------------------------- l'etat des temoins ----
  local table requis connus inconnus carte comps
  if [ "$mode" = device ]; then table="$ZF_TEMOINS_DEVICE"; else table="$ZF_TEMOINS_X86"; fi
  requis=0; connus=0; inconnus=0; carte=""; comps=""
  local tnom tcomp tobl val
  while IFS='|' read -r tnom tcomp tobl; do
    [ -n "$tnom" ] || continue
    requis=$((requis+1))
    case "$tnom" in
      focus)      val="$focus" ;;
      keyguard)   val="$keyguard" ;;
      wake)       val="$wake" ;;
      appop10020) val="$appop" ;;
      surface)    val=$([ "$scree" -ge 0 ] && echo connu || echo inconnu) ;;
      ladder)     val=$([ -s "$rawlog" ] && echo connu || echo inconnu) ;;
      display)    val="$display" ;;
      gl)         val="$gl" ;;
      *)          val="inconnu" ;;
    esac
    carte="${carte:+$carte,}$tnom:$tcomp"
    case "$val" in
      inconnu|illisible|"") inconnus=$((inconnus+1)) ;;
      *) connus=$((connus+1)); comps="${comps:+$comps,}$tcomp" ;;
    esac
  done <<< "$table"
  # COMBIEN DE VOIX DISTINCTES, ET COMBIEN SE REPETENT. Deux temoins du meme composant ne
  # sont pas deux temoins : `zf_witness_shared_pairs` compte les paires qui partagent leur
  # source, sur les temoins CONNUS seulement.
  local ncomp paires
  ncomp=$(printf '%s' "$comps" | tr ',' '\n' | sort -u | grep -c . )
  paires=$(printf '%s' "$comps" | tr ',' '\n' | grep -v '^$' | sort | uniq -c \
           | awk '{n=$1; s+=n*(n-1)/2} END{print s+0}')

  local complet=0
  [ "$inconnus" = 0 ] && [ "$requis" -gt 0 ] && complet=1

  # ---------------------------------------------------------------- le verdict ------------
  # Chaque cause NOMME le composant qui la porte. Deux causes du meme composant ne comptent
  # que pour UNE voix : c'est exactement la faute proximite+lumiere.
  local verdict causes ccomps
  causes=""; ccomps=""
  ajoute(){ causes="${causes:+$causes,}$1"; ccomps="${ccomps:+$ccomps,}$(zf_composant "$2")"; }
  if [ "$frames" -lt 0 ]; then
    verdict="sans-mesure"
  elif [ "$frames" -gt 0 ]; then
    verdict="sans-objet"
  else
    if [ "$mode" = device ]; then
      [ "$appop" = ignore ] && ajoute appop-10020-ignore appop10020
      [ "$appop" = ask ]    && ajoute appop-10020-ask appop10020
      [ "${denials:-0}" -gt 0 ] 2>/dev/null && ajoute refus-affichage-ecran-verrouille "$denial_comp"
      case "$wake" in Awake|inconnu) ;; *) ajoute ecran-$wake wake ;; esac
      [ "$keyguard" = verrouille ] && [ "$appop" != allow ] && ajoute ecran-verrouille keyguard
      [ "$focus_ours" = 0 ] && ajoute fenetre-non-focalisee focus
      [ "${sdes:-0}" -gt 0 ] 2>/dev/null && ajoute surface-detruite surface
    else
      case "$display" in aucun|sans-socket) ajoute session-graphique-absente display ;; esac
      [ "$gl" = echec ] && ajoute gl-non-initialise gl
    fi
    if [ -n "$causes" ]; then verdict="explique"
    elif [ "$complet" = 1 ]; then verdict="exclut-le-systeme"
    else verdict="indetermine"; fi
  fi
  unset -f ajoute
  local ncauses ncc cpaires
  ncauses=$(printf '%s' "$causes" | tr ',' '\n' | grep -c . )
  # LES VOIX INDEPENDANTES DU VERDICT : des COMPOSANTS distincts, jamais des causes. Trois
  # causes lues dans `dumpsys window` restent UNE voix.
  ncc=$(printf '%s' "$ccomps" | tr ',' '\n' | sort -u | grep -c . )
  cpaires=$(printf '%s' "$ccomps" | tr ',' '\n' | grep -v '^$' | sort | uniq -c \
            | awk '{n=$1; s+=n*(n-1)/2} END{print s+0}')

  # ---------------------------------------------------------------- publication -----------
  zf_pub zf_context_present 1
  zf_pub zf_context_version "$ZF_VERSION"
  zf_pub zf_context_mode "$mode"
  zf_pub zf_frames "$frames"
  zf_pub zf_frames_zero "$([ "$frames" = 0 ] && echo 1 || echo 0)"
  zf_pub zf_focused_window "$focus"
  zf_pub zf_focus_is_ours "$focus_ours"
  zf_pub zf_keyguard "$keyguard"
  zf_pub zf_keyguard_occluded "$occluded"
  zf_pub zf_wakefulness "$wake"
  zf_pub zf_appop_10020 "$appop"
  zf_pub zf_appop_denials "$denials"
  zf_pub zf_appop_denial_component "$denial_comp"
  zf_pub zf_surface_created "$scree"
  zf_pub zf_surface_destroyed "$sdes"
  zf_pub zf_display "$display"
  zf_pub zf_gl_state "$gl"
  zf_pub zf_last_render_marker "$marqueur"
  zf_pub zf_render_ladder "$rang"
  zf_pub zf_render_ladder_total "$total"
  zf_pub zf_render_ladder_hits "$hits"
  zf_pub zf_proc_pid "$prc"
  zf_pub zf_witness_required "$requis"
  zf_pub zf_witness_known "$connus"
  zf_pub zf_witness_unknown "$inconnus"
  zf_pub zf_witness_components "$ncomp"
  zf_pub zf_witness_shared_pairs "$paires"
  zf_pub zf_witness_map "$carte"
  zf_pub zf_context_complete "$complet"
  zf_pub zf_verdict "$verdict"
  zf_pub zf_verdict_causes "${causes:--}"
  zf_pub zf_verdict_cause_count "$ncauses"
  zf_pub zf_verdict_components "${ccomps:--}"
  zf_pub zf_verdict_independent "$ncc"
  zf_pub zf_verdict_shared_pairs "$cpaires"
}

# ============================================================== LE DETECTEUR ================
# `zf_juger_preuve <fichier>` -> `zfd_classe=...` et `zfd_defaut=0|1`.
# LA SEULE definition de « frames=0 sans contexte », partagee par le recensement et le banc.
#
# LES CLASSES, ET POURQUOI ELLES NE SE CONFONDENT PAS :
#   dessine          la course a dessine : il n'y a rien a expliquer.
#   zero-explique    frames=0, bloc PRESENT et COMPLET, verdict prononce -> l'instrument a fait
#                    son travail, meme si la cause est dans le moteur.
#   zero-legacy      frames=0 et AUCUNE cle `zf_` : la preuve sort d'un producteur ANTERIEUR a
#                    l'instrument. On la COMPTE et on la NOMME — un seau exclu n'est pas un seau
#                    correct — mais on n'accuse pas un producteur qui n'existait pas.
#   zero-sans-contexte  frames=0, le producteur PORTE l'instrument, et le bloc manque ou est
#                    incomplet. C'est le defaut, et le seul.
#   sans-frames      le fichier ne porte pas `frames=` : ce n'est pas une preuve de course.
zf_juger_preuve(){   # <fichier>
  local f=$1 fr blocs complet verdict
  if [ ! -s "$f" ]; then
    printf 'zfd_classe=%s\nzfd_defaut=%s\n' "fichier-absent" 0; return 0
  fi
  fr=$(sed -n 's/^frames=//p' "$f" 2>/dev/null | tail -1)
  case "${fr:-}" in ''|*[!0-9]*) printf 'zfd_classe=%s\nzfd_defaut=%s\n' "sans-frames" 0; return 0 ;; esac
  if [ "$fr" -gt 0 ]; then printf 'zfd_classe=%s\nzfd_defaut=%s\n' "dessine" 0; return 0; fi
  blocs=$(grep -c '^zf_[a-z_0-9]*=' "$f" 2>/dev/null || true); blocs=$((blocs+0))
  if [ "$blocs" = 0 ]; then printf 'zfd_classe=%s\nzfd_defaut=%s\n' "zero-legacy" 0; return 0; fi
  complet=$(sed -n 's/^zf_context_complete=//p' "$f" | tail -1)
  verdict=$(sed -n 's/^zf_verdict=//p' "$f" | tail -1)
  if [ "$(sed -n 's/^zf_context_present=//p' "$f" | tail -1)" = 1 ] \
     && [ "${complet:-0}" = 1 ] \
     && [ -n "${verdict:-}" ] && [ "$verdict" != "-" ] \
     && [ "$verdict" != "indetermine" ] && [ "$verdict" != "sans-mesure" ]; then
    printf 'zfd_classe=%s\nzfd_defaut=%s\n' "zero-explique" 0; return 0
  fi
  printf 'zfd_classe=%s\nzfd_defaut=%s\n' "zero-sans-contexte" 1
}
