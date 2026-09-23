#!/usr/bin/env python3
"""Ce que le SUPERVISEUR coute, lu sur ses propres transcriptions.

POURQUOI CE FICHIER EXISTE. Le harnais compte le cout des ESSAIS (logs/<item>/attempt-*.jsonl)
et rien d'autre. Le superviseur — la session Claude Code interactive qui parle a l'owner — a
tourne 94 jours sans qu'aucun compteur ne la regarde. Mesure du 2026-09-19 : 9 033 $ sur la
vie du projet, ~96 $ par jour, dont 49 % en REVEILS AUTOMATIQUES (le cron de supervision
30 min) que personne n'avait chiffres.

CE QU'IL LIT. Les transcriptions de Claude Code, `~/.claude/projects/<depot>/*.jsonl`. Une
ligne `assistant` y porte son `usage` REEL (jetons d'entree, d'ecriture de cache, de lecture
de cache, de sortie) et le modele qui l'a facturee. C'est la seule source qui dise ce qui a
ete PAYE ; `costUSD` n'est publie que par intermittence et `attempt_end` compte 2 a 4 fois
(voir FINDINGS de owner-se-renseigner-sur-le-combo-le-plus-efficient-tou, 19/09).

LES TROIS PIEGES, ET CE QU'ON EN FAIT
  1. UN MEME APPEL EST ECRIT PLUSIEURS FOIS. Un message d'assistant a un bloc par contenu
     (reflexion, texte, appel d'outil) et CHAQUE bloc reporte le MEME `usage`. Sommer les
     lignes gonfle la facture de 70 %. On dedoublonne par `requestId` ; mesure sur les
     34 487 lignes du superviseur : les copies sont TOUJOURS adjacentes (ecart max 1), ce
     qui rend le dedoublonnage exact meme en lecture incrementale. L'ecart max observe est
     publie (`sc_rid_ecart_max`) : s'il depasse la fenetre, le compteur le DIT.
  2. LE DOSSIER NE CONTIENT PAS QUE LE SUPERVISEUR. 746 des 1 028 sessions sont des ESSAIS
     (les workers tournent dans le meme repertoire de travail), 254 sont un lot d'images.
     Les confondre est ce qui a fait annoncer « 11 000 $ de superviseur » : c'etait le
     dossier entier. Le role d'une session se lit sur son PREMIER prompt et sur la presence
     de reveils programmes ; il est publie par role.
  3. L'ECRITURE DE CACHE N'A PAS UN SEUL TARIF. 266 M des 268 M de jetons ecrits par le
     superviseur le sont en TTL 1 heure, facture 2x l'entree, pas 1,25x. Le detail est dans
     `usage.cache_creation` ; quand il manque, on facture au tarif 5 min et on compte la
     ligne dans `sc_ecriture_sans_ttl` plutot que de se taire.

CE QU'IL PUBLIE. Un bloc court pour l'owner (`--bloc`, repris par `autoport status`, donc lu
par le digest), un instantane machine (`--json`), et les cles `sc_*` du recensement
(`--recensement`). Le chemin incremental ne relit que les octets NEUFS : la premiere passe
lit 2 Go, les suivantes quelques kilo-octets.
"""
import argparse
import json
import os
import sys
import time

AP = os.path.dirname(os.path.abspath(__file__))
AP = os.path.dirname(AP)                      # .../.autoport
ROOT = os.path.dirname(AP)

# Le banc (`lib/census/supervisor-cost/selftest.py`) fait tourner CE module sur une
# transcription fabriquee dont il connait la reponse : il lui faut son propre cache, sinon il
# mesurerait celui du depot et ne prouverait rien.
CACHE = os.environ.get("AUTOPORT_COST_CACHE") or os.path.join(AP, ".supervisor_cost_cache.json")
SNAPSHOT = os.environ.get("AUTOPORT_COST_SNAPSHOT") or os.path.join(AP, ".supervisor_cost.json")
LANCEMENTS = os.path.join(AP, "logs", "supervisor-launches.jsonl")

VERSION_CACHE = 3

# ------------------------------------------------------------------ TARIFS
# $/million de jetons : (entree, ecriture 5 min, ecriture 1 h, lecture de cache, sortie).
# Source : documentation Anthropic du 2026-09-19 (skill claude-api, table « Current Models »
# + shared/prompt-caching.md § Economics). Ecriture = 1,25x l'entree en TTL 5 min, 2x en TTL
# 1 heure ; lecture = 0,1x l'entree, sauf Fable 5.1 a 0,025x. Pas de surcout « contexte
# long » : la fenetre 1M est au tarif standard sur Opus 4.7/4.8/5.
TARIFS = {
    # Opus 5.5 (23/09, skill claude-api 2.1.280) : 4 $ / 20 $, lecture de cache 0,20 $ (0,05x,
    # pas 0,1x), ecritures 1,25x / 2x de l'entree.
    "claude-opus-5-5":   (4.0,  5.0,   8.0, 0.20, 20.0),
    "claude-opus-5":     (5.0,  6.25, 10.0, 0.50, 25.0),
    "claude-opus-4-8":   (5.0,  6.25, 10.0, 0.50, 25.0),
    "claude-opus-4-7":   (5.0,  6.25, 10.0, 0.50, 25.0),
    "claude-opus-4-6":   (5.0,  6.25, 10.0, 0.50, 25.0),
    "claude-fable-5":    (10.0, 12.5, 20.0, 1.00, 50.0),
    "claude-fable-5-1":  (10.0, 12.5, 20.0, 0.25, 50.0),
    "claude-sonnet-5":   (2.0,  2.5,   4.0, 0.20, 10.0),
    "claude-sonnet-4-6": (3.0,  3.75,  6.0, 0.30, 15.0),
    "claude-haiku-4-5":  (1.0,  1.25,  2.0, 0.10,  5.0),
}

FAMILLES = ("veille", "owner", "fin-de-tache", "reprise", "autre")

# Les familles de prompts INJECTES qui ne sont PAS des reveils. Tout le reste de ce qui est
# injecte dans une session de superviseur est un reveil : les libelles du cron ont change
# quatre fois en trois mois (« Auto progress check », « Supervision 30-min », « [orchestrator
# monitor] », « Supervision autoport »), donc une liste de libelles serait aveugle des le
# prochain changement. On nomme l'EXCEPTION, pas la regle.
INJECTE_NON_VEILLE = (
    ("<task-notification>", "fin-de-tache"),
    ("This session is being continued", "reprise"),
    ("Your claude.ai usage limit", "reprise"),
    ("Another Claude session sent", "autre"),
    ("<local-command", "autre"),
    ("<command-name>", "autre"),
    ("[Request interrupted", "autre"),
)

BIN_PREFIXE = 25000          # largeur d'un casier d'histogramme de prefixe, en jetons
NBIN_PREFIXE = 45            # jusqu'a 1,125 M


def _slug(path):
    return path.replace("/", "-")


def dossier_transcriptions(root=ROOT):
    env = os.environ.get("AUTOPORT_TRANSCRIPTS")
    if env:
        return env
    return os.path.join(os.path.expanduser("~"), ".claude", "projects", _slug(root))


def modele_normalise(m):
    """`claude-opus-5[1m]`, `claude-haiku-4-5-20251001` -> la cle de tarif."""
    if not m:
        return ""
    m = m.strip()
    if m.endswith("]"):
        i = m.rfind("[")
        if i > 0:
            m = m[:i]
    if m in TARIFS:
        return m
    # suffixe de date : claude-haiku-4-5-20251001
    bouts = m.split("-")
    while bouts:
        cand = "-".join(bouts)
        if cand in TARIFS:
            return cand
        bouts.pop()
    return ""


def cout(modele, entree, ecr5, ecr1h, lecture, sortie):
    t = TARIFS.get(modele)
    if not t:
        return 0.0, 0.0, 0.0, 0.0
    c_lec = lecture * t[3] / 1e6
    c_ecr = (ecr5 * t[1] + ecr1h * t[2]) / 1e6
    c_sor = sortie * t[4] / 1e6
    c_ent = entree * t[0] / 1e6
    return c_ent, c_ecr, c_lec, c_sor


# --------------------------------------------------------------- etat par fichier
def _etat_neuf(nom):
    return {"nom": nom, "taille": 0, "mtime_ns": 0, "offset": 0, "role": "inconnu",
            "premier_prompt": "", "debut": "", "fin": "", "req": 0, "reveils_programmes": 0,
            "rid_ecart_max": 0, "modeles_inconnus": 0, "jetons_non_tarifes": 0,
            "ecriture_sans_ttl": 0,
            "jours": {}, "familles": {}, "tour": None, "rid_recents": [], "index": 0}


def _jour(etat, d):
    j = etat["jours"].get(d)
    if j is None:
        j = {"cout": 0.0, "req": 0, "entree": 0.0, "ecriture": 0.0, "lecture": 0.0,
             "sortie": 0.0, "prefixe_somme": 0, "prefixe_n": 0,
             "hist": {}, "familles": {}, "veilles": 0, "veilles_muettes": 0}
        etat["jours"][d] = j
    return j


def _fam(dico, nom):
    f = dico.get(nom)
    if f is None:
        f = {"cout": 0.0, "tours": 0, "req": 0}
        dico[nom] = f
    return f


def famille_du_prompt(texte, injecte, source):
    t = " ".join(texte.split())
    for prefixe, fam in INJECTE_NON_VEILLE:
        if t.startswith(prefixe):
            return fam
    if injecte and source in (None, "system"):
        return "veille"
    if source in ("typed", "queued", "suggestion_accepted", None):
        return "owner"
    return "autre"


def _cloture_tour(etat):
    """UN TOUR SE JUGE QUAND IL EST FINI. « Muet » veut dire : le superviseur s'est reveille,
    a travaille, et n'a RIEN rendu a l'owner. On ne peut le savoir qu'au tour suivant — le
    compter au premier appel puis le decompter aurait donne un compteur qui oscille."""
    tour = etat.get("tour")
    if not tour or not tour.get("compte"):
        return
    if tour["famille"] == "veille" and tour["texte_rendu"] == 0:
        jour = tour.get("jour") or etat.get("fin") or ""
        if jour:
            _jour(etat, jour)["veilles_muettes"] += 1
    etat["tour"] = None


def _texte_du_contenu(contenu):
    """Le texte d'un message, et s'il s'agit d'un RESULTAT d'outil (qui ne demarre pas un tour)."""
    if isinstance(contenu, str):
        return contenu, False
    if isinstance(contenu, list):
        for p in contenu:
            if isinstance(p, dict) and p.get("type") == "tool_result":
                return "", True
        return " ".join(p.get("text", "") for p in contenu
                        if isinstance(p, dict) and p.get("type") == "text"), False
    return "", False


def role_de_session(premier_prompt, a_des_reveils):
    t = " ".join((premier_prompt or "").split())
    if "DIRECTIVES v" in t or "## CET ESSAI" in t:
        return "essai"
    if "contact sheet of 16 textures" in t:
        return "lot-images"
    if a_des_reveils:
        return "superviseur"
    if not t:
        return "inconnu"
    return "atelier"


def lire_fichier(chemin, etat, budget_octets=None):
    """Avale les octets NEUFS de `chemin` dans `etat`. Rend le nombre d'octets lus."""
    try:
        st = os.stat(chemin)
    except OSError:
        return 0
    if st.st_size == etat["taille"] and st.st_mtime_ns == etat["mtime_ns"]:
        return 0
    if st.st_size < etat["offset"]:                       # fichier reecrit : on repart de zero
        nom = etat["nom"]
        etat.clear()
        etat.update(_etat_neuf(nom))
    if budget_octets is not None and st.st_size - etat["offset"] > budget_octets:
        return -1                                          # trop gros pour ce chemin-la
    lus = 0
    with open(chemin, "rb") as fh:
        fh.seek(etat["offset"])
        reste = b""
        while True:
            bloc = fh.read(1 << 22)
            if not bloc:
                break
            lus += len(bloc)
            bloc = reste + bloc
            lignes = bloc.split(b"\n")
            reste = lignes.pop()
            for brute in lignes:
                _ligne(etat, brute)
            etat["offset"] += len(bloc) - len(reste)
        # `reste` est une ligne incomplete : elle sera relue au prochain passage.
    etat["taille"] = st.st_size
    etat["mtime_ns"] = st.st_mtime_ns
    return lus


def _ligne(etat, brute):
    # LE FILTRE QUI EVITE D'ANALYSER 2 Go DE JSON. Il cherche `"user"` et non `"type":"user"` :
    # le second dependrait de la mise en forme de l'ecrivain (avec ou sans espace apres le
    # deux-points), et un banc ecrit en `json.dumps` par defaut passerait a cote de TOUS les
    # prompts sans qu'aucun total ne bouge — le cout resterait juste, les familles a zero.
    if b'"usage"' not in brute and b'"user"' not in brute \
       and b'scheduled_task_fire' not in brute:
        return
    try:
        o = json.loads(brute.decode("utf-8", "replace"))
    except Exception:                                      # noqa: BLE001 — ligne illisible
        return
    t = o.get("type")
    ts = o.get("timestamp") or ""
    if t == "system" and o.get("subtype") == "scheduled_task_fire":
        etat["reveils_programmes"] += 1
        return
    if t == "user":
        if o.get("isSidechain"):
            return
        msg = o.get("message") or {}
        texte, resultat_outil = _texte_du_contenu(msg.get("content"))
        if resultat_outil or not texte.strip():
            return
        if not etat["premier_prompt"] and not o.get("isMeta"):
            etat["premier_prompt"] = texte[:400]
        _cloture_tour(etat)
        fam = famille_du_prompt(texte, bool(o.get("isMeta")), o.get("promptSource"))
        etat["tour"] = {"famille": fam, "jour": ts[:10], "texte_rendu": 0, "req": 0,
                        "cout": 0.0, "compte": False}
        return
    if t != "assistant":
        return
    msg = o.get("message") or {}
    u = msg.get("usage") or {}
    rid = o.get("requestId") or msg.get("id") or ""
    etat["index"] += 1
    # DEDOUBLONNAGE. Le meme appel est ecrit une fois par bloc de contenu, avec le MEME usage.
    # Les copies sont adjacentes (mesure : ecart max 1 sur 34 487 lignes) ; on garde quand meme
    # une fenetre de 16 et on PUBLIE l'ecart maximal observe. Si un jour il atteint la fenetre,
    # `sc_rid_ecart_max` le dira au lieu de laisser le compteur sous-facturer en silence.
    recents = etat["rid_recents"]
    if rid:
        for pos, (vu, idx) in enumerate(recents):
            if vu == rid:
                etat["rid_ecart_max"] = max(etat["rid_ecart_max"], etat["index"] - idx)
                recents[pos] = (vu, etat["index"])
                return
        recents.append((rid, etat["index"]))
        if len(recents) > 16:
            del recents[:-16]
    modele = modele_normalise(msg.get("model"))
    if not modele:
        etat["modeles_inconnus"] += 1
        etat["jetons_non_tarifes"] += (int(u.get("input_tokens") or 0)
                                       + int(u.get("cache_creation_input_tokens") or 0)
                                       + int(u.get("cache_read_input_tokens") or 0)
                                       + int(u.get("output_tokens") or 0))
    cc = u.get("cache_creation") or {}
    ecr1h = int(cc.get("ephemeral_1h_input_tokens") or 0)
    ecr5 = int(cc.get("ephemeral_5m_input_tokens") or 0)
    ecr_total = int(u.get("cache_creation_input_tokens") or 0)
    if not cc and ecr_total:
        ecr5 = ecr_total
        etat["ecriture_sans_ttl"] += 1
    lecture = int(u.get("cache_read_input_tokens") or 0)
    entree = int(u.get("input_tokens") or 0)
    sortie = int(u.get("output_tokens") or 0)
    c_ent, c_ecr, c_lec, c_sor = cout(modele, entree, ecr5, ecr1h, lecture, sortie)
    c = c_ent + c_ecr + c_lec + c_sor
    jour = ts[:10] or (etat["tour"] or {}).get("jour") or ""
    if not jour:
        return
    if not etat["debut"] or jour < etat["debut"]:
        etat["debut"] = jour
    if jour > etat["fin"]:
        etat["fin"] = jour
    j = _jour(etat, jour)
    j["cout"] += c
    j["req"] += 1
    j["entree"] += c_ent
    j["ecriture"] += c_ecr
    j["lecture"] += c_lec
    j["sortie"] += c_sor
    prefixe = lecture + ecr5 + ecr1h + entree
    j["prefixe_somme"] += prefixe
    j["prefixe_n"] += 1
    casier = str(min(prefixe // BIN_PREFIXE, NBIN_PREFIXE - 1))
    j["hist"][casier] = j["hist"].get(casier, 0) + 1
    etat["req"] += 1
    tour = etat["tour"]
    fam = tour["famille"] if tour else "autre"
    f = _fam(etat["familles"], fam)
    f["cout"] += c
    f["req"] += 1
    fj = _fam(j["familles"], fam)
    fj["cout"] += c
    fj["req"] += 1
    if tour is not None:
        tour["req"] += 1
        tour["cout"] += c
        if not tour["compte"]:
            tour["compte"] = True
            f["tours"] += 1
            fj["tours"] += 1
            if fam == "veille":
                j["veilles"] += 1
        if not tour["jour"]:
            tour["jour"] = jour
        texte = "".join(p.get("text", "") for p in (msg.get("content") or [])
                        if isinstance(p, dict) and p.get("type") == "text")
        if len(texte.strip()) > 40:
            tour["texte_rendu"] += 1


# ------------------------------------------------------------------- recensement
def charger_cache():
    try:
        with open(CACHE, encoding="utf-8") as fh:
            d = json.load(fh)
        if d.get("version") == VERSION_CACHE:
            return d
    except Exception:                                      # noqa: BLE001
        pass
    return {"version": VERSION_CACHE, "fichiers": {}}


def ecrire_cache(d):
    tmp = CACHE + ".%d.tmp" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(d, fh)
    os.replace(tmp, CACHE)


def rafraichir(roles=None, budget_octets=None, dossier=None):
    """Relit ce qui a bouge. `roles` limite le travail aux sessions de ces roles-la."""
    d = charger_cache()
    dossier = dossier or dossier_transcriptions()
    t0 = time.time()
    lus = 0
    sautes = 0
    try:
        noms = sorted(n for n in os.listdir(dossier) if n.endswith(".jsonl"))
    except OSError:
        noms = []
    for nom in noms:
        etat = d["fichiers"].get(nom) or _etat_neuf(nom)
        if roles and etat["role"] not in ("inconnu", "") and etat["role"] not in roles:
            d["fichiers"][nom] = etat
            continue
        n = lire_fichier(os.path.join(dossier, nom), etat, budget_octets)
        if n < 0:
            sautes += 1
        else:
            lus += n
        etat["role"] = role_de_session(etat["premier_prompt"], etat["reveils_programmes"] > 0)
        if etat["role"] not in ("superviseur", "inconnu"):
            _compacte(etat)
        d["fichiers"][nom] = etat
    d["ms"] = int((time.time() - t0) * 1000)
    d["octets_lus"] = lus
    d["sautes"] = sautes
    d["dossier"] = dossier
    ecrire_cache(d)
    return d


def _compacte(etat):
    """Un role qui n'est PAS le superviseur ne publie que son total : on jette son detail par
    jour. Sans ca le cache pese 5,6 Mo et le digest, qui le relit, paie pour un detail que
    personne ne lit."""
    jours = etat.get("jours") or {}
    if len(jours) <= 1 and "_total" in jours:
        return
    tot = {"cout": 0.0, "req": 0, "entree": 0.0, "ecriture": 0.0, "lecture": 0.0,
           "sortie": 0.0, "prefixe_somme": 0, "prefixe_n": 0, "hist": {}, "familles": {},
           "veilles": 0, "veilles_muettes": 0}
    for j in jours.values():
        for k in ("cout", "req", "entree", "ecriture", "lecture", "sortie",
                  "prefixe_somme", "prefixe_n", "veilles", "veilles_muettes"):
            tot[k] += j.get(k, 0)
    etat["jours"] = {"_total": tot}


def _mediane_hist(hist):
    """La mediane du prefixe, au casier pres (25 k jetons). Un histogramme creux : seuls les
    casiers non vides sont gardes, sinon le cache pese 5,6 Mo et le digest paie sa relecture."""
    total = sum(hist.values())
    if not total:
        return 0
    vu = 0
    for i in sorted(hist, key=int):
        vu += hist[i]
        if vu * 2 >= total:
            return int((int(i) + 0.5) * BIN_PREFIXE)
    return int(NBIN_PREFIXE * BIN_PREFIXE)


def _ajoute_hist(dest, src):
    for i, n in (src or {}).items():
        dest[i] = dest.get(i, 0) + n
    return dest


def agreger(d, role="superviseur"):
    """Somme les etats de fichier d'un role en un seul releve, par jour et par famille."""
    jours = {}
    familles = {}
    sessions = 0
    req = 0
    reveils_prog = 0
    ecart_max = 0
    inconnus = 0
    non_tarifes = 0
    sans_ttl = 0
    for etat in d.get("fichiers", {}).values():
        if etat.get("role") != role:
            continue
        sessions += 1
        req += etat.get("req", 0)
        reveils_prog += etat.get("reveils_programmes", 0)
        ecart_max = max(ecart_max, etat.get("rid_ecart_max", 0))
        inconnus += etat.get("modeles_inconnus", 0)
        non_tarifes += etat.get("jetons_non_tarifes", 0)
        sans_ttl += etat.get("ecriture_sans_ttl", 0)
        for nom, f in (etat.get("familles") or {}).items():
            g = _fam(familles, nom)
            g["cout"] += f["cout"]
            g["tours"] += f["tours"]
            g["req"] += f["req"]
        for jour, j in (etat.get("jours") or {}).items():
            g = jours.get(jour)
            if g is None:
                g = {"cout": 0.0, "req": 0, "entree": 0.0, "ecriture": 0.0, "lecture": 0.0,
                     "sortie": 0.0, "prefixe_somme": 0, "prefixe_n": 0,
                     "hist": {}, "familles": {}, "veilles": 0, "veilles_muettes": 0}
                jours[jour] = g
            for k in ("cout", "req", "entree", "ecriture", "lecture", "sortie",
                      "prefixe_somme", "prefixe_n", "veilles", "veilles_muettes"):
                g[k] += j.get(k, 0)
            _ajoute_hist(g["hist"], j.get("hist"))
            for nom, f in (j.get("familles") or {}).items():
                h = _fam(g["familles"], nom)
                h["cout"] += f["cout"]
                h["tours"] += f["tours"]
                h["req"] += f["req"]
    return {"sessions": sessions, "req": req, "jours": jours, "familles": familles,
            "reveils_programmes": reveils_prog, "rid_ecart_max": ecart_max,
            "modeles_inconnus": inconnus, "jetons_non_tarifes": non_tarifes,
            "ecriture_sans_ttl": sans_ttl}


def essais_par_jour(root=ROOT):
    """Combien d'essais ont tourne chaque jour, pour le cout PAR ESSAI."""
    import glob
    par_jour = {}
    for f in glob.glob(os.path.join(root, ".autoport", "logs", "*", "attempt-*.jsonl")):
        try:
            d = time.strftime("%Y-%m-%d", time.localtime(os.stat(f).st_mtime))
        except OSError:
            continue
        par_jour[d] = par_jour.get(d, 0) + 1
    return par_jour


def lancements_armes(chemin=LANCEMENTS):
    """Les demarrages de superviseur enregistres par `supervisor.sh`, du plus recent au plus
    ancien. C'est la CONFIGURATION qui designe la population « apres », pas un seuil sur une
    grandeur qui derive."""
    out = []
    try:
        with open(chemin, encoding="utf-8") as fh:
            for ligne in fh:
                ligne = ligne.strip()
                if not ligne:
                    continue
                try:
                    out.append(json.loads(ligne))
                except Exception:                          # noqa: BLE001
                    continue
    except OSError:
        pass
    return out


def releve(d=None, jours_recents=7):
    d = d if d is not None else charger_cache()
    ag = agreger(d, "superviseur")
    jours = ag["jours"]
    noms_jours = sorted(jours)
    total = sum(j["cout"] for j in jours.values())
    recents = noms_jours[-jours_recents:]
    cout_recent = sum(jours[x]["cout"] for x in recents)
    essais = essais_par_jour()
    essais_recents = sum(essais.get(x, 0) for x in recents)
    hist = {}
    for j in jours.values():
        _ajoute_hist(hist, j["hist"])
    hist_recent = {}
    for x in recents:
        _ajoute_hist(hist_recent, jours[x]["hist"])
    lect = sum(j["lecture"] for j in jours.values())
    ecr = sum(j["ecriture"] for j in jours.values())
    sor = sum(j["sortie"] for j in jours.values())
    ent = sum(j["entree"] for j in jours.values())
    return {
        "total": total, "jours": len(noms_jours), "premier": noms_jours[0] if noms_jours else "",
        "dernier": noms_jours[-1] if noms_jours else "", "req": ag["req"],
        "sessions": ag["sessions"], "familles": ag["familles"],
        "par_jour": {x: jours[x]["cout"] for x in noms_jours},
        "veilles": {x: jours[x]["veilles"] for x in noms_jours},
        "veilles_muettes": {x: jours[x]["veilles_muettes"] for x in noms_jours},
        "cout_jour": total / max(len(noms_jours), 1),
        "cout_jour_recent": cout_recent / max(len(recents), 1),
        "cout_essai_recent": cout_recent / essais_recents if essais_recents else 0.0,
        "essais_recents": essais_recents,
        "prefixe_median": _mediane_hist(hist),
        "prefixe_median_recent": _mediane_hist(hist_recent),
        "lecture": lect, "ecriture": ecr, "sortie": sor, "entree": ent,
        "rid_ecart_max": ag["rid_ecart_max"], "modeles_inconnus": ag["modeles_inconnus"],
        "jetons_non_tarifes": ag["jetons_non_tarifes"],
        "ecriture_sans_ttl": ag["ecriture_sans_ttl"],
        "reveils_programmes": ag["reveils_programmes"],
        "jours_detail": jours,
    }


# --------------------------------------------------------------------- sorties
def bloc_owner(r):  # noqa: D401
    """Trois lignes, en francais courant. Ce bloc part dans `autoport status`, donc dans le
    digest : il ne porte AUCUNE valeur a la seconde — seulement des chiffres du JOUR, sinon le
    digest se reveillerait a chaque appel (voir backlog.py, hash du digest)."""
    if not r["jours"]:
        return ""
    fam = r["familles"]
    tot = sum(f["cout"] for f in fam.values()) or 1.0
    ordre = sorted(fam.items(), key=lambda kv: -kv[1]["cout"])[:2]
    parts = ", ".join("%s %d %%" % (_mot(nom), round(100 * f["cout"] / tot))
                      for nom, f in ordre)
    return "\n".join([
        "## Ce que le superviseur coute",
        "%d $ par jour en moyenne sur les %d derniers jours ; %d $ depuis le %s."
        % (round(r["cout_jour_recent"]), min(7, r["jours"]), round(r["total"]), r["premier"]),
        "Ce qui coute le plus : %s." % parts,
        "Detail : ./.autoport/autoport cost",
    ])


def _mot(famille):
    return {"veille": "les reveils automatiques du superviseur",
            "owner": "tes questions et tes retours",
            "fin-de-tache": "les fins d'essai qui le reveillent",
            "reprise": "les reprises apres saturation de memoire",
            "autre": "le reste"}.get(famille, famille)


def texte_detail(r):
    lignes = ["Superviseur — %s a %s (%d jours, %d sessions, %d appels)"
              % (r["premier"], r["dernier"], r["jours"], r["sessions"], r["req"])]
    lignes.append("Total %.0f $ — %.0f $/jour en moyenne, %.0f $/jour sur les 7 derniers jours"
                  % (r["total"], r["cout_jour"], r["cout_jour_recent"]))
    if r["essais_recents"]:
        lignes.append("Soit %.2f $ par essai du harnais sur ces 7 jours (%d essais)"
                      % (r["cout_essai_recent"], r["essais_recents"]))
    t = r["total"] or 1.0
    lignes.append("Ou part l'argent : relecture du contexte %.0f %% (%.0f $), ecriture de "
                  "cache %.0f %% (%.0f $), reponses %.0f %% (%.0f $), entree neuve %.0f %%"
                  % (100 * r["lecture"] / t, r["lecture"], 100 * r["ecriture"] / t,
                     r["ecriture"], 100 * r["sortie"] / t, r["sortie"],
                     100 * r["entree"] / t))
    lignes.append("Contexte relu a chaque appel : %d k jetons (mediane), %d k sur 7 jours"
                  % (r["prefixe_median"] / 1000, r["prefixe_median_recent"] / 1000))
    lignes.append("")
    lignes.append("Qui le reveille :")
    for nom, f in sorted(r["familles"].items(), key=lambda kv: -kv[1]["cout"]):
        lignes.append("  %-14s %8.0f $ (%2.0f %%)  %5d tours  %.2f $/tour"
                      % (nom, f["cout"], 100 * f["cout"] / t, f["tours"],
                         f["cout"] / max(f["tours"], 1)))
    lignes.append("")
    lignes.append("Par jour (30 derniers) :")
    for jour in sorted(r["par_jour"])[-30:]:
        lignes.append("  %s %7.2f $   reveils %3d dont muets %3d"
                      % (jour, r["par_jour"][jour], r["veilles"].get(jour, 0),
                         r["veilles_muettes"].get(jour, 0)))
    return "\n".join(lignes)


def _pm(part, total):
    return int(round(1000.0 * part / total)) if total else 0


def recensement(r, d):
    """Les cles `sc_*`. Tout ce qu'un terme de porte interroge est publie ICI, jamais calcule
    deux fois : une porte qui recalcule ne mesure que sa propre recopie."""
    out = []

    def pub(cle, val):
        out.append("%s=%s" % (cle, val))

    t = r["total"] or 1.0
    pub("sc_sessions_superviseur", r["sessions"])
    pub("sc_jours", r["jours"])
    pub("sc_premier_jour", r["premier"] or "-")
    pub("sc_dernier_jour", r["dernier"] or "-")
    pub("sc_requetes", r["req"])
    pub("sc_cout_total_cents", int(round(r["total"] * 100)))
    pub("sc_cout_jour_cents", int(round(r["cout_jour"] * 100)))
    pub("sc_cout_jour_recent_cents", int(round(r["cout_jour_recent"] * 100)))
    pub("sc_cout_essai_cents", int(round(r["cout_essai_recent"] * 100)))
    pub("sc_essais_recents", r["essais_recents"])
    pub("sc_prefixe_median_k", int(r["prefixe_median"] / 1000))
    pub("sc_prefixe_median_recent_k", int(r["prefixe_median_recent"] / 1000))
    pub("sc_part_lecture_pm", _pm(r["lecture"], t))
    pub("sc_part_ecriture_pm", _pm(r["ecriture"], t))
    pub("sc_part_sortie_pm", _pm(r["sortie"], t))
    pub("sc_part_entree_pm", _pm(r["entree"], t))
    for nom in FAMILLES:
        f = r["familles"].get(nom) or {"cout": 0.0, "tours": 0, "req": 0}
        pub("sc_famille_%s_pm" % nom.replace("-", "_"), _pm(f["cout"], t))
        pub("sc_famille_%s_tours" % nom.replace("-", "_"), f["tours"])
        pub("sc_famille_%s_cents" % nom.replace("-", "_"), int(round(f["cout"] * 100)))
    veilles = sum(r["veilles"].values())
    muettes = sum(r["veilles_muettes"].values())
    fv = r["familles"].get("veille") or {"cout": 0.0, "tours": 0}
    pub("sc_veilles", veilles)
    pub("sc_veilles_muettes", muettes)
    pub("sc_veilles_par_jour_x10", int(round(10.0 * veilles / max(r["jours"], 1))))
    pub("sc_veille_cout_moyen_cents", int(round(100.0 * fv["cout"] / max(fv["tours"], 1))))
    pub("sc_reveils_programmes", r["reveils_programmes"])
    pub("sc_rid_ecart_max", r["rid_ecart_max"])
    pub("sc_modeles_inconnus", r["modeles_inconnus"])
    pub("sc_jetons_non_tarifes", r["jetons_non_tarifes"])
    pub("sc_ecriture_sans_ttl", r["ecriture_sans_ttl"])
    # Les autres roles : le denominateur qui empeche de reprendre « le dossier entier » pour
    # « le superviseur », faute qui a fait annoncer 11 000 $.
    for role in ("essai", "lot-images", "atelier", "inconnu"):
        ag = agreger(d, role)
        pub("sc_role_%s_sessions" % role.replace("-", "_"), ag["sessions"])
        pub("sc_role_%s_cents" % role.replace("-", "_"),
            int(round(100 * sum(j["cout"] for j in ag["jours"].values()))))
    pub("sc_cache_ms", d.get("ms", -1))
    pub("sc_cache_octets", d.get("octets_lus", -1))
    pub("sc_cache_sautes", d.get("sautes", -1))
    # --------------------------------------------------------- la population « APRES »
    lanc = [x for x in lancements_armes() if x.get("autocompact")]
    pub("sc_lancements_armes", len(lanc))
    depuis = min((x.get("date") or "" for x in lanc), default="")
    pub("sc_arme_depuis", depuis or "-")
    apres = [x for x in sorted(r["par_jour"]) if depuis and x >= depuis]
    pub("sc_apres_jours", len(apres))
    if len(apres) >= 3:
        hist = {}
        for x in apres:
            _ajoute_hist(hist, r["jours_detail"][x]["hist"])
        med = _mediane_hist(hist)
        avant = r["prefixe_median"]
        pub("sc_apres_mesurable", 1)
        pub("sc_apres_prefixe_median_k", int(med / 1000))
        pub("sc_apres_cout_jour_cents",
            int(round(100 * sum(r["par_jour"][x] for x in apres) / len(apres))))
        pub("sc_baisse_prefixe_pm", _pm(avant - med, avant) if avant else 0)
    else:
        pub("sc_apres_mesurable", 0)
        pub("sc_apres_prefixe_median_k", -1)
        pub("sc_apres_cout_jour_cents", -1)
        pub("sc_baisse_prefixe_pm", -1)
    return "\n".join(out)


def instantane(r):
    return {"genere": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "total_usd": round(r["total"], 2),
            "jours": r["jours"],
            "cout_jour_usd": round(r["cout_jour"], 2),
            "cout_jour_recent_usd": round(r["cout_jour_recent"], 2),
            "cout_essai_usd": round(r["cout_essai_recent"], 2),
            "prefixe_median_jetons": r["prefixe_median"],
            "familles": {k: round(v["cout"], 2) for k, v in r["familles"].items()},
            "par_jour_usd": {k: round(v, 2) for k, v in r["par_jour"].items()},
            "veilles_par_jour": r["veilles"]}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--rafraichir", action="store_true", help="relire les octets neufs")
    p.add_argument("--tout", action="store_true", help="tous les roles, pas que le superviseur")
    p.add_argument("--budget-octets", type=int, default=None,
                   help="au-dela, un fichier est saute (chemin economique du digest)")
    p.add_argument("--bloc", action="store_true", help="le bloc court pour l'owner")
    p.add_argument("--detail", action="store_true", help="le releve complet")
    p.add_argument("--recensement", action="store_true", help="les cles sc_* de la porte")
    p.add_argument("--json", action="store_true", help="ecrire l'instantane machine")
    a = p.parse_args(argv)
    if a.rafraichir:
        d = rafraichir(roles=None if a.tout else ("superviseur", "inconnu", ""),
                       budget_octets=a.budget_octets)
    else:
        d = charger_cache()
    r = releve(d)
    if a.json:
        tmp = SNAPSHOT + ".%d.tmp" % os.getpid()
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(instantane(r), fh, indent=1)
        os.replace(tmp, SNAPSHOT)
    if a.recensement:
        print(recensement(r, d))
    if a.bloc:
        print(bloc_owner(r))
    if a.detail or not (a.recensement or a.bloc or a.json):
        print(texte_detail(r))
    return 0


if __name__ == "__main__":
    sys.exit(main())
