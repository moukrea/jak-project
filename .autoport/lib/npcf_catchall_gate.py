#!/usr/bin/env python3
"""Gcutscene-npc-flicker-2 — LE SEAU FOURRE-TOUT NE DOIT JAMAIS ETRE UN SEAU EXCUSE.

CE QUE CETTE GARDE EMPECHE, ET POURQUOI ELLE EXISTE.
Au cycle 1, `classify()` finissait par `return kReasonCulled;` — le cas « je ne sais pas nommer cet
etat ». Or `culled` est declare NON-DEFAUT par `reason_is_defect`, donc tout etat non prevu tombait
dans un seau qui ne fait jamais monter `cycles`. Sur les sept courses archivees de
`.autoport/reports/Gcutscene-npc-flicker/`, ce seau portait 37 a 106 episodes par course et
`cycles` valait 0 pendant que l'owner revoyait le defaut. Un fourre-tout qui excuse est un faux
vert par construction : il rend l'instrument insensible a tout ce qu'il n'avait pas anticipe.

LA REGLE : le dernier `return` de `classify()` — celui qu'aucune condition ne garde — doit nommer
une cause que `reason_is_defect` compte comme un DEFAUT. Ne pas savoir expliquer une disparition
n'est pas une raison de la declarer normale.

CONTROLE POSITIF INTEGRE : la garde s'applique d'abord a un texte de reference qui reproduit
exactement la faute du cycle 1, et ECHOUE si elle ne la detecte pas.
"""
import re
import sys

SRC = 'game/system/npc_flicker.cpp'


def non_defect_reasons(text):
    """Les causes que reason_is_defect EXCLUT, lues dans le code et pas recopiees a la main."""
    m = re.search(r'bool reason_is_defect\(Reason r\)\s*\{(.*?)\n\}', text, re.S)
    if not m:
        return None
    return set(re.findall(r'r\s*!=\s*(kReason\w+)', m.group(1)))


def trailing_return(text):
    """La derniere instruction `return` du corps de classify(), celle qu'aucune condition ne garde."""
    m = re.search(r'Reason classify\((.*?)\n\}', text, re.S)
    if not m:
        return None
    body = m.group(1)
    rets = re.findall(r'return\s+(kReason\w+)\s*;', body)
    return rets[-1] if rets else None


def verdict(text, label):
    nd = non_defect_reasons(text)
    tr = trailing_return(text)
    if nd is None:
        return False, f"{label}: `reason_is_defect` introuvable"
    if tr is None:
        return False, f"{label}: le dernier `return` de `classify()` est introuvable"
    if tr in nd:
        return False, (f"{label}: le fourre-tout de classify() est `{tr}`, que reason_is_defect "
                       f"declare NON-DEFAUT — tout etat non prevu serait excuse en silence")
    return True, f"{label}: fourre-tout = `{tr}`, compte comme un defaut (non-defauts : {sorted(nd)})"


# --- CONTROLE POSITIF : le motif exact du cycle 1 doit ECHOUER ------------------------------------
FAUTE = '''
Reason classify(const std::string& key, bool in_tree, uint32_t status, uint32_t pid,
                int level_active) {
  if (!in_tree) {
    return kReasonDead;
  }
  return kReasonCulled;
}

bool reason_is_defect(Reason r) {
  return r != kReasonCulled && r != kReasonHidden;
}
'''
ok, msg = verdict(FAUTE, 'controle positif')
if ok:
    print("  [FAIL] controle positif : la faute du cycle 1 n'est PAS detectee — la garde est vide")
    sys.exit(1)
print("  [ok]   controle positif : `fourre-tout non-defaut` est bien detecte")

# --- LE CODE LIVRE --------------------------------------------------------------------------------
try:
    text = open(SRC).read()
except OSError as e:
    print(f"  [FAIL] {SRC} illisible : {e}")
    sys.exit(1)

ok, msg = verdict(text, SRC)
print(("  [ok]   " if ok else "  [FAIL] ") + msg)
sys.exit(0 if ok else 1)
