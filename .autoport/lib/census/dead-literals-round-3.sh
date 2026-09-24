#!/usr/bin/env bash
# census/dead-literals-round-3.sh — DEUX LITTERAUX, ET CE QU'ILS RENDAIENT CREUX.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course. Sa
# sortie `cle=valeur` rejoint celle du moteur dans le MEME journal, moissonnee par la MEME regle.
# Il n'ecrit aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la
# machine.
#
# CE QU'IL COMPTE. `dead_literals_r3_defects` = T1 + T2 + T3 + penalites.
# T3 compare chaque sortie vivante sur les memes sources courantes epinglees par SHA256.
#
#   T1 — UNE ASSERTION QUI NE POUVAIT PAS ECHOUER. `lib/hdr_batches.py` comparait
#        `particle_step_const` a la chaine `'once-per-logic-frame'` que `refset.cpp` y ecrit
#        lui-meme : la condition ne pouvait pas etre vraie. Le protocole qu'elle pretendait
#        garantir — le temps des particules n'avance QUE d'un pas par frame de logique — n'etait
#        donc verifie par personne. Le terme n'est PAS mesure en lisant le code : les DEUX arbres
#        sont montes dans un bac a sable et le VRAI lecteur (`hdr_batches.read_batch`) y est
#        joue sur des lots fabriques par le VRAI fabricant de la suite (`temporal_particle_batch`).
#        La valeur fabriquee est la MEME des deux cotes, au bit : `particle_steps` fige a 4242 sur
#        toutes les photos — un feu qui ne bouge plus entre deux photos espacees de `spacing_lf`
#        frames de logique. AVANT elle ne declenche RIEN, APRES elle declenche.
#        POURQUOI CETTE VALEUR-LA ET PAS UNE AUTRE : elle est CONSTANTE sur la sequence. Une
#        valeur qui varierait ferait rougir l'arbre d'AVANT par sa clause « reglages temporels
#        changes dans la sequence », et le temoin de vacuite accuserait alors une AUTRE clause.
#
#   T2 — UNE BRANCHE MORTE ET SON LITTERAL. `float tess_w = 0.0;` figeait `tess_displaced` a faux
#        et rendait mort le bloc qui en decoulait, dans `shaders/pbr_fused.glsl`. CE CHANTIER N'EN
#        RETIRE PAS UNE LIGNE : le fichier ENTIER — 816 lignes — a quitte l'arbre le 12/09 a 17:52
#        avec le commit `c65c9a71bd` (lighting-legacy-purge), quelques heures apres que le
#        signalement l'ait nomme. L'item le DIT au lieu de revendiquer un gain, et il le MESURE :
#        temoin non nul sur l'arbre du signalement, zero sur l'arbre livre, zero dans le blob que
#        l'Android embarque, chacun avec son controle positif.
#        CE QUI RESTAIT VRAIMENT A FAIRE, ET QUE CE CHANTIER FAIT : `shaders/preprocess.py`
#        n'effacait RIEN. Un chunk retire des sources laissait sa copie dans `out_dir` pour
#        toujours. Mesure du 13/09 : TREIZE fichiers y trainaient, dont `pbr_fused.glsl` du 12/09
#        14:18 — le litteral et sa branche morte, intacts, a la disposition du prochain lecteur,
#        trois heures APRES leur sortie de l'arbre. Le blob livre, lui, etait propre : le residu
#        n'atteignait ni `libgk.so` ni l'APK, il atteignait l'HUMAIN. La purge est posee AU POINT
#        DE PRODUCTION, et l'ablation la mesure : le module d'AVANT laisse l'orphelin, celui
#        d'APRES le retire, sans toucher aux deux controles semes pour rester.
#
# POURQUOI LE ZERO N'EST PAS UN ZERO D'INACTION. Chaque detecteur est rejoue, dans ce processus,
# sur l'arbre TEL QU'IL ETAIT au commit EPINGLE d'avant l'item. Chaque temoin `..._before` doit
# etre NON NUL. Un temoin « avant » lu a `HEAD:` deviendrait faux a la seconde ou l'on commite :
# les commits sont ECRITS ICI.
#
# POLARITE, NON NEGOCIABLE : TOUT INCONNU VAUT DEFAUT. Source illisible, bac a sable muet,
# population vide, controle positif qui rougit : on publie une valeur NON NULLE qui ferme la
# porte, jamais un zero par silence. Le script sort en 0 meme quand il accuse — c'est le
# validateur qui juge.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "dead_literals_r3_audit_ran=0"; echo "dead_literals_r3_defects=9001"; exit 0; }
cd "$ROOT" || { echo "dead_literals_r3_audit_ran=0"; echo "dead_literals_r3_defects=9002"; exit 0; }

# Le commit d'AVANT l'item, EPINGLE : l'arbre ou l'assertion etait encore vide.
BEFORE_COMMIT=cc00f44ca828075acb873078b41b8dd6b6436b13
# Le commit du SIGNALEMENT, EPINGLE : l'arbre ou `pbr_fused.glsl` portait encore la branche morte.
SHADER_BEFORE_COMMIT=37fa60521db936de67a57cf0e8897ebd805b7578
# Le commit qui a sorti le fichier de l'arbre, EPINGLE : le credit ne nous revient pas.
SHADER_REMOVED_BY=c65c9a71bd2e00aa1f4799abf4dae000769503a5

python3 - "$BEFORE_COMMIT" "$SHADER_BEFORE_COMMIT" "$SHADER_REMOVED_BY" <<'PYEOF'
import hashlib, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, ".autoport/lib/census")
import anchor as A

BEFORE_COMMIT, SHADER_BEFORE_COMMIT, SHADER_REMOVED_BY = sys.argv[1], sys.argv[2], sys.argv[3]

# ── LA PUBLICATION ──────────────────────────────────────────────────────────────────────────────
# UNE VALEUR NE PORTE JAMAIS D'ESPACE. Le moissonneur de `proof_run.sh` ne retient que
# `^cle=[^[:space:]]+$` : un message d'exception ecrit en clair serait publie pour personne. On
# colle les espaces AU POINT DE PUBLICATION, jamais a la main dans chaque appel.
OUT = []
def pub(k, v):
    OUT.append('dead_literals_r3_%s=%s' % (k, re.sub(r'\s+', '_', str(v)) or '-'))
REASONS, PENALTY = [], [0]
def note(msg, cost=1000):
    REASONS.append(msg)
    PENALTY[0] += cost

HDR = '.autoport/lib/hdr_batches.py'
HDR_TEST = '.autoport/tests/harness/test_hdr_batches.py'
ARTIFACT_BENCH = Path('.autoport/tests/harness/dead_literals_r3_artifacts.py').resolve()
REFSET = 'game/graphics/refset.cpp'
SHADER = 'game/graphics/opengl_renderer/shaders/pbr_fused.glsl'
SHADER_DIR = 'game/graphics/opengl_renderer/shaders'
PREPROC = SHADER_DIR + '/preprocess.py'
# Ce que le bac a sable doit porter pour que le juge s'IMPORTE lui-meme : le lecteur, la suite qui
# fabrique les lots, le backlog et `refset.cpp` d'ou `hdr.contract()` tire la table des vantages.
LEVELS = 'goal_src/jak1/engine/level/level-info.gc'
SANDBOX_PATHS = ['.autoport/lib', '.autoport/tests', '.autoport/backlog.yaml', REFSET, LEVELS]

TMPS = []
NOTES = Path('.autoport/reports/dead-literals-round-3/notes')
NOTES.mkdir(parents=True, exist_ok=True)
SCRATCH = NOTES.resolve() / 'sandboxes'
SCRATCH.mkdir(exist_ok=True)

def scratch(prefix):
    # Les deux vrais preprocesseurs et leurs sorties restent hors /tmp, meme si TMPDIR y pointe.
    d = tempfile.mkdtemp(prefix=prefix, dir=SCRATCH)
    TMPS.append(d)
    return d

def sandbox_from_commit(commit, paths):
    d = scratch('r3-before-')
    a = subprocess.run(['git', 'archive', commit] + paths,
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if a.returncode != 0 or not a.stdout:
        return None
    t = subprocess.run(['tar', '-x', '-C', d], input=a.stdout, stderr=subprocess.DEVNULL)
    return d if t.returncode == 0 else None

def sandbox_from_worktree(paths):
    d = scratch('r3-after-')
    c = subprocess.run(['tar', '-c', '--exclude=__pycache__', '--exclude=.pytest_cache', '--'] + paths,
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if c.returncode != 0 or not c.stdout:
        return None
    t = subprocess.run(['tar', '-x', '-C', d], input=c.stdout, stderr=subprocess.DEVNULL)
    return d if t.returncode == 0 else None

def blob_at(commit, rel):
    r = subprocess.run(['git', 'show', '%s:%s' % (commit, rel)],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    return r.stdout if r.returncode == 0 else None

# ════════════════════════════════════════════════════════════════════════════════════════════════
# T1 — L'ASSERTION QUI NE POUVAIT PAS ECHOUER
# ════════════════════════════════════════════════════════════════════════════════════════════════
# La valeur FABRIQUEE, une seule, ecrite ici et publiee : le compteur de pas de la particule fige.
# Entre deux photos espacees de `spacing_lf` frames de logique il doit avancer d'exactement
# `spacing_lf` ; fige, il n'avance pas du tout. C'est le feu qui gele — la panne meme que le
# protocole disait empecher.
FABRICATED = 4242

PROBE = '''# genere par lib/census/dead-literals-round-3.sh — jamais commite.
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
# `plan` est une fixture DEFINIE DANS le module de test : l'importer dans l'espace de noms de
# ce fichier est la seule facon pour pytest de la resoudre ici.
from test_hdr_batches import hdr, plan, stats, temporal_particle_batch  # noqa: F401

FABRICATED = %d

def _play(tmp_path, plan, mutate, tag):
    try:
        path = temporal_particle_batch(tmp_path, plan, mutate)
        rows = [json.loads(line.split(' options=', 1)[1])['temporal']
                for line in (path / 'engine.log').read_text().splitlines()
                if line.startswith('REFSET effective ')]
        measured = sum(row.get('particle_steps') is not None for row in rows)
        print('R3POP %%s %%d %%d %%d' %% (tag, len(rows), measured, len(rows) - measured))
    except Exception as exc:                       # banc casse : ce n'est pas un verdict
        print('R3PROBE %%s bench %%s' %% (tag, type(exc).__name__))
        return
    try:
        hdr.read_batch(path / 'manifest.json', plan, stats)
    except Exception as exc:
        print('R3PROBE %%s raised %%s:%%s' %% (tag, type(exc).__name__, str(exc)[:90]))
        return
    print('R3PROBE %%s silent -' %% tag)

def test_probe_valid(tmp_path, plan):
    _play(tmp_path, plan, lambda case, sample, options: None, 'valid')

def test_probe_legacy(tmp_path, plan):
    def strip(case, sample, options):
        options['temporal'].pop('particle_steps', None)
    _play(tmp_path, plan, strip, 'legacy')

def test_probe_violation(tmp_path, plan):
    def freeze(case, sample, options):
        options['temporal']['particle_steps'] = FABRICATED
    _play(tmp_path, plan, freeze, 'violation')

def test_probe_mixed(tmp_path, plan):
    def mix(case, sample, options):
        options['temporal']['particle_steps'] = FABRICATED
        if sample == 1:
            options['temporal'].pop('particle_steps')
    _play(tmp_path, plan, mix, 'mixed')
''' % FABRICATED

def run_probe(sandbox, arm):
    """Rend {tag: (etat, message)} — etat dans 'silent' / 'raised' / 'bench' / 'absent'."""
    test_path = Path(sandbox) / HDR_TEST
    rel = test_path.parent
    if not test_path.is_file():
        return None
    (rel / 'test_zzz_r3_probe.py').write_text(PROBE)
    env = dict(os.environ)
    # L'ESSAI COURANT NE DOIT PAS VOYAGER DANS LE BANC. `AUTOPORT_ATTEMPT_ID` fait rougir des
    # tests du harnais qui comparent la preuve a l'essai en cours : un faux rouge ici serait lu
    # comme un verdict sur le lecteur.
    for k in ('AUTOPORT_ATTEMPT_ID', 'AUTOPORT_PHASE_ID', 'AUTOPORT_CENSUS_ID',
              'AUTOPORT_CENSUS_ARMED', 'AUTOPORT_CENSUS_DIR', 'AUTOPORT_FEATURE_SITE'):
        env.pop(k, None)
    r = subprocess.run([sys.executable, '-m', 'pytest', '-q', '-s', '-p', 'no:cacheprovider',
                        str(rel / 'test_zzz_r3_probe.py')],
                       cwd=sandbox, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, timeout=600)
    if r.returncode:
        note('t1-pytest-en-erreur:' + arm)
    seen, populations = {}, {}
    for line in r.stdout.split('\n'):
        # `re.search`, pas `re.match` : pytest colle son point de progression devant la ligne.
        m = re.search(r'R3PROBE (\S+) (\S+) (.*)$', line)
        if m:
            seen[m.group(1)] = (m.group(2), m.group(3))
        m = re.search(r'R3POP (\S+) (\d+) (\d+) (\d+)$', line)
        if m:
            populations[m.group(1)] = tuple(map(int, m.groups()[1:]))
    if len(seen) != 4:
        # UN BANC MUET DOIT DIRE POURQUOI. Sans cette trace, « le lecteur ne rougit pas » et
        # « pytest n'a pas pu jouer la jambe » se publient tous les deux comme un silence. Le
        # journal part dans `notes/`, qu'aucune porte ne lit.
        d = Path('.autoport/reports/dead-literals-round-3/notes')
        d.mkdir(parents=True, exist_ok=True)
        (d / ('probe-%s.txt' % arm)).write_text(r.stdout)
        pub('t1_bench_tail_' + arm, (r.stdout.strip().split('\n') or ['-'])[-1][:120])
    return (seen, populations) if seen else None

def t1():
    bad = 0
    before = sandbox_from_commit(BEFORE_COMMIT, SANDBOX_PATHS)
    after = sandbox_from_worktree(SANDBOX_PATHS)
    pub('before_commit', BEFORE_COMMIT[:10])
    pub('t1_before_sandbox', 1 if before else 0)
    pub('t1_after_sandbox', 1 if after else 0)
    pub('t1_fabricated_value', FABRICATED)
    if not before or not after:
        note('t1-bac-a-sable-illisible'); return 9000

    res = {}
    for arm, sb in (('before', before), ('after', after)):
        got = run_probe(sb, arm)
        if got is None:
            note('t1-banc-muet:' + arm); bad += 9000; continue
        got, populations = got
        for tag in ('valid', 'legacy', 'violation', 'mixed'):
            state, msg = got.get(tag, ('absent', '-'))
            res[(arm, tag)] = (state, msg)
            pub('t1_%s_%s' % (arm, tag), state)
            if state == 'raised':
                pub('t1_%s_%s_msg' % (arm, tag), msg)
            counts = populations.get(tag, (0, 0, 0))
            for field, value in zip(('samples', 'measured', 'missing'), counts):
                pub('t1_%s_%s_%s' % (arm, tag, field), value)
            n, measured, missing = counts
            if n <= 0 or measured + missing != n:
                note('t1-population-vide:' + arm + '/' + tag); bad += 1000
            if ((tag == 'violation' or (tag == 'valid' and arm == 'after')) and measured != n
                    or tag == 'legacy' and missing != n
                    or tag == 'mixed' and (not measured or not missing)):
                note('t1-population-incompatible:' + arm + '/' + tag); bad += 1000
    pub('t1_bench_ran', 1)

    # LES CONTROLES POSITIFS. Un lot NON fabrique doit se lire des DEUX cotes : si le banc rougit
    # partout, il est casse et ne mesure rien (pas meme un defaut).
    for arm in ('before', 'after'):
        for tag in ('valid', 'legacy'):
            state = res.get((arm, tag), ('absent',))[0]
            if state != 'silent':
                note('t1-controle-positif-rouge:%s/%s=%s' % (arm, tag, state)); bad += 1000
    # LE TEMOIN DE VACUITE. La valeur fabriquee, identique au bit des deux cotes, ne declenche
    # RIEN sur l'arbre d'avant. C'est ca, une assertion vide.
    st_b = res.get(('before', 'violation'), ('absent',))[0]
    if st_b != 'silent':
        note('t1-temoin-de-vacuite-absent:' + st_b); bad += 1000
    # ET ELLE DECLENCHE SUR L'ARBRE LIVRE, EN NOMMANT SA CAUSE. Un rouge qui nommerait une AUTRE
    # clause ne prouverait pas que la cadence est jugee.
    st_a, msg_a = res.get(('after', 'violation'), ('absent', '-'))
    if st_a != 'raised':
        note('t1-assertion-toujours-vide:' + st_a); bad += 1000
    elif 'particle step cadence' not in msg_a:
        note('t1-rouge-d-une-autre-clause'); bad += 1000
    pub('t1_violation_names_cadence', 1 if (st_a == 'raised' and 'particle step cadence' in msg_a) else 0)
    mixed_state, mixed_msg = res.get(('after', 'mixed'), ('absent', '-'))
    if mixed_state != 'raised' or 'mixed temporal particle step metadata' not in mixed_msg:
        note('t1-melange-non-refuse'); bad += 1000

    # LE LITTERAL LUI-MEME, DES DEUX COTES. Il etait compare, il ne l'est plus.
    pat = re.compile(r"particle_step_const'\)\s*!=")
    for arm, txt in (('before', blob_at(BEFORE_COMMIT, HDR)), ('after', Path(HDR).read_text())):
        if txt is None:
            note('t1-lecteur-illisible:' + arm); bad += 1000; continue
        n = len(pat.findall(txt))
        pub('t1_literal_terms_' + arm, n)
        if arm == 'before' and n == 0:
            note('t1-temoin-avant-du-litteral-a-zero'); bad += 1000
        if arm == 'after' and n:
            note('t1-litteral-encore-compare'); bad += n * 1000

    # LA CLE MESUREE EST BIEN EMISE, SANS GARDE OPTIONNELLE. Sans ce controle, un lot neuf
    # pourrait retomber au niveau d'avant en silence et la cadence ne serait plus jugee.
    src = Path(REFSET).read_text(errors='ignore')
    try:
        blk = A.tok_block(src, 'effective_options["temporal"] =', lang='c')
        ok = A.tok_count(blk, '{"particle_steps", g_part_steps}', lang='c') > 0
    except A.Introuvable:
        ok = False
    pub('t1_cpp_key_present', 1 if ok else 0)
    if not ok:
        note('t1-cle-mesuree-non-emise'); bad += 1000
    return bad

# ════════════════════════════════════════════════════════════════════════════════════════════════
# T2 — LA BRANCHE MORTE, SON LITTERAL, ET LE RESIDU QU'ILS ONT LAISSE SUR LE DISQUE
# ════════════════════════════════════════════════════════════════════════════════════════════════
DEAD_MARKS = ('float tess_w = 0.0;', 'bool tess_displaced = tess_w > TESS_COVER_MIN;',
              '&& tess_displaced)')
ORPHAN_CHUNK = 'zz_r3_orphan.glsl'
ORPHAN_VARIANT = 'zz_r3_orphan.android.frag'
FOREIGN_FILE = 'zz_r3_foreign.txt'          # controle A : a LAISSER (nom hors production)
FOREIGN_DIR = 'zz_r3_foreign_dir'           # controle B : a LAISSER (un repertoire)
SHADER_ARMS = {}
SOURCE_SNAPSHOT = {}

def dead_sites(text):
    return sum(text.count(m) for m in DEAD_MARKS) if text else 0

def preprocess_arm(script, src_dir, tag):
    """Joue UN module preprocess.py sur une copie jetable des sources, avec un `out_dir` SEME.
    Rend (rc, orphelin_survit, chunk_vivant, blob, controle_fichier, controle_repertoire)."""
    out = scratch('r3-out-%s-' % tag)
    Path(out, ORPHAN_CHUNK).write_text('// residu fabrique\nfloat tess_w = 0.0;\n')
    Path(out, ORPHAN_VARIANT).write_text('// residu fabrique\n')
    Path(out, FOREIGN_FILE).write_text('a laisser\n')
    Path(out, FOREIGN_DIR).mkdir()
    Path(out, FOREIGN_DIR, 'dedans.glsl').write_text('a laisser aussi\n')
    r = subprocess.run([sys.executable, str(Path(script).resolve()), src_dir, out],
                       cwd=src_dir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, timeout=300)
    (NOTES / ('preprocess-%s.txt' % tag)).write_text(r.stdout)
    live = sorted(p.name for p in Path(out).glob('*.glsl'))
    return (r.returncode,
            1 if Path(out, ORPHAN_CHUNK).exists() or Path(out, ORPHAN_VARIANT).exists() else 0,
            1 if [n for n in live if n != ORPHAN_CHUNK] else 0,
            1 if Path(out, 'shaders_android_blob.h').exists() else 0,
            1 if Path(out, FOREIGN_FILE).exists() else 0,
            1 if Path(out, FOREIGN_DIR, 'dedans.glsl').exists() else 0,
            out)

def t2():
    bad = 0
    pub('shader_before_commit', SHADER_BEFORE_COMMIT[:10])
    pub('t2_removed_by_commit', SHADER_REMOVED_BY[:10])
    # ── LE TEMOIN « AVANT » : la branche morte existait, et elle est chiffree ──────────────────
    txt = blob_at(SHADER_BEFORE_COMMIT, SHADER)
    pub('t2_shader_before_present', 1 if txt else 0)
    pub('t2_shader_before_lines', len(txt.split('\n')) - 1 if txt else 0)
    nb = dead_sites(txt)
    pub('t2_shader_before_dead_sites', nb)
    if not txt:
        note('t2-arbre-du-signalement-illisible'); bad += 1000
    elif nb == 0:
        note('t2-temoin-avant-de-la-branche-morte-a-zero'); bad += 1000
    # ── L'ARBRE LIVRE : le fichier a quitte l'arbre ENTIER, et ce n'est pas notre gain ─────────
    here = Path(SHADER).is_file()
    pub('t2_shader_head_present', 1 if here else 0)
    nh = dead_sites(Path(SHADER).read_text(errors='ignore')) if here else 0
    pub('t2_shader_head_dead_sites', nh)
    bad += nh * 1000
    if nh:
        note('t2-branche-morte-encore-dans-l-arbre')
    # LE CREDIT NE NOUS REVIENT PAS, ET LE DIRE EST UNE CLE, PAS UNE PHRASE DE RAPPORT.
    d = subprocess.run(['git', 'show', '--numstat', '--format=', SHADER_REMOVED_BY, '--', SHADER],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.split()
    pub('t2_lines_removed_by_purge_commit', d[1] if len(d) > 2 and d[1].isdigit() else 0)
    pub('t2_lines_removed_by_this_item', 0)
    pub('t2_gain_claimed', 0)
    # Resolution explicite du contrat : pas de mesure nulle pour un programme supprime.
    pub('t2_linked_program_fp_before', 'sans-objet')
    pub('t2_linked_program_fp_after', 'sans-objet')
    pub('t2_pom_keys', 'sans-objet')
    pub('t2_linked_program_fp_why', 'programme-et-producteurs-POM-supprimes-sur-ordre-owner')
    pub('t2_scope_resolution_commit', SHADER_REMOVED_BY)
    if here or len(d) <= 2 or not d[1].isdigit() or int(d[1]) <= 0:
        note('t2-provenance-de-suppression-invalide'); bad += 1000
    # ── CE QUE L'ANDROID EMBARQUE VRAIMENT, avec son controle positif ──────────────────────────
    sys.path.insert(0, str(ARTIFACT_BENCH.parent))
    from dead_literals_r3_artifacts import source_inventory
    original = source_inventory(Path(SHADER_DIR))
    src_copy = scratch('r3-src-')
    shutil.copytree(SHADER_DIR, src_copy, dirs_exist_ok=True)
    pinned = source_inventory(Path(src_copy))
    if original != pinned:
        raise RuntimeError('sources-changees-pendant-copie')
    SOURCE_SNAPSHOT.update(pinned)
    SOURCE_SNAPSHOT['path'] = src_copy
    (NOTES / 't3-sources.txt').write_text(pinned['manifest'])
    pub('t3_sources_sha256', pinned['sha256'])
    pub('t3_sources_files', pinned['files'])
    pub('t3_sources_bytes', pinned['bytes'])
    pub('t3_sources_inventory', str(NOTES / 't3-sources.txt'))
    pub('t3_sources_head', subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip())
    script_after = Path(src_copy, 'preprocess.py')
    pub('t3_preprocess_after_sha256', hashlib.sha256(script_after.read_bytes()).hexdigest())
    arm_after = preprocess_arm(str(script_after), src_copy, 'after')
    SHADER_ARMS['after'] = arm_after
    blob = Path(arm_after[6], 'shaders_android_blob.h')
    btxt = blob.read_text(errors='ignore') if blob.is_file() else ''
    pub('t2_blob_built', 1 if btxt else 0)
    hits = dead_sites(btxt) + btxt.count('pbr_fused')
    ctrl = btxt.count('shade.glsl')
    pub('t2_blob_dead_hits', hits)
    pub('t2_blob_control', ctrl)
    bad += hits * 1000
    if hits:
        note('t2-branche-morte-encore-dans-le-blob')
    if not btxt or ctrl == 0:
        note('t2-instrument-de-blob-aveugle'); bad += 1000
    # LE BINAIRE ARM64 LIVRE, quand il est la. Il n'est pas regenerable par ce recensement : son
    # absence est PUBLIEE, elle n'accuse pas. Sa presence, elle, est jugee — avec son controle.
    so = Path('android/app/src/main/jniLibs/arm64-v8a/libgk.so')
    pub('t2_so_present', 1 if so.is_file() else 0)
    if so.is_file():
        st = subprocess.run(['strings', '-a', str(so)], stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, errors='ignore').stdout
        sh = dead_sites(st) + st.count('pbr_fused')
        sc = st.count('shade.glsl')
        pub('t2_so_dead_hits', sh); pub('t2_so_control', sc)
        bad += sh * 1000
        if sh:
            note('t2-branche-morte-encore-dans-libgk')
        if sc == 0:
            note('t2-instrument-de-libgk-aveugle'); bad += 1000
    # ── L'ABLATION DE LA PURGE : le module d'AVANT laisse le residu, celui d'APRES le retire ───
    bsrc = sandbox_from_commit(BEFORE_COMMIT, [PREPROC])
    pub('t2_bench_before_sandbox', 1 if bsrc else 0)
    if not bsrc:
        note('t2-module-d-avant-illisible'); bad += 1000
    else:
        pub('t3_preprocess_before_sha256', hashlib.sha256(Path(bsrc, PREPROC).read_bytes()).hexdigest())
        arm_before = preprocess_arm(str(Path(bsrc) / PREPROC), src_copy, 'before')
        SHADER_ARMS['before'] = arm_before
        pub('t2_bench_before_rc', arm_before[0])
        pub('t2_bench_before_orphan_survives', arm_before[1])
        if arm_before[0] != 0:
            note('t2-module-d-avant-sorti-en-erreur'); bad += 1000
        elif arm_before[1] != 1:
            note('t2-ablation-sans-mordant'); bad += 1000
    pub('t2_bench_after_rc', arm_after[0])
    pub('t2_bench_after_orphan_survives', arm_after[1])
    pub('t2_bench_after_live_chunk_kept', arm_after[2])
    pub('t2_bench_after_blob_kept', arm_after[3])
    pub('t2_bench_after_foreign_file_kept', arm_after[4])
    pub('t2_bench_after_foreign_dir_kept', arm_after[5])
    if arm_after[0] != 0:
        note('t2-module-livre-sorti-en-erreur'); bad += 1000
    bad += arm_after[1] * 1000
    if arm_after[1]:
        note('t2-purge-sans-effet')
    for idx, nom in ((2, 'chunk-vivant'), (3, 'blob'), (4, 'fichier-etranger'), (5, 'repertoire')):
        if arm_after[idx] != 1:
            note('t2-purge-trop-large:' + nom); bad += 1000
    # ── LE RESIDU SUR LE DISQUE LIVRE, aujourd'hui ────────────────────────────────────────────
    real = Path('build-android/shaders')
    pub('t2_disk_out_present', 1 if real.is_dir() else 0)
    if real.is_dir():
        fresh = {p.name for p in Path(arm_after[6]).iterdir() if p.is_file()}
        fresh -= {ORPHAN_CHUNK, ORPHAN_VARIANT, FOREIGN_FILE}
        stale = sorted(p.name for p in real.iterdir()
                       if p.is_file() and p.name not in fresh
                       and (p.suffix == '.glsl'
                            or re.fullmatch(r'.+\.android\.(vert|frag|tesc|tese)', p.name)))
        pub('t2_disk_orphans', len(stale))
        pub('t2_disk_orphans_list', ','.join(stale) or '-')
        bad += len(stale) * 1000
        if stale:
            note('t2-residu-encore-sur-le-disque')
    return bad

# T3 reutilise exactement les deux passes T2 : aucun build ni nouvelle campagne.
def t3():
    from dead_literals_r3_artifacts import compare_outputs, source_inventory
    if set(SHADER_ARMS) != {'before', 'after'} or not SOURCE_SNAPSHOT:
        raise RuntimeError('t3-bras-ou-inventaire-manquant')
    bad = 0
    for arm in ('before', 'after'):
        if SHADER_ARMS[arm][0] != 0:
            note('t3-preprocesseur-en-erreur:' + arm); bad += 1000
    for where in (Path(SOURCE_SNAPSHOT['path']), Path(SHADER_DIR)):
        if source_inventory(where)['sha256'] != SOURCE_SNAPSHOT['sha256']:
            note('t3-sources-modifiees:' + str(where)); bad += 1000
    expected = SOURCE_SNAPSHOT['expected']
    before, after = (Path(SHADER_ARMS[arm][6]) for arm in ('before', 'after'))
    measured = compare_outputs(before, after, expected)
    for key in ('files', 'bytes', 'divergences', 'sha256'):
        pub('t3_compared_' + key, measured[key])
    pub('t3_expected_files', len(expected))
    pub('t3_live_list', ','.join(expected))
    pub('t3_comparison_defects', measured['defects'])
    pub('t3_comparison_issues', ';'.join(measured['issues']) or '-')
    inventory = NOTES / 't3-outputs.txt'
    inventory.write_text(measured['manifest'])
    pub('t3_outputs_inventory', str(inventory))
    bad += measured['defects']

    # Le meme comparateur doit rougir pour chaque categorie, puis retrouver le vert
    # apres restauration. Seuls les artefacts jetables sont modifies ici.
    choices = (next(n for n in expected if re.fullmatch(r'.+\.android\.(vert|frag|tesc|tese)', n)),
               next(n for n in expected if n.endswith('.glsl')), 'shaders_android_blob.h')
    trials, detected = 0, 0
    for name in choices:
        target = after / name
        content = target.read_bytes()
        try:
            for mutation in ('altered', 'missing'):
                if mutation == 'altered':
                    target.write_bytes(content + b'\n// r3 isolated alteration\n')
                else:
                    target.unlink()
                observed = compare_outputs(before, after, expected)
                trials += 1
                detected += observed['defects'] > measured['defects']
                pub('t3_negative_%s_%s_defects' % (name.replace('.', '_'), mutation), observed['defects'])
        finally:
            target.write_bytes(content)
    pub('t3_negative_trials', trials)
    pub('t3_negative_detected', detected)
    if trials != 6 or detected != trials:
        note('t3-comparateur-ne-detecte-pas-la-perte'); bad += 1000
    # Le seul ecart de noms genere par T2 doit etre le residu seme, hors inventaire vivant.
    residue_only = compare_outputs(before, after, expected)
    pub('t3_dead_residue_only_defects', residue_only['defects'])
    if residue_only['manifest'] != measured['manifest']:
        note('t3-restauration-du-banc-incomplete'); bad += 1000
    return bad

TERMS = []
try:
    for name, measure in (('t1', t1), ('t2', t2), ('t3', t3)):
        try:
            value = measure()
        except Exception as exc:                            # tout inconnu vaut DEFAUT
            note(name + '-exception:' + type(exc).__name__ + ':' + str(exc)[:100], 9000)
            value = 9000
        pub(name + '_defects', value)
        TERMS.append(value)
finally:
    for d in TMPS:
        shutil.rmtree(d, ignore_errors=True)

pub('audit_ran', 1)
pub('penalty', PENALTY[0])
pub('reason', ';'.join(REASONS) if REASONS else '-')
pub('defects', sum(TERMS) + PENALTY[0])
print('\n'.join(OUT))
PYEOF
exit 0
