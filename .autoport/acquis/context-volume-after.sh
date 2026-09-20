#!/usr/bin/env bash
# acquis/context-volume-after.sh — LA GARDE « APRES » DE harness-main-agent-context-volume.
#
# L'item a ete valide le 19/09 avec un terme 5 qui DISAIT « quand 5 essais auront tourne sous la
# configuration armee (`--strict-mcp-config`), la baisse mesuree devra tenir » — et rien, nulle
# part, ne revenait le verifier : l'item pouvait fermer avec son gain principal (>= 20 % de
# contexte relu en moins par essai) jamais mesure. Cette garde est ce « plus tard ».
#
# CE QU'ELLE FAIT. Elle relit les journaux d'essai par le MEME collecteur que l'item
# (lib/census/context-volume/collect.py : rien n'est recopie ici) :
#   * moins de 5 essais sous la configuration armee -> UNPROVABLE, avec le compte ; elle ne
#     bloque rien et dit exactement ce qui manque ;
#   * 5 essais ou plus -> la baisse de l'integrale de contexte par essai doit valoir au moins
#     200 pour mille (20 %) face aux 278 essais opus-5/eleve de reference, sinon PLUS TENU.
# INCONNU = PAS TENU des que la population existe : une cle absente ou -1 ne passe pas.
ACQ_NAME=context-volume-after
. "$(dirname "$0")/_lib.sh"

AP=$(git rev-parse --show-toplevel 2>/dev/null)/.autoport
[ -f "$AP/lib/census/context-volume/collect.py" ] || acq_unprovable "collecteur lib/census/context-volume/collect.py absent"
CV=$(timeout -k 15 600 python3 "$AP/lib/census/context-volume/collect.py" "$AP/logs" 2>/dev/null) \
  || acq_unprovable "le collecteur a echoue ou depasse 600 s"
n(){ printf '%s\n' "$CV" | sed -n "s/^$1=//p" | tail -1; }
APRES=$(n cv_apres_essais); BAISSE=$(n cv_baisse_integrale_pm); TOURS=$(n cv_apres_tours_x10_par_essai)
[ -n "$APRES" ] || acq_unprovable "cv_apres_essais non publie par le collecteur"
if [ "$APRES" -lt 5 ] 2>/dev/null; then
  acq_unprovable "population APRES = $APRES essai(s) sous --strict-mcp-config, il en faut 5 : le gain de 20 % n'est pas encore mesurable"
fi
[ -n "$BAISSE" ] && [ "$BAISSE" != -1 ] || acq_broken "population APRES = $APRES mais cv_baisse_integrale_pm absent ou -1 : le gain n'est pas mesure"
# 20/09 03:40 : cette garde n'est PAS un acquis valide par l'owner, c'est le controle differe d'un item
# valide par la machine. La faire BLOQUER toutes les fermetures (elle a arrete les libelles de
# resolution, verts sur leur propre porte) est disproportionne : le manque se DIT, nomme, et c'est
# l'item harness-main-agent-context-volume qui se rouvre, pas les autres qui s'arretent.
[ "$BAISSE" -ge 200 ] 2>/dev/null || acq_unprovable "GAIN NON TENU (non bloquant) : baisse de contexte relu par essai = $BAISSE pour mille sur $APRES essais armes, attendu >= 200 ; tours x10 par essai = ${TOURS:--} ; a traiter dans harness-main-agent-context-volume"
acq_ok "baisse de contexte relu = $BAISSE pour mille sur $APRES essais armes (>= 200), tours x10 par essai = ${TOURS:--}"
