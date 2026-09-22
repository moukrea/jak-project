#!/usr/bin/env bash
# census/harness-supervisor-death-is-an-alarm.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course.
# Il ne peut ecrire aucun champ que la machine produit (`sha`, `frames`, `crash`).
#
# CE QU'IL MESURE — quatre termes, un par point du livrable :
#   1. le COUT D'AVANT, chiffre sur 7 jours de vrais retours    -> osla_cost_before
#   2. le LECTEUR, mesure — et mesure MIEUX que `kill -0`       -> osla_reader_probe
#   3. la MORT EST UNE ALERTE : elle sort, elle ne se repete pas -> osla_alarm_fires
#   4. le FICHIER DE TERMINAL NE MENT PLUS                      -> osla_terminal_truth
#
# INCONNU = DEFAUT. Un terme qu'on n'a pas su mesurer compte pour un, jamais pour zero : une
# porte `== 0` sur une alarme serait sinon verte par INACTION — reseau coupe, aucun defaut vu.
# `orphan_owner_feedback_terms_measured` dit combien de termes ont VRAIMENT ete mesures : le
# lire AVANT la somme (feedback_aggregate_gate_scoring_unmeasured_terms_as_one_hides_blindness).
#
# RIEN ICI N'ECRIT DANS L'ETAT DU HARNAIS QUI TOURNE. Les termes 2, 3 et 4 SEMENT leurs
# populations dans un repertoire jetable et les font lire par le code LIVRE via les surcharges
# de chemin (`AUTOPORT_SUPERVISOR_TERMINAL`, `AUTOPORT_OWNER_SLA_CACHE`, ...). Poser un faux
# `.supervisor-terminal.json` le temps d'une mesure ferait refuser le prochain
# `run-supervisor.sh` : on ne mesure jamais en deplacant ce qu'on mesure.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "orphan_owner_feedback_defects=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import json, os, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.abspath(".autoport"))
sys.path.insert(0, os.path.abspath(".autoport/lib"))

OUT, ORDRE = {}, []
def pub(k, v):
    if k not in OUT:
        ORDRE.append(k)
    OUT[k] = v

defects = 0
measured = 0
TMP = tempfile.mkdtemp(prefix="osla-census-")

import owner_sla as O
import supervisor_alive as SA

SLA = O.sla_seconds()
pub("osla_sla_s", SLA)
pub("osla_stale_s", SA.stale_seconds())

# =============================================== T2 : LE LECTEUR, MESURE — ET MIEUX QUE kill -0
# Mesure en premier : c'est le terme qui ne depend ni du reseau ni d'un secret, donc le seul
# qui reste parlant quand tout le reste est hors d'atteinte.
#
# Population SEMEE, avec des cas a REFUSER et des cas a LAISSER PASSER. Le bras CONDAMNE
# (`kill -0`, ce que faisait tout le depot) est rejoue sur la MEME population : s'il ne se
# trompe sur RIEN, la population ne separe pas les deux regles et le terme compte un defaut
# (feedback_ablation_vacuous_when_condition_absent).
try:
    # un ZOMBIE reel : l'enfant sort, le pere ne le moissonne pas. `kill -0` lui repond OUI.
    zpid = os.fork()
    if zpid == 0:
        os._exit(0)
    time.sleep(0.2)
    vivant = subprocess.Popen(["sleep", "120"])
    time.sleep(0.2)
    st_v = SA.read_proc_stat(vivant.pid)
    st_z = SA.read_proc_stat(zpid)
    seen = os.path.join(TMP, "seen.json")
    SA.stamp_seen(seen)
    t0 = time.time()

    CAS = [
        # (nom, record, now, attendu_vivant)
        ("fichier-absent",   None,                                                    t0, False),
        ("pid-mort-68980",   {"pid": 68980, "start": "123456", "tty": "/dev/pts/3"},   t0, False),
        ("zombie",           {"pid": zpid, "start": str(st_z["starttime"]) if st_z else "0",
                              "tty": "-"},                                             t0, False),
        ("pid-recycle",      {"pid": vivant.pid, "start": str(st_v["starttime"] + 1),
                              "tty": "-"},                                             t0, False),
        ("vivant",           {"pid": vivant.pid, "start": str(st_v["starttime"]),
                              "tty": "-"},                                             t0, True),
        ("gele-3h",          {"pid": vivant.pid, "start": str(st_v["starttime"]),
                              "tty": "-"},                             t0 + 3 * 3600,  False),
    ]
    faux_livre = faux_kill0 = 0
    detail = []
    for nom, rec, quand, attendu in CAS:
        if rec is None:
            r = SA.probe(state_file=os.path.join(TMP, "pas-de-fichier.json"),
                         now=quand, seen_file=seen)
        else:
            r = SA.probe(record=rec, now=quand, seen_file=seen)
        if bool(r["alive"]) != attendu:
            faux_livre += 1
        # LE BRAS CONDAMNE : « le pid repond a kill -0 » — zombie compris, recyclage compris,
        # gel compris.
        k0 = False
        if rec is not None:
            try:
                os.kill(int(rec["pid"]), 0)
                k0 = True
            except OSError:
                k0 = False
        if k0 != attendu:
            faux_kill0 += 1
        detail.append("%s:%s/%s" % (nom, r["why"], "k0oui" if k0 else "k0non"))

    # L'ASCENDANCE : le tampon « il a repondu » ne doit etre pose QUE par une session qui
    # descend du superviseur declare. Trois cas, dont deux a refuser.
    moi = SA.read_proc_stat(os.getpid())
    ASC = [
        ("mon-propre-arbre", {"pid": os.getpid(), "start": str(moi["starttime"]), "tty": "-"}, True),
        ("superviseur-mort", {"pid": 68980, "start": "1", "tty": "-"}, False),
        ("processus-etranger", {"pid": vivant.pid, "start": str(st_v["starttime"]), "tty": "-"}, False),
    ]
    faux_asc = 0
    for nom, rec, attendu in ASC:
        if SA.in_supervisor_tree(record=rec) != attendu:
            faux_asc += 1
        detail.append("asc-%s:%s" % (nom, "ok" if SA.in_supervisor_tree(record=rec) == attendu else "FAUX"))
    pub("osla_ancestry_cases", len(ASC))
    pub("osla_ancestry_wrong", faux_asc)
    faux_livre += faux_asc

    pub("osla_probe_cases", len(CAS))
    pub("osla_probe_wrong_now", faux_livre)
    pub("osla_probe_wrong_kill0", faux_kill0)
    pub("osla_probe_detail", ",".join(detail))
    measured += 1
    bad = 1 if (faux_livre != 0 or faux_kill0 == 0) else 0
    pub("osla_reader_probe", bad)
    defects += bad

    vivant.terminate()
    try:
        vivant.wait(timeout=5)
    except Exception:  # noqa: BLE001
        vivant.kill()
    try:
        os.waitpid(zpid, 0)
    except OSError:
        pass
except Exception as e:  # noqa: BLE001
    pub("osla_probe_error", str(e)[:120].replace(" ", "_"))
    pub("osla_reader_probe", 1)
    defects += 1

# ============================================== T4 : LE FICHIER DE TERMINAL NE MENT PLUS =====
# Le releve du 22/09, REJOUE : pid 68980 mort, tty /dev/pts/3 tenu par un `codex --yolo resume`
# depuis quatre jours. Le fichier lui-meme est gitignore et il a disparu depuis ; c'est le
# releve qui est rejoue, pas le fichier — un test qui EXIGE un fichier gitignore accuse un
# innocent des qu'on change d'arbre (feedback_test_reading_a_gitignored_file...).
try:
    R2209 = {"pid": 68980, "start": "1234567", "tty": "/dev/pts/3"}
    r = SA.probe(record=R2209, now=time.time())
    pub("osla_2209_declared", r["declared"])
    pub("osla_2209_alive", 1 if r["alive"] else 0)
    pub("osla_2209_why", r["why"])
    pub("osla_2209_tty", r["tty"])
    pub("osla_2209_tty_holder", r["tty_holder"])

    # ET LE LANCEUR LIVRE DOIT EN TIRER LA MEME CONCLUSION : « pas de superviseur », pas
    # « superviseur declare ». C'est lui qui refusait de demarrer en accusant un mort.
    ok_lanceur, rel_lanceur = SA.process_alive(record=R2209)
    pub("osla_2209_launcher_sees_alive", 1 if ok_lanceur else 0)

    # Un tty qui a change de main sous un pid VIVANT : le releve doit le DIRE.
    men = subprocess.Popen(["sleep", "120"])
    time.sleep(0.2)
    stm = SA.read_proc_stat(men.pid)
    rm = SA.probe(record={"pid": men.pid, "start": str(stm["starttime"]),
                          "tty": "/dev/pts/99"}, now=time.time())
    pub("osla_tty_mismatch_seen", 0 if rm["tty_matches_pid"] else 1)
    men.terminate()
    try:
        men.wait(timeout=5)
    except Exception:  # noqa: BLE001
        men.kill()

    # Le fichier REEL, tel qu'il est a l'instant de la course. Observation publiee, jamais une
    # condition de la porte : sur un arbre neuf il est absent, et c'est un etat legitime.
    live = SA.probe()
    pub("osla_terminal_present", 1 if os.path.exists(SA.state_file_path()) else 0)
    pub("osla_live_why", live["why"])
    pub("osla_live_alive", 1 if live["alive"] else 0)
    pub("osla_live_last_response_ts", live["last_response_ts"])
    pub("osla_live_last_response_src", live["last_response_src"])
    pub("osla_live_since_last_response_s", live["since_last_response_s"])

    measured += 1
    bad = 0 if (r["declared"] == 1 and not r["alive"] and r["why"] == SA.PID_MORT
                and not ok_lanceur and not rm["tty_matches_pid"]) else 1
    pub("osla_terminal_truth", bad)
    defects += bad
except Exception as e:  # noqa: BLE001
    pub("osla_terminal_error", str(e)[:120].replace(" ", "_"))
    pub("osla_terminal_truth", 1)
    defects += 1

# ================================== T3 : LA MORT EST UNE ALERTE, PAS UNE LIGNE DE JOURNAL ====
# La porte du contrat, mot pour mot : superviseur mort + retour de 3 h -> la rubrique apparait
# ET le commentaire part ; superviseur vivant -> ni l'un ni l'autre ; deux passages de suite ->
# UN seul commentaire.
# La rubrique est lue sur la VRAIE sortie de `./.autoport/autoport status`, pas sur la fonction
# qui la fabrique : c'est cette sortie-la que l'owner regarde, et c'est elle qui doit changer.
try:
    t0 = int(time.time())
    RETOURS = [
        {"item": "hud-eco-gauge", "ticket": "issue-temoin", "text": "la jauge est toujours pas la",
         "date": "2026-09-22", "key": "temoin:vieux", "ts": t0 - 3 * 3600, "dated": 1,
         "answered_ts": 0, "answered": 0, "delay_s": 3 * 3600, "open": 1},
        # un retour RECENT et un retour DEJA REPONDU : ils ne doivent JAMAIS declencher.
        {"item": "hud-heart", "ticket": "issue-temoin", "text": "tout frais",
         "date": "2026-09-22", "key": "temoin:frais", "ts": t0 - 60, "dated": 1,
         "answered_ts": 0, "answered": 0, "delay_s": 60, "open": 1},
        {"item": "water-ocean-mesh", "ticket": "issue-temoin", "text": "vieux mais repondu",
         "date": "2026-09-21", "key": "temoin:repondu", "ts": t0 - 9 * 3600, "dated": 1,
         "answered_ts": t0 - 8 * 3600, "answered": 1, "delay_s": 3600, "open": 0},
    ]
    MORT = {"alive": False, "why": "pid-mort", "pid": 68980, "tty": "/dev/pts/3",
            "tty_holder": "codex"}
    vivant = subprocess.Popen(["sleep", "120"])
    time.sleep(0.2)
    stv = SA.read_proc_stat(vivant.pid)
    seen2 = os.path.join(TMP, "seen2.json")
    SA.stamp_seen(seen2)
    VIF = SA.probe(record={"pid": vivant.pid, "start": str(stv["starttime"]), "tty": "-"},
                   now=time.time(), seen_file=seen2)

    etat_mort, etat_vif = {}, {}
    postes_mort, postes_vif = [], []
    a1 = O.run(RETOURS, MORT, lambda i, t, b: postes_mort.append(i) or True,
               now=t0, state=etat_mort)
    a2 = O.run(RETOURS, MORT, lambda i, t, b: postes_mort.append(i) or True,
               now=t0 + 1, state=etat_mort)          # DEUXIEME passage, meme etat
    a3 = O.run(RETOURS, VIF, lambda i, t, b: postes_vif.append(i) or True,
               now=t0, state=etat_vif)               # CONTROLE NEGATIF

    pub("osla_alarm_overdue", a1["overdue_n"])
    pub("osla_alarm_posted_pass1", a1["posted"])
    pub("osla_alarm_posted_pass2", a2["posted"])
    pub("osla_alarm_posted_total", len(postes_mort))
    pub("osla_alarm_lines_pass1", len(a1["lines"]))
    pub("osla_alarm_control_raise", 1 if a3["raise"] else 0)
    pub("osla_alarm_control_posted", len(postes_vif))
    pub("osla_alarm_control_why", VIF["why"])

    # ------- LA RUBRIQUE, LUE SUR LA VRAIE SORTIE DU CLI, dans les DEUX regimes -------------
    def status_sous(regime_record, cache_records):
        d = os.path.join(TMP, "regime-%d" % abs(hash(json.dumps(regime_record, sort_keys=True))))
        os.makedirs(d, exist_ok=True)
        term = os.path.join(d, "terminal.json")
        with open(term, "w") as fh:
            json.dump(regime_record, fh)
        cache = os.path.join(d, "cache.json")
        with open(cache, "w") as fh:
            json.dump({"at": int(time.time()), "records": cache_records}, fh)
        env = dict(os.environ)
        env.update({"AUTOPORT_SUPERVISOR_TERMINAL": term,
                    "AUTOPORT_OWNER_SLA_CACHE": cache,
                    "AUTOPORT_OWNER_SLA_STATE": os.path.join(d, "deja.json"),
                    "AUTOPORT_SUPERVISOR_SEEN": os.path.join(d, "seen.json")})
        p = subprocess.run(["./.autoport/autoport", "status"], cwd=os.getcwd(), env=env,
                           capture_output=True, text=True, timeout=300)
        return p.stdout or ""

    vu_mort = status_sous({"pid": 68980, "start": "1234567", "tty": "/dev/pts/3"}, RETOURS)
    vu_vif = status_sous({"pid": vivant.pid, "start": str(stv["starttime"]), "tty": "-"},
                         RETOURS)
    # le regime vivant doit poser un tampon frais, sinon le releve le declare GELE
    tampon = os.path.join(TMP, "regime-%d" % abs(hash(json.dumps(
        {"pid": vivant.pid, "start": str(stv["starttime"]), "tty": "-"}, sort_keys=True))),
        "seen.json")
    SA.stamp_seen(tampon)
    vu_vif = status_sous({"pid": vivant.pid, "start": str(stv["starttime"]), "tty": "-"},
                         RETOURS)

    tete_mort = 1 if vu_mort.lstrip().startswith("!! " + O.RUBRIQUE) else 0
    pub("osla_status_rubric_dead", 1 if O.RUBRIQUE in vu_mort else 0)
    pub("osla_status_rubric_first", tete_mort)
    pub("osla_status_rubric_alive", 1 if O.RUBRIQUE in vu_vif else 0)
    pub("osla_status_dead_bytes", len(vu_mort))
    pub("osla_status_alive_bytes", len(vu_vif))
    # L'ACQUIS VOISIN : le compteur de cout du superviseur sort toujours (item
    # harness-supervisor-cost-counter, valide). La nouvelle rubrique s'AJOUTE en tete, elle ne
    # remplace rien.
    pub("osla_status_cost_block_kept", 1 if "superviseur" in vu_vif.lower() else 0)

    vivant.terminate()
    try:
        vivant.wait(timeout=5)
    except Exception:  # noqa: BLE001
        vivant.kill()

    measured += 1
    bad = 0 if (a1["raise"] and a1["overdue_n"] == 1 and a1["posted"] == 1
                and a2["posted"] == 0 and len(postes_mort) == 1
                and not a3["raise"] and not postes_vif
                and tete_mort == 1 and O.RUBRIQUE not in vu_vif
                and len(vu_vif) > 0) else 1
    pub("osla_alarm_fires", bad)
    defects += bad
except Exception as e:  # noqa: BLE001
    pub("osla_alarm_error", str(e)[:120].replace(" ", "_"))
    pub("osla_alarm_fires", 1)
    defects += 1

# ========================================== T1 : LE COUT D'AVANT, CHIFFRE SUR 7 JOURS ========
# La seule mesure qui touche le reseau. Population = les retours de l'owner que le backlog a
# recopies sur 7 jours ; grandeur = le delai entre l'horodatage LINEAR du retour et le premier
# commentaire du harnais poste APRES lui sur le meme ticket. Sans reponse, le delai reste
# OUVERT : le compter a zero rendrait la moyenne d'autant plus verte que la panne est grave.
# On publie un COMPTE au-dela du seuil et le MAXIMUM, jamais une moyenne
# (feedback_mean_over_a_low_threshold_set_is_self_defeating).
try:
    import datetime
    import yaml
    import linear_identity as LI
    import linear_sync as S

    ident = LI.resolve()
    L = S.Linear(ident)
    mp = json.loads(open(".autoport/linear_map.json").read())
    owner_id = (mp.get("_owner") or {}).get("user_id")
    bl = yaml.safe_load(open(".autoport/backlog.yaml"))
    items = bl["items"] if isinstance(bl, dict) and "items" in bl else bl
    maintenant = time.time()
    depuis = (datetime.date.fromtimestamp(maintenant)
              - datetime.timedelta(days=O.FENETRE_JOURS)).isoformat()
    rows = O.rows_from_backlog(items, mp, since_date=depuis)
    fetch, is_owner, is_harness = O.linear_sources(L, owner_id,
                                                   tickets=[r["ticket"] for r in rows])
    recs = O.collect(rows, fetch, is_owner, is_harness, now=maintenant)
    c = O.cost_summary(recs, SLA, now=maintenant)

    pub("osla_cost_window_days", O.FENETRE_JOURS)
    pub("osla_cost_population", c["population"])
    pub("osla_cost_dated", c["dated"])
    pub("osla_cost_undated", c["undated"])
    pub("osla_cost_answered", c["answered"])
    pub("osla_cost_open", c["open"])
    pub("osla_cost_over_sla", c["over_sla"])
    pub("osla_cost_max_delay_s", c["max_delay_s"])
    pub("osla_cost_worst_item", c["worst_item"])
    pub("osla_cost_tickets", len({r["ticket"] for r in rows if r["ticket"]}))
    measured += 1
    # NON NUL PAR CONSTRUCTION (contrat) : zero retour date, ou zero depassement, signifie que
    # l'instrument n'a rien vu — pas que la file etait servie.
    bad = 0 if (c["dated"] > 0 and c["over_sla"] > 0) else 1
    pub("osla_cost_before", bad)
    defects += bad
except Exception as e:  # noqa: BLE001
    pub("osla_cost_error", str(e)[:140].replace(" ", "_"))
    pub("osla_cost_before", 1)
    defects += 1

pub("orphan_owner_feedback_terms_measured", measured)
pub("orphan_owner_feedback_terms_total", 4)
pub("orphan_owner_feedback_defects", defects + (4 - measured))

for k in ORDRE:
    v = OUT[k]
    v = "-" if v is None or v == "" else str(v).replace(" ", "_")
    print("%s=%s" % (k, v))
PY
