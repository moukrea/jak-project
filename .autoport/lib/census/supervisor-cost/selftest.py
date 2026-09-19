#!/usr/bin/env python3
"""LE BANC de l'item `harness-supervisor-cost-counter`.

Il ne LIT rien du passe : il FAIT TOURNER les pieces livrees sur des entrees dont il connait
la reponse, et sur les fichiers reellement livres dans l'arbre.

  1. LE COMPTEUR MESURE JUSTE. Une transcription FABRIQUEE, dont le cout est calcule a la
     main ici (145 cents, arithmetique ecrite en toutes lettres plus bas), passee au moteur.
     Si les tarifs bougent, ce nombre rougit : un changement de tarif doit etre DELIBERE.
  2. LE DEDOUBLONNAGE N'EST PAS DECORATIF. La meme transcription, lue sans lui, coute
     250 cents au lieu de 145 : le banc mesure l'ECART, il ne se contente pas d'un vert.
  3. L'INCREMENTAL DONNE LE MEME CHIFFRE QUE LA PASSE UNIQUE. Le fichier est lu en deux
     morceaux, avec une coupure AU MILIEU D'UNE LIGNE, et le total doit tomber au cent pres
     sur celui d'une lecture d'un seul tenant. C'est le seul defaut qui ne se verrait jamais
     a l'oeil : un compteur qui saute 3 % des octets reste vraisemblable.
  4. LA VEILLE DECIDE JUSTE, SUR DE VRAIES CHARGES UTILES. Douze prompts reels — les quatre
     libelles qu'a pris le cron en trois mois, plus des prompts qui ne doivent JAMAIS etre
     refuses (essai, owner, fin de tache) — dans les deux bras : etat inchange (refus) et
     etat change (passage). Plus l'echeance, plus l'echec OUVERT.
  5. LA VEILLE NE VOLE PAS LA NOTIFICATION DU SUPERVISEUR. `status --changed` a un memo que
     le PREMIER lecteur consomme. Le banc lit ce memo avant et apres : il doit etre INTACT.
  6. LE LEVIER EST ARME, ET LE BRAS D'AVANT NE L'EST PAS. Le lanceur passe `--autocompact`
     avec une valeur que le binaire Claude Code ACCEPTE (verifie en le lancant), le crochet
     est declare dans le `.claude/settings.json` SUIVI PAR GIT, et le fichier au commit
     precedent ne porte ni l'un ni l'autre.

Sortie : des lignes `banc_<cle>=<valeur>`, lues par `lib/census/harness-supervisor-cost-counter.sh`.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

ICI = os.path.dirname(os.path.abspath(__file__))
AP = os.path.dirname(os.path.dirname(os.path.dirname(ICI)))
ROOT = os.path.dirname(AP)
sys.path.insert(0, AP)

PUB = []


def pub(cle, val):
    if val is None or val == "":
        val = "-"
    PUB.append("banc_%s=%s" % (cle, str(val).replace(" ", "_")))


def panne(quoi):
    pub("panne", quoi)
    print("\n".join(PUB))
    sys.exit(0)


# ------------------------------------------------------------------ 1. LA TRANSCRIPTION
# LE COUT ATTENDU, CALCULE A LA MAIN (tarifs Anthropic du 2026-09-19, $/Mjeton) :
#   opus-5 : entree 5, ecriture 5 min 6,25, ecriture 1 h 10, lecture 0,5, sortie 25
#   fable-5-1 : lecture 0,25, sortie 50
#   A1 owner   1000*5    + 100000*10  + 2000*25            = 1 055 000 -> 1,055 $
#   A1' copie adjacente du MEME requestId                   =         0
#   A3 owner   8000*6,25 + 100000*0,5 + 500*25             =   112 500 -> 0,1125 $
#   A4 veille muette     200000*0,5   + 100*25             =   102 500 -> 0,1025 $
#   A5 veille parlante (fable) 400000*0,25 + 1000*50       =   150 000 -> 0,15 $
#   A6 fin de tache       50000*0,5  + 200*25              =    30 000 -> 0,03 $
#                                                    TOTAL   1 450 000 -> 1,45 $ = 145 cents
COUT_ATTENDU_CENTS = 145
COUT_SANS_DEDOUBLONNAGE_CENTS = 250          # 145 + 105 (la copie de A1)
# Prefixes (entree + ecriture + lecture) : 101 000, 108 000, 200 000, 400 000, 50 000
# -> mediane 108 000 -> casier 4 sur 25 000 -> 112 k publies
PREFIXE_MEDIAN_ATTENDU_K = 112
JOUR = "2026-09-18"


def _usage(entree=0, ecr5=0, ecr1h=0, lecture=0, sortie=0):
    return {"input_tokens": entree, "cache_creation_input_tokens": ecr5 + ecr1h,
            "cache_creation": {"ephemeral_5m_input_tokens": ecr5,
                               "ephemeral_1h_input_tokens": ecr1h},
            "cache_read_input_tokens": lecture, "output_tokens": sortie}


def _assistant(rid, modele, usage, texte="", heure="10:00:00", side=False):
    return {"type": "assistant", "requestId": rid, "isSidechain": side,
            "timestamp": "%sT%s.000Z" % (JOUR, heure),
            "message": {"model": modele, "id": "msg_" + rid, "role": "assistant",
                        "usage": usage,
                        "content": ([{"type": "text", "text": texte}] if texte else
                                    [{"type": "tool_use", "id": "t1", "name": "Bash",
                                      "input": {}}])}}


def _user(texte, heure, meta=False, source="typed"):
    o = {"type": "user", "isSidechain": False, "promptId": "p" + heure,
         "timestamp": "%sT%s.000Z" % (JOUR, heure),
         "message": {"role": "user", "content": texte}}
    if meta:
        o["isMeta"] = True
    if source:
        o["promptSource"] = source
    return o


def transcription_superviseur():
    long_texte = "Voici le point pour l'owner, en francais, avec assez de caracteres."
    return [
        {"type": "system", "subtype": "scheduled_task_fire", "cron": "13,43 * * * *",
         "timestamp": "%sT09:59:00.000Z" % JOUR, "taskId": "abc"},
        _user("Ou en est le portage ? Donne-moi l'etat du harnais.", "10:00:00"),
        _assistant("req-A1", "claude-opus-5", _usage(entree=1000, ecr1h=100000, sortie=2000),
                   texte=long_texte),
        _assistant("req-A1", "claude-opus-5", _usage(entree=1000, ecr1h=100000, sortie=2000),
                   texte=""),                    # meme requestId : copie adjacente
        _assistant("req-A3", "claude-opus-5", _usage(ecr5=8000, lecture=100000, sortie=500),
                   texte=long_texte, heure="10:01:00"),
        _user("Supervision autoport. Fais les verifications de sante SILENCIEUSEMENT puis "
              "lance ./.autoport/autoport status --changed ; s'il ne sort rien, ne reponds "
              "rien et ne consomme pas de tour.", "10:30:00", meta=True, source="system"),
        _assistant("req-A4", "claude-opus-5", _usage(lecture=200000, sortie=100),
                   texte="", heure="10:30:10"),   # aucun texte rendu -> reveil MUET
        _user("Auto progress check (30-min owner update) — monitor the autoport orchestrator "
              "and report a quick digest to the owner.", "11:00:00", meta=True,
              source="system"),
        _assistant("req-A5", "claude-fable-5-1", _usage(lecture=400000, sortie=1000),
                   texte=long_texte, heure="11:00:10"),
        _user("<task-notification> <task-id>abc</task-id> l'essai est termine "
              "</task-notification>", "11:30:00", meta=True, source="system"),
        _assistant("req-A6", "claude-opus-5", _usage(lecture=50000, sortie=200),
                   texte=long_texte, heure="11:30:10"),
    ]


def transcription_essai():
    return [
        _user("ultrathink\n\n## DIRECTIVES v0000000000\nVersion courante ... ## CET ESSAI "
              "item : quelque-chose", "12:00:00"),
        _assistant("req-W1", "claude-opus-5", _usage(lecture=10000, sortie=100),
                   texte="ok", heure="12:00:10"),
    ]


def ecris(chemin, lignes, coupure=None):
    """Ecrit les lignes ; si `coupure` est donne, s'arrete au MILIEU de cette ligne-la."""
    texte = "".join(json.dumps(x, separators=(",", ":")) + "\n" for x in lignes)
    if coupure is not None:
        texte = texte[:coupure]
    with open(chemin, "w", encoding="utf-8") as fh:
        fh.write(texte)
    return texte


def mesure(dossier, cache):
    env = dict(os.environ)
    env["AUTOPORT_TRANSCRIPTS"] = dossier
    env["AUTOPORT_COST_CACHE"] = cache
    r = subprocess.run([sys.executable, os.path.join(AP, "lib", "supervisor_cost.py"),
                        "--rafraichir", "--tout", "--recensement"],
                       capture_output=True, text=True, env=env, timeout=120)
    out = {}
    for ligne in (r.stdout or "").splitlines():
        if "=" in ligne:
            k, v = ligne.split("=", 1)
            out[k] = v
    return out, r.returncode


def banc_compteur():
    tmp = tempfile.mkdtemp(prefix="banc-cout-")
    try:
        d = os.path.join(tmp, "transcripts")
        os.makedirs(d)
        sup = os.path.join(d, "aaaa-superviseur.jsonl")
        texte = ecris(sup, transcription_superviseur())
        ecris(os.path.join(d, "bbbb-essai.jsonl"), transcription_essai())
        un_coup, rc = mesure(d, os.path.join(tmp, "c1.json"))
        pub("compteur_rc", rc)
        pub("cout_cents", un_coup.get("sc_cout_total_cents"))
        pub("cout_attendu_cents", COUT_ATTENDU_CENTS)
        pub("cout_sans_dedoublonnage_cents", COUT_SANS_DEDOUBLONNAGE_CENTS)
        pub("prefixe_median_k", un_coup.get("sc_prefixe_median_k"))
        pub("prefixe_median_attendu_k", PREFIXE_MEDIAN_ATTENDU_K)
        pub("veilles", un_coup.get("sc_veilles"))
        pub("veilles_muettes", un_coup.get("sc_veilles_muettes"))
        pub("famille_veille_cents", un_coup.get("sc_famille_veille_cents"))
        pub("famille_owner_cents", un_coup.get("sc_famille_owner_cents"))
        pub("famille_tache_cents", un_coup.get("sc_famille_fin_de_tache_cents"))
        pub("role_essai_sessions", un_coup.get("sc_role_essai_sessions"))
        pub("sessions_superviseur", un_coup.get("sc_sessions_superviseur"))
        pub("rid_ecart_max", un_coup.get("sc_rid_ecart_max"))
        pub("jetons_non_tarifes", un_coup.get("sc_jetons_non_tarifes"))

        # --- l'incremental, avec une coupure AU MILIEU D'UNE LIGNE
        d2 = os.path.join(tmp, "incremental")
        os.makedirs(d2)
        sup2 = os.path.join(d2, "aaaa-superviseur.jsonl")
        milieu = int(len(texte) * 0.55)
        while milieu < len(texte) and texte[milieu] == "\n":
            milieu += 1
        with open(sup2, "w", encoding="utf-8") as fh:
            fh.write(texte[:milieu])
        shutil.copy(os.path.join(d, "bbbb-essai.jsonl"), d2)
        cache2 = os.path.join(tmp, "c2.json")
        moitie, _ = mesure(d2, cache2)
        pub("incremental_moitie_cents", moitie.get("sc_cout_total_cents"))
        with open(sup2, "a", encoding="utf-8") as fh:
            fh.write(texte[milieu:])
        deux_temps, _ = mesure(d2, cache2)
        pub("incremental_cents", deux_temps.get("sc_cout_total_cents"))
        pub("incremental_veilles", deux_temps.get("sc_veilles"))
        pub("incremental_octets", json.load(open(cache2, encoding="utf-8")).get("octets_lus"))
        pub("coupure_octets", milieu)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ------------------------------------------------------------------ 2. LA VEILLE
# LES CHARGES UTILES SONT REELLES, pas inventees : `charges.json` recopie les prompts que le
# cron a reellement injectes dans la session du superviseur (ses quatre libelles successifs)
# et des messages que l'owner a reellement tapes — dont quatre qui PARLENT du harnais, de la
# supervision et du digest, c'est-a-dire exactement ceux qu'un detecteur trop large effacerait.
CHARGES = json.load(open(os.path.join(ICI, "charges.json"), encoding="utf-8"))
CHARGES_VEILLE = CHARGES["veilles"]
CHARGES_JAMAIS = CHARGES["jamais"]


def banc_veille():
    import importlib
    wake = importlib.import_module("lib.wake_gate")
    memo_tmp = os.path.join(tempfile.mkdtemp(prefix="banc-veille-"), "memo.json")
    wake.MEMO = memo_tmp
    wake.JOURNAL = os.path.join(os.path.dirname(memo_tmp), "journal.jsonl")

    pub("veille_charges", len(CHARGES_VEILLE))
    pub("veille_charges_jamais", len(CHARGES_JAMAIS))
    pub("veille_reconnues", sum(1 for c in CHARGES_VEILLE if wake.est_un_reveil(c)))
    pub("veille_faux_positifs", sum(1 for c in CHARGES_JAMAIS if wake.est_un_reveil(c)))

    # LE MEMO DU SUPERVISEUR NE DOIT PAS BOUGER : la veille ne consomme pas sa notification.
    memo_digest = os.path.join(AP, ".last_status_digest")
    avant = ""
    try:
        with open(memo_digest, encoding="utf-8") as fh:
            avant = fh.read().strip()
    except OSError:
        pass

    t0 = time.time()
    d1 = wake.decide(CHARGES_VEILLE[0])                     # premier passage : laisse passer
    ms1 = int((time.time() - t0) * 1000)
    refus = 0
    ms_max = 0
    for charge in CHARGES_VEILLE:
        t = time.time()
        d = wake.decide(charge)
        ms_max = max(ms_max, int((time.time() - t) * 1000))
        if d[0] == "refuse":
            refus += 1
    pub("veille_premier_passage", d1[0])
    pub("veille_premier_raison", d1[1])
    pub("veille_premier_contexte_octets", len(d1[2]))
    pub("veille_refus_sur_etat_inchange", refus)
    pub("veille_ms_max", max(ms_max, ms1))

    # LE BRAS « QUELQUE CHOSE A BOUGE » : on change la signature memorisee, le reveil passe.
    memo = json.load(open(memo_tmp, encoding="utf-8"))
    memo["signature"] = "0" * 64
    json.dump(memo, open(memo_tmp, "w", encoding="utf-8"))
    d = wake.decide(CHARGES_VEILLE[0])
    pub("veille_etat_change", d[0])
    pub("veille_etat_change_raison", d[1])
    pub("veille_etat_change_contexte_octets", len(d[2]))

    # L'ECHEANCE : meme signature, mais le plancher est ecoule -> on reveille quand meme.
    memo = json.load(open(memo_tmp, encoding="utf-8"))
    memo["dernier_reveil"] = time.time() - (wake.PLANCHER_S + 60)
    json.dump(memo, open(memo_tmp, "w", encoding="utf-8"))
    d = wake.decide(CHARGES_VEILLE[0])
    pub("veille_echeance", d[0])
    pub("veille_echeance_raison", d[1])

    # LES PROMPTS QUI NE DOIVENT JAMAIS ETRE REFUSES, passes a la DECISION (pas au detecteur).
    jamais_refuses = 0
    for charge in CHARGES_JAMAIS:
        if wake.decide(charge, ecrire=False)[0] == "refuse":
            jamais_refuses += 1
    pub("veille_refus_interdits", jamais_refuses)

    # L'ECHEC OUVERT : un backlog illisible ne doit PAS faire taire le superviseur.
    vrai = wake.signature

    def casse(_bk):
        raise RuntimeError("backlog illisible")
    wake.signature = casse
    try:
        d = wake.decide(CHARGES_VEILLE[0], ecrire=False)
    finally:
        wake.signature = vrai
    pub("veille_echec_ouvert", d[0])
    pub("veille_echec_ouvert_raison", d[1])

    # LE CROCHET LUI-MEME, lance comme Claude Code le lancera : code 2 = refus.
    env = dict(os.environ)
    charge = json.dumps({"prompt": CHARGES_VEILLE[0], "session_id": "x", "cwd": ROOT,
                         "hook_event_name": "UserPromptSubmit"})
    r = subprocess.run(["bash", os.path.join(AP, "hooks", "user-prompt.sh")],
                       input=charge, capture_output=True, text=True, env=env, timeout=60)
    pub("crochet_rc", r.returncode)
    pub("crochet_sortie_octets", len(r.stdout))
    r2 = subprocess.run(["bash", os.path.join(AP, "hooks", "user-prompt.sh")],
                        input=json.dumps({"prompt": "ca en est ou ?"}),
                        capture_output=True, text=True, env=env, timeout=60)
    pub("crochet_owner_rc", r2.returncode)
    pub("crochet_owner_sortie_octets", len(r2.stdout))

    apres = ""
    try:
        with open(memo_digest, encoding="utf-8") as fh:
            apres = fh.read().strip()
    except OSError:
        pass
    pub("memo_digest_intact", 1 if avant == apres else 0)
    shutil.rmtree(os.path.dirname(memo_tmp), ignore_errors=True)


# ------------------------------------------------------------------ 3. LE LEVIER ARME
def _git(*args):
    try:
        r = subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True, text=True,
                           timeout=30)
        return r.stdout if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def banc_population_reelle():
    """LE DETECTEUR, JUGE SUR LA VRAIE POPULATION. Un detecteur qui refuse un message de
    l'owner l'EFFACE : c'est le seul defaut inacceptable de cette veille. On le fait donc
    tourner sur tous les prompts reellement tapes par l'owner dans la session du superviseur,
    et sur tous les prompts injectes. La transcription n'est pas du code livre : si elle
    manque, les deux populations sont publiees a -1, et la porte le lit."""
    import importlib
    wake = importlib.import_module("lib.wake_gate")
    try:
        from lib import supervisor_cost as sc                # noqa: PLC0415
        dossier = sc.dossier_transcriptions()
        cache = sc.charger_cache()
        fichiers = [n for n, e in (cache.get("fichiers") or {}).items()
                    if e.get("role") == "superviseur"]
    except Exception:                                        # noqa: BLE001
        fichiers = []
    if not fichiers:
        pub("population_owner", -1)
        pub("population_injectes", -1)
        pub("population_faux_positifs", -1)
        pub("population_reveils_detectes", -1)
        return
    owner = injecte = detectes = faux = 0
    for nom in fichiers:
        try:
            fh = open(os.path.join(dossier, nom), encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for ligne in fh:
                if '"user"' not in ligne:
                    continue
                try:
                    o = json.loads(ligne)
                except Exception:                            # noqa: BLE001
                    continue
                if o.get("type") != "user" or o.get("isSidechain"):
                    continue
                c = (o.get("message") or {}).get("content")
                if not isinstance(c, str) or not c.strip():
                    continue
                vu = wake.est_un_reveil(c)
                if o.get("isMeta"):
                    injecte += 1
                    detectes += 1 if vu else 0
                else:
                    owner += 1
                    faux += 1 if vu else 0
    pub("population_owner", owner)
    pub("population_injectes", injecte)
    pub("population_faux_positifs", faux)
    pub("population_reveils_detectes", detectes)


def banc_levier():
    lanceur = os.path.join(AP, "supervisor.sh")
    with open(lanceur, encoding="utf-8") as fh:
        txt = fh.read()
    val = ""
    for ligne in txt.splitlines():
        if "AUTOPORT_SUPERVISOR_AUTOCOMPACT" in ligne and ":-" in ligne:
            val = ligne.split(":-", 1)[1].split("}", 1)[0].strip().strip('"')
    pub("lanceur_autocompact", val or "-")
    pub("lanceur_autocompact_dans_exec", 1 if "--autocompact" in txt else 0)
    pub("lanceur_journal", 1 if "supervisor-launches.jsonl" in txt else 0)
    # `[1m]` ne doit plus etre pose par le lanceur : c'est lui qui supprimait la compaction.
    # `[1m]` ne doit plus etre POSE par le lanceur. On ne compte que les lignes de code qui
    # l'AFFECTENT : le retrait (`${SUP_MODEL%[1m]}`) et les commentaires qui l'expliquent le
    # citent forcement, et les compter ferait rougir le correctif lui-meme.
    pose = 0
    for ligne in txt.splitlines():
        nu = ligne.strip()
        if nu.startswith("#") or "%\\[1m\\]" in nu or "%[1m]" in nu:
            continue
        if "[1m]" in nu and ("=" in nu or "exec" in nu):
            pose += 1
    pub("lanceur_pose_1m", pose)

    # LA VALEUR EST-ELLE ACCEPTEE PAR LE BINAIRE ? On le LANCE — sans ouvrir de session.
    def essai_cli(v):
        try:
            r = subprocess.run(["claude", "--autocompact", v, "--version"],
                               capture_output=True, text=True, timeout=60)
            return r.returncode
        except (OSError, subprocess.SubprocessError):
            return -1
    pub("cli_accepte_valeur", essai_cli(val or "150000"))
    pub("cli_refuse_absurde", essai_cli("42"))

    # LE BRAS D'AVANT : le lanceur au commit PRECEDENT ne porte pas le marqueur. On ancre sur
    # le marqueur, pas sur HEAD : lu a `HEAD:`, le temoin s'accuserait lui-meme des le commit.
    ancre = ""
    for c in (_git("log", "--format=%H", "-n", "40", "--", ".autoport/supervisor.sh")
              .split()):
        avant = _git("show", "%s:.autoport/supervisor.sh" % c)
        if avant and "--autocompact" not in avant:
            ancre = c
            pub("avant_commit", c[:10])
            pub("avant_octets", len(avant))
            pub("avant_porte_le_marqueur", 1 if "--autocompact" in avant else 0)
            break
    if not ancre:
        pub("avant_commit", "-")
        pub("avant_octets", 0)
        pub("avant_porte_le_marqueur", -1)

    # LE CROCHET EST DECLARE DANS LE FICHIER SUIVI PAR GIT, pas seulement en local.
    suivi = ".claude/settings.json" in (_git("ls-files", ".claude/settings.json") or "")
    pub("settings_suivi_par_git", 1 if suivi else 0)
    declare = 0
    try:
        with open(os.path.join(ROOT, ".claude", "settings.json"), encoding="utf-8") as fh:
            reglages = json.load(fh)
        for groupe in (reglages.get("hooks") or {}).get("UserPromptSubmit") or []:
            for h in groupe.get("hooks") or []:
                if "user-prompt.sh" in (h.get("command") or ""):
                    declare = 1
    except Exception:                                      # noqa: BLE001
        declare = -1
    pub("crochet_declare", declare)

    # LE COMPTEUR EST BIEN DANS CE QUE LIT LE DIGEST : on APPELLE le renderer, on ne grep pas
    # le fichier qui le contient.
    try:
        from lib import backlog                            # noqa: PLC0415
        bk = backlog.load()
        texte = bk.status_report()
        pub("status_porte_le_cout", 1 if "## Ce que le superviseur coute" in texte else 0)
        sig1 = bk.signature_digest()
        sig2 = bk.signature_digest()
        pub("signature_stable", 1 if sig1 == sig2 else 0)
        pub("signature_octets", len(sig1))
    except Exception as exc:                               # noqa: BLE001
        pub("status_porte_le_cout", -1)
        pub("signature_stable", -1)
        pub("status_erreur", type(exc).__name__)


def main():
    pub("ran", 1)
    # PUBLIEE MEME QUAND TOUT VA BIEN : une cle absente et une cle a « rien » se ressemblent
    # trop, et la porte compterait une cecite la ou il n'y a qu'un succes. `panne()` republie
    # la meme cle en cas d'echec ; le moissonneur garde la DERNIERE.
    pub("panne", "-")
    try:
        banc_compteur()
        banc_veille()
        banc_population_reelle()
        banc_levier()
    except Exception as exc:                               # noqa: BLE001
        panne("%s:%s" % (type(exc).__name__, str(exc)[:60]))
    print("\n".join(PUB))
    return 0


if __name__ == "__main__":
    sys.exit(main())
