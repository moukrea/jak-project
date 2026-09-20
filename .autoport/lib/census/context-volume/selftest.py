#!/usr/bin/env python3
"""BANC DU CORRECTIF « volume de contexte de l'agent principal ».

Il ne lit aucun journal : il fait TOURNER les deux pieces livrees, sur de vrais processus et de
vraies charges utiles de crochet, et il met les DEUX BRAS cote a cote.

LE BRAS D'AVANT EST L'ABSENCE, PAS UN DRAPEAU A ZERO. Il est tire du blob que
`lib/ablation_anchor.sh` designe — le dernier commit du chemin AVANT celui qui a introduit le
marqueur — jamais de `HEAD:`, qui serait faux des le commit du correctif.

Sortie : des lignes `cle=valeur` sans espace.
"""
import json, os, re, subprocess, sys, tempfile, time, shutil

ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True,
                      text=True).stdout.strip()
AP = os.path.join(ROOT, '.autoport')
OUT = {}
PANNES = []


def pub(k, v):
    OUT[k] = re.sub(r'\s+', '_', str(v)) if str(v).strip() else '-'


def ancre(chemin, marqueur):
    r = subprocess.run(['bash', os.path.join(AP, 'lib/ablation_anchor.sh'),
                        ROOT, chemin, marqueur, 'commit'],
                       capture_output=True, text=True, timeout=120)
    return r.stdout.strip()


def blob(commit, chemin):
    r = subprocess.run(['git', '-C', ROOT, 'show', f'{commit}:{chemin}'],
                       capture_output=True, text=True, timeout=120)
    return r.stdout if r.returncode == 0 else ''


# =========================================================== 1. LE CROCHET, DEUX BRAS ========
MARQUEUR_HOOK = 'harness-main-agent-context-volume, 19/09'
CHEMIN_HOOK = '.autoport/hooks/pre-tool.sh'

# label, commande, rc attendu ARME, rc attendu AVANT
CHARGES = [
    ('sleep-nu-20',        'sleep 20',                                                  2, 0),
    ('sleep-court-5',      'sleep 5',                                                   0, 0),
    ('sleep-enchaine',     'echo debut; sleep 30; echo fin',                            2, 0),
    ('boucle-qui-dort',    'while kill -0 123 2>/dev/null; do sleep 20; done',          2, 0),
    ('boucle-courte',      'for i in 1 2 3; do echo $i; sleep 1; done',                 0, 0),
    ('heredoc-qui-ecrit',  "cat > /tmp/z.sh <<'EOF'\nwhile true; do sleep 20; done\nEOF", 0, 0),
    ('await-le-remplacant','bash .autoport/lib/await.sh pid 12345 --timeout 60',        0, 0),
    ('porte-de-build',     '.autoport/lib/build_x86.sh --target gk',                    0, 0),
    ('regression-cmake',   'cmake --build build',                                       2, 2),
    ('regression-adb',     'adb shell ls',                                              2, 2),
    ('texte-qui-cite',     'grep -n "sleep 20" .autoport/hooks/pre-tool.sh',            0, 0),
    ('rapport-qui-cite',   'echo "on dormait sleep 30 dans une boucle while"',          0, 0),
]


def joue_crochet(script, cmd):
    payload = json.dumps({'tool_name': 'Bash', 'tool_input': {'command': cmd}})
    t0 = time.time()
    r = subprocess.run(['bash', script], input=payload, capture_output=True,
                       text=True, timeout=60, cwd=ROOT)
    return r.returncode, r.stderr, (time.time() - t0) * 1000


def bras_crochet():
    tmp = tempfile.mkdtemp(prefix='cv-hook-')
    try:
        arme = os.path.join(tmp, 'arme.sh')
        shutil.copy(os.path.join(ROOT, CHEMIN_HOOK), arme)
        shutil.copy(os.path.join(AP, 'hooks/cmake_initial_configure.py'), tmp)
        c = ancre(CHEMIN_HOOK, MARQUEUR_HOOK)
        pub('banc_ancre_commit', c[:12] or '-')
        texte_avant = blob(c, CHEMIN_HOOK) if c else ''
        pub('banc_ancre_octets', len(texte_avant))
        pub('banc_ancre_porte_le_marqueur', int(MARQUEUR_HOOK in texte_avant))
        avant = os.path.join(tmp, 'avant.sh')
        if texte_avant:
            open(avant, 'w', encoding='utf-8').write(texte_avant)
        else:
            avant = ''
            PANNES.append('ancre-du-crochet-introuvable')
        ok_a = ok_v = 0; nomme = 0; msmax = 0.0
        for label, cmd, att_a, att_v in CHARGES:
            rc, err, ms = joue_crochet(arme, cmd)
            msmax = max(msmax, ms)
            pub('banc_crochet_%s_rc' % label, rc)
            ok_a += int(rc == att_a)
            if att_a == 2 and att_v == 0:          # c'est CE correctif qui refuse
                nomme += int('await.sh' in err)
            if avant:
                rcv, _, _ = joue_crochet(avant, cmd)
                pub('banc_crochet_%s_rc_avant' % label, rcv)
                ok_v += int(rcv == att_v)
        pub('banc_crochet_charges', len(CHARGES))
        pub('banc_crochet_arme_conformes', ok_a)
        pub('banc_crochet_avant_conformes', ok_v if avant else -1)
        pub('banc_crochet_refus_nommant_await', nomme)
        pub('banc_crochet_refus_attendus', sum(1 for c in CHARGES if c[2] == 2 and c[3] == 0))
        pub('banc_crochet_ms_max', int(msmax))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ================================================== 2. L'ATTENTE, SUR DE VRAIS PROCESSUS =====
AWAIT = os.path.join(AP, 'lib/await.sh')


def joue_await(args, timeout=200):
    r = subprocess.run(['bash', AWAIT] + args, capture_output=True, text=True,
                       timeout=timeout, cwd=ROOT)
    kv = dict(l.split('=', 1) for l in r.stdout.splitlines() if re.match(r'^await_\w+=', l))
    return r.returncode, kv, r.stdout


def lance(duree):
    p = subprocess.Popen(['bash', '-c', 'exec sleep %d' % duree],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return p


def bras_attente():
    # A. la cible finit : UN SEUL appel, il rend la main quand elle meurt.
    p = lance(6); t0 = time.time()
    rc, kv, _ = joue_await(['pid', str(p.pid), '--timeout', '60'])
    dt = time.time() - t0
    p.wait(timeout=30)
    pub('banc_await_fini_rc', rc)
    pub('banc_await_fini_state', kv.get('await_state', '-'))
    pub('banc_await_fini_finished', kv.get('await_finished', '-'))
    pub('banc_await_fini_mesure_s', int(dt))
    pub('banc_await_fini_publie_s', kv.get('await_waited_s', '-'))
    pub('banc_await_fini_zombie', kv.get('await_zombie', '-'))

    # A2. LA MEME CIBLE, MAIS MOISSONNEE PAR LE SYSTEME. La jambe A ci-dessus attend un fils
    # que SON parent (ce banc) ne moissonne pas : `kill -0` y reussit encore apres la fin, et
    # une attente naive n'y finit jamais (mesure : 61 s pour un processus mort depuis 6).
    # Celle-ci est detachee — parent mort, reparentee, moissonnee — et doit rendre le MEME
    # verdict par l'autre chemin. Deux chemins, un seul resultat.
    tmp2 = tempfile.mkdtemp(prefix='cv-detach-')
    try:
        pf = os.path.join(tmp2, 'pid')
        subprocess.run(['bash', '-c',
                        "setsid bash -c 'echo $$ > %s; exec sleep 6' >/dev/null 2>&1 </dev/null &"
                        % pf], timeout=30)
        time.sleep(0.5)
        dpid = open(pf).read().strip() if os.path.exists(pf) else ''
        t0 = time.time()
        rc, kv, _ = joue_await(['pid', dpid or '1', '--timeout', '60']) if dpid else (-1, {}, '')
        pub('banc_await_detache_rc', rc)
        pub('banc_await_detache_state', kv.get('await_state', '-'))
        pub('banc_await_detache_finished', kv.get('await_finished', '-'))
        pub('banc_await_detache_zombie', kv.get('await_zombie', '-'))
        pub('banc_await_detache_mesure_s', int(time.time() - t0))
    finally:
        shutil.rmtree(tmp2, ignore_errors=True)

    # B. la borne tranche, et elle NE TUE PAS la cible.
    p = lance(60)
    rc, kv, _ = joue_await(['pid', str(p.pid), '--timeout', '3'])
    vivant = p.poll() is None
    p.kill(); p.wait(timeout=30)
    pub('banc_await_borne_rc', rc)
    pub('banc_await_borne_state', kv.get('await_state', '-'))
    pub('banc_await_borne_finished', kv.get('await_finished', '-'))
    pub('banc_await_borne_cible_vivante', int(vivant))

    # C. deja mort : « fini » n'est pas « jamais lance ».
    p = lance(1); p.wait(timeout=30); mort = p.pid
    time.sleep(0.2)
    rc, kv, _ = joue_await(['pid', str(mort), '--timeout', '30'])
    pub('banc_await_mort_rc', rc)
    pub('banc_await_mort_state', kv.get('await_state', '-'))
    pub('banc_await_mort_waited', kv.get('await_waited_s', '-'))

    # D. aucun pid a attendre : il le NOMME au lieu de dire « fini ».
    rc, kv, _ = joue_await(['lock', '/nonexistent/verrou'])
    pub('banc_await_sanspid_rc', rc)
    pub('banc_await_sanspid_state', kv.get('await_state', '-'))
    pub('banc_await_sanspid_finished', kv.get('await_finished', '-'))

    # E. LA SORTIE EST BORNEE : une attente ne rend pas au contexte ce qu'elle economise.
    tmp = tempfile.mkdtemp(prefix='cv-log-')
    try:
        j = os.path.join(tmp, 'gros.log')
        with open(j, 'w', encoding='utf-8') as fh:
            for i in range(10000):
                fh.write('%06d %s\n' % (i, 'x' * 2000))
        p = lance(1); p.wait(timeout=30)
        rc, kv, sortie = joue_await(['pid', str(p.pid), '--log', j, '--tail', '20'])
        pub('banc_await_sortie_octets', len(sortie))
        pub('banc_await_sortie_lignes', len(sortie.splitlines()))
        pub('banc_await_journal_octets', os.path.getsize(j))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # F. LE PLAFOND DUR : une borne demesuree est ramenee a 3600 s.
    p = lance(1); p.wait(timeout=30)
    rc, kv, _ = joue_await(['pid', str(p.pid), '--timeout', '99999'])
    pub('banc_await_plafond_s', kv.get('await_timeout_s', '-'))


# ========================================== 3. LA LIGNE DE LANCEMENT DU WORKER, DEUX BRAS ====
MARQUEUR_CLI = '--strict-mcp-config'
CHEMIN_CLI = '.autoport/lib/cli_backend.py'


def bras_cli():
    # LE BRAS ARME : on APPELLE la fonction, on ne la grep pas. Un grep compterait le commentaire.
    code = ('import sys,json;sys.path.insert(0,%r);'
            'from lib import cli_backend as c;'
            'print(json.dumps(c.worker_command(%r,"claude",{"manager_model":"m"},"high",300)))'
            % (AP, ROOT))
    r = subprocess.run([sys.executable, '-c', code], capture_output=True, text=True,
                       timeout=60, cwd=ROOT)
    try:
        argv = json.loads(r.stdout.strip())
    except Exception:
        argv = []
        PANNES.append('worker_command-injoignable')
    pub('banc_cli_argv_n', len(argv))
    pub('banc_cli_arme', int(MARQUEUR_CLI in argv))
    pub('banc_cli_premier', argv[0] if argv else '-')

    c = ancre(CHEMIN_CLI, MARQUEUR_CLI)
    pub('banc_cli_ancre_commit', c[:12] or '-')
    texte = blob(c, CHEMIN_CLI) if c else ''
    pub('banc_cli_ancre_octets', len(texte))
    pub('banc_cli_ancre_porte_le_marqueur', int(MARQUEUR_CLI in texte))
    if texte:
        tmp = tempfile.mkdtemp(prefix='cv-cli-')
        try:
            lib = os.path.join(tmp, 'lib')
            os.makedirs(lib)
            open(os.path.join(lib, '__init__.py'), 'w').close()
            open(os.path.join(lib, 'cli_backend.py'), 'w', encoding='utf-8').write(texte)
            code2 = ('import sys,json;sys.path.insert(0,%r);'
                     'from lib import cli_backend as c;'
                     'print(json.dumps(c.worker_command(%r,"claude",{"manager_model":"m"},"high",300)))'
                     % (tmp, ROOT))
            r2 = subprocess.run([sys.executable, '-c', code2], capture_output=True,
                                text=True, timeout=60, cwd=ROOT)
            try:
                argv2 = json.loads(r2.stdout.strip())
            except Exception:
                argv2 = []
                PANNES.append('worker_command-du-bras-avant-injoignable')
            pub('banc_cli_avant_argv_n', len(argv2))
            pub('banc_cli_avant_arme', int(MARQUEUR_CLI in argv2))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    else:
        pub('banc_cli_avant_argv_n', -1)
        pub('banc_cli_avant_arme', -1)
        PANNES.append('ancre-cli-introuvable')


# =============================== 4. LA CONSIGNE EST DANS LE PROMPT QUE LE WORKER RECOIT ======
def bras_preambule():
    code = ('import sys;sys.path.insert(0,%r);'
            'import importlib.util as u;'
            's=u.spec_from_file_location("o",%r);m=u.module_from_spec(s);\n'
            'import types\n' % (AP, os.path.join(AP, 'orchestrator.py')))
    # On ne CHARGE pas l'orchestrateur (il ouvre l'etat) : on lit le texte que sa fonction
    # assemble, en levant le litteral. Le noeud d'AST, pas un grep : un grep compterait
    # une docstring.
    import ast
    src = open(os.path.join(AP, 'orchestrator.py'), encoding='utf-8').read()
    tree = ast.parse(src)
    txt = ''
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == '_delegation_preamble':
            for sub in ast.walk(node):
                if isinstance(sub, ast.Constant) and isinstance(sub.value, str):
                    txt += sub.value
    pub('banc_preambule_octets', len(txt))
    pub('banc_preambule_nomme_await', int('await.sh' in txt))
    pub('banc_preambule_nomme_le_cout', int('195_000' in txt.replace(' ', '_')))


# ================= 5. CINQ TOURS DE LECTURE D'AFFILEE, SUR LE VRAI CROCHET ===================
# On ne lit pas la garde : on la fait TOURNER, sur des SEQUENCES de charges utiles, parce que
# son verdict depend de l'etat laisse par les tours precedents de la MEME session. Chaque jambe
# prend un `session_id` neuf et unique — deux jambes qui partagent un identifiant se polluent —
# et son fichier d'etat est efface a la fin. Le bras d'avant est L'ABSENCE de la garde : le
# blob du commit d'ancre, ecrit dans un fichier et EXECUTE, jamais relu.
MARQUEUR_LECT = "CINQ TOURS DE LECTURE"

# (label, commande, rc attendu ARME, rc attendu AVANT)
# Jambe A : cinq lectures pures -> la cinquieme est refusee, puis LE REJEU de la meme commande
# passe (le refus a remis le compteur a zero).
JAMBE_A = [
    ('a1-cat',    'cat .autoport/DIRECTIVES.md',                       0, 0),
    ('a2-sed',    'sed -n 1,20p .autoport/hooks/pre-tool.sh',          0, 0),
    ('a3-grep',   'grep -c refuse .autoport/hooks/pre-tool.sh',        0, 0),
    ('a4-wc',     'wc -l .autoport/hooks/pre-tool.sh',                 0, 0),
    ('a5-refus',  'ls .autoport/lib',                                  2, 0),
    ('a6-rejeu',  'ls .autoport/lib',                                  0, 0),
]
# Jambe B : quatre lectures, UN TOUR DE TRAVAIL (`python3 -c`), puis une lecture qui DOIT
# passer — sans la remise a zero elle serait la cinquieme. Puis on remonte a cinq pour verifier
# que le compteur a bien REDEMARRE a partir du travail, et non qu'il est mort.
JAMBE_B = [
    ('b1-cat',    'cat .autoport/DIRECTIVES.md',                       0, 0),
    ('b2-head',   'head -5 .autoport/hooks/pre-tool.sh',               0, 0),
    ('b3-tail',   'tail -5 .autoport/hooks/pre-tool.sh',               0, 0),
    ('b4-stat',   'stat -c %s .autoport/hooks/pre-tool.sh',            0, 0),
    ('b5-travail','python3 -c "print(1)"',                             0, 0),
    ('b6-apres',  'cat .autoport/DIRECTIVES.md',                       0, 0),
    ('b7-cat',    'wc -c .autoport/hooks/pre-tool.sh',                 0, 0),
    ('b8-cat',    'ls .autoport/hooks',                                0, 0),
    ('b9-cat',    'grep -c exit .autoport/hooks/pre-tool.sh',          0, 0),
    ('b10-refus', 'cat .autoport/DIRECTIVES.md',                       2, 0),
]
# Jambe D : une seconde rafale independante, pour que la population de refus attendus soit
# superieure a un seul evenement.
JAMBE_D = [
    ('d1', 'cat .autoport/DIRECTIVES.md',                  0, 0),
    ('d2', 'ls .autoport',                                 0, 0),
    ('d3', 'wc -l .autoport/hooks/pre-tool.sh',            0, 0),
    ('d4', 'head -1 .autoport/hooks/pre-tool.sh',          0, 0),
    ('d5', 'sed -n 1,3p .autoport/hooks/pre-tool.sh',      2, 0),
]
# Jambe C : SANS session_id. La garde ne peut pas separer deux sessions : elle ne refuse
# JAMAIS. Six charges, toutes des lectures pures, toutes doivent passer.
JAMBE_C = [
    ('c%d' % i, cmd, 0, 0) for i, cmd in enumerate([
        'cat .autoport/DIRECTIVES.md',
        'ls .autoport',
        'wc -l .autoport/hooks/pre-tool.sh',
        'head -2 .autoport/hooks/pre-tool.sh',
        'tail -2 .autoport/hooks/pre-tool.sh',
        'grep -c set .autoport/hooks/pre-tool.sh',
    ], 1)
]


def joue_lecture(script, cmd, sid):
    charge = {'tool_name': 'Bash', 'tool_input': {'command': cmd}}
    if sid:
        charge['session_id'] = sid
    t0 = time.time()
    r = subprocess.run(['bash', script], input=json.dumps(charge), capture_output=True,
                       text=True, timeout=60, cwd=ROOT)
    return r.returncode, r.stderr, (time.time() - t0) * 1000


def etat_de(sid):
    sur = re.sub(r'[^A-Za-z0-9_-]', '_', sid)
    return os.path.join(os.environ.get('TMPDIR', '/tmp'), 'autoport-lecture-%s' % sur)


def bras_lecture():
    import uuid
    tmp = tempfile.mkdtemp(prefix='cv-lect-')
    mes_sids = []
    try:
        arme = os.path.join(tmp, 'arme.sh')
        shutil.copy(os.path.join(ROOT, CHEMIN_HOOK), arme)
        shutil.copy(os.path.join(AP, 'hooks/cmake_initial_configure.py'), tmp)

        # L'ANCRE. La garde vient d'etre ecrite et n'est pas encore commitee : `git log -S` est
        # muet, le repli de ablation_anchor.sh rend alors le dernier commit du chemin — un etat
        # qui NE PORTE PAS la garde, donc un bras d'avant valide. S'il est muet aussi, HEAD.
        c = ancre(CHEMIN_HOOK, MARQUEUR_LECT)
        if not c:
            c = subprocess.run(['git', '-C', ROOT, 'rev-parse', 'HEAD'],
                               capture_output=True, text=True).stdout.strip()
        texte_avant = blob(c, CHEMIN_HOOK) if c else ''
        pub('banc_lecture_ancre_commit', c[:12] or '-')
        pub('banc_lecture_ancre_octets', len(texte_avant))
        pub('banc_lecture_ancre_porte_le_marqueur', int(MARQUEUR_LECT in texte_avant))
        avant = os.path.join(tmp, 'avant.sh')
        if texte_avant:
            open(avant, 'w', encoding='utf-8').write(texte_avant)
        else:
            avant = ''
            PANNES.append('ancre-lecture-introuvable')

        jeton = '%s-%d' % (uuid.uuid4().hex[:12], os.getpid())
        jambes = [('A', JAMBE_A, True), ('B', JAMBE_B, True),
                  ('D', JAMBE_D, True), ('C', JAMBE_C, False)]
        n = ok_a = ok_v = 0
        att_refus = refus_a = refus_v = nomme = 0
        sans_session_refus = 0
        msmax = 0.0
        rc_par_label = {}
        for nom, jambe, avec_sid in jambes:
            sid_a = 'banc-%s-%s-arme' % (jeton, nom) if avec_sid else ''
            sid_v = 'banc-%s-%s-avant' % (jeton, nom) if avec_sid else ''
            for s in (sid_a, sid_v):
                if s:
                    mes_sids.append(s)
            for label, cmd, att_a, att_v in jambe:
                n += 1
                att_refus += int(att_a == 2)
                rc, err, ms = joue_lecture(arme, cmd, sid_a)
                msmax = max(msmax, ms)
                rc_par_label[label] = rc
                ok_a += int(rc == att_a)
                if rc == 2:
                    refus_a += 1
                    nomme += int('autoport-researcher' in err)
                    if not avec_sid:
                        sans_session_refus += 1
                if avant:
                    rcv, _, msv = joue_lecture(avant, cmd, sid_v)
                    msmax = max(msmax, msv)
                    ok_v += int(rcv == att_v)
                    refus_v += int(rcv == 2)
        pub('banc_lecture_charges', n)
        pub('banc_lecture_arme_conformes', ok_a)
        pub('banc_lecture_avant_conformes', ok_v if avant else -1)
        pub('banc_lecture_avant_refus', refus_v if avant else -1)
        pub('banc_lecture_refus_attendus', att_refus)
        pub('banc_lecture_refus_obtenus', refus_a)
        pub('banc_lecture_refus_nommant_agent', nomme)
        # Le rejeu : la MEME commande, rejouee juste apres son refus, doit passer.
        pub('banc_lecture_rejeu_passe',
            int(rc_par_label.get('a5-refus') == 2 and rc_par_label.get('a6-rejeu') == 0))
        # La remise a zero par un tour de TRAVAIL : sans elle, b6 serait la cinquieme lecture.
        pub('banc_lecture_reset_par_travail',
            int(rc_par_label.get('b5-travail') == 0 and rc_par_label.get('b6-apres') == 0
                and rc_par_label.get('b10-refus') == 2))
        pub('banc_lecture_sans_session', sans_session_refus)
        pub('banc_lecture_ms_max', int(msmax))
    finally:
        # UNIQUEMENT mes identifiants : d'autres sessions tournent, le motif entier ne se
        # balaye jamais.
        for s in mes_sids:
            try:
                os.remove(etat_de(s))
            except OSError:
                pass
        shutil.rmtree(tmp, ignore_errors=True)


try:
    bras_crochet()
except Exception as e:
    PANNES.append('crochet:%s' % type(e).__name__)
try:
    bras_attente()
except Exception as e:
    PANNES.append('attente:%s' % type(e).__name__)
try:
    bras_cli()
except Exception as e:
    PANNES.append('cli:%s' % type(e).__name__)
try:
    bras_preambule()
except Exception as e:
    PANNES.append('preambule:%s' % type(e).__name__)
try:
    bras_lecture()
except Exception as e:
    PANNES.append('lecture:%s' % type(e).__name__)
    for _k in ('banc_lecture_charges', 'banc_lecture_arme_conformes',
               'banc_lecture_avant_conformes', 'banc_lecture_refus_attendus',
               'banc_lecture_refus_obtenus', 'banc_lecture_avant_refus',
               'banc_lecture_refus_nommant_agent', 'banc_lecture_rejeu_passe',
               'banc_lecture_reset_par_travail', 'banc_lecture_sans_session',
               'banc_lecture_ms_max', 'banc_lecture_ancre_commit',
               'banc_lecture_ancre_octets', 'banc_lecture_ancre_porte_le_marqueur'):
        OUT.setdefault(_k, '-1')

pub('banc_ran', 1)
pub('banc_panne', '+'.join(PANNES) if PANNES else '-')
for k in sorted(OUT):
    print('%s=%s' % (k, OUT[k]))
