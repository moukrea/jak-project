"""Both CLIs through the same attempt lifecycle, with no real model/device calls."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

import pytest

from lib import cli_backend as cb
from lib import model_profile
from test_attempt import item_repo, ITEM

ROOT = Path(__file__).resolve().parents[3]


def _modele(cmd):
    """Le modele que la ligne de commande EPINGLE, '' si elle n'en epingle aucun.

    Les deux tests qui exigeaient l'ABSENCE de `--model` mesuraient en realite le fichier
    `.autoport/codex/profiles.json` du jour : verts avec `manager_model: ""`, rouges des que
    l'owner y a nomme un modele. On lit l'invariant, plus la donnee livree.

    DEPUIS harness-undeclared-profile-attempts (2026-09-19) le '' est un cas qui NE PEUT PLUS
    SE PRODUIRE : `codex_options` refuse un profil non resolu. Le repli reste ici pour que le
    test qui l'attend le VOIE, au lieu de mourir sur un IndexError.
    """
    if '--model' not in cmd:
        return ''
    assert cmd.count('--model') == 1, cmd
    return cmd[cmd.index('--model') + 1]


@pytest.fixture
def codex_repo(orch, item_repo, monkeypatch):
    monkeypatch.setattr(orch, 'BACKEND', 'codex')
    profile = cb.codex_profile(ROOT)
    monkeypatch.setattr(orch, '_PROFILE', profile)
    # LE MODELE VIENT DU PROFIL, PAS D'UN DECRET DE CE BANC
    # (harness-undeclared-profile-attempts, 2026-09-19). Ces deux lignes posaient '' EN DUR :
    # elles reproduisaient, dans la suite, exactement l'etat des vingt-huit essais du
    # 2026-09-07. `run_attempt` refuse desormais de partir sur un profil non resolu, et un
    # banc qui epingle un defaut ne peut pas servir de decor a tous les autres tests.
    monkeypatch.setattr(orch, 'MODEL', profile['manager_model'])
    monkeypatch.setattr(orch, 'SUBAGENT_MODEL', profile['worker_model'])
    monkeypatch.setattr(orch, 'PROFILE_NAME', profile['_active_name'])
    # LE PROFIL EST RELU A LA FRONTIERE D'ITEM (JAK-265, 23/09) : `run_attempt` relit
    # `<REPO_ROOT>/.autoport/codex/profiles.json` a chaque essai, comme `main` au lancement.
    # Sans ce fichier dans le bac a sable, les douze tests Codex partaient en `no-start`
    # (profil refuse) au lieu de mesurer le cycle d'essai.
    dst = orch.AUTOPORT_DIR / 'codex' / 'profiles.json'
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text((ROOT / '.autoport/codex/profiles.json').read_text())
    bindir = orch.AUTOPORT_DIR / 'fakebin'
    bindir.mkdir()
    monkeypatch.setenv('PATH', str(bindir) + os.pathsep + os.environ['PATH'])
    return bindir


def fake_codex(bindir, events, rc=0, tail=''):
    exe = bindir / 'codex'
    exe.write_text('#!/usr/bin/env python3\nimport sys,json\n'
                   'sys.stdin.read()\n'
                   'assert "exec" in sys.argv and "--json" in sys.argv and sys.argv[-1] == "-"\n'
                   'assert "--max-turns" not in sys.argv and "--effort" not in sys.argv\n'
                   + ''.join('print(' + repr(json.dumps(e)) + ', flush=True)\n' for e in events)
                   + tail + '\nsys.exit(' + str(rc) + ')\n')
    exe.chmod(0o755)


WORK = [{'type': 'thread.started', 'thread_id': 'thread-demo'},
        {'type': 'item.started', 'item': {'id': 'one', 'type': 'command_execution', 'command': 'true'}},
        {'type': 'item.completed', 'item': {'id': 'one', 'type': 'command_execution', 'command': 'true'}},
        {'type': 'turn.completed', 'usage': {'input_tokens': 100, 'output_tokens': 20, 'cached_input_tokens': 70}}]


def test_codex_attempt_runs_same_validator_and_handoff(orch, codex_repo):
    fake_codex(codex_repo, WORK)
    orch.GENERIC_VALIDATOR.write_text('echo "FAIL counter=4 expected=0"\nexit 1\n')
    state = orch.load_state()
    out = orch.run_attempt(dict(ITEM), state)
    assert out.kind == 'fail'
    assert state['retries']['demo'] == 1
    assert 'counter=4' in orch.handoff_path('demo').read_text()
    records = [json.loads(l) for l in (orch.LOG_ROOT/'demo/attempt-001.jsonl').read_text().splitlines()]
    assert records[0]['backend'] == 'codex'
    assert records[-1]['tool_calls'] == 1
    assert records[-1]['tokens_in'] == 100
    assert records[-1]['cache_read'] == 70


@pytest.mark.parametrize('events', [[], WORK[:2]])
def test_codex_rate_refusal_never_burns_retry(orch, codex_repo, events):
    fake_codex(codex_repo, events + [{'type':'turn.failed','error': {'message':'429 usage limit reached','resets_at':2000000000}}], rc=1)
    state = orch.load_state()
    out = orch.run_attempt(dict(ITEM), state)
    assert out.kind == 'no-start'
    assert out.resume_at == 2000000000
    assert not state['retries'].get('demo')
    assert not list(orch.LOG_ROOT.rglob('validator-*'))
    assert out.stderr_tail


def test_codex_auth_error_pauses_not_blocked_nor_counted(orch, codex_repo):
    # PANNE-D-AUTH/ (25/09) : un refus d'authentification est l'environnement, pas le chantier.
    # Il bloquait l'item ; il met desormais la boucle en pause (voir test_auth_outage.py).
    fake_codex(codex_repo, [{'type': 'error', 'message': '401 Unauthorized authentication failed'}], rc=1)
    state = orch.load_state()
    out = orch.run_attempt(dict(ITEM), state)
    assert out.kind == 'auth'
    assert '401' in out.reason
    assert not state['retries'].get('demo')


def test_codex_missing_model_is_still_blocked(orch, codex_repo):
    fake_codex(codex_repo, [{'type': 'error', 'message': '404 model not found'}], rc=1)
    out = orch.run_attempt(dict(ITEM), orch.load_state())
    assert out.kind == 'blocked'


def test_codex_tools_containing_error_words_are_not_api_failures(orch, codex_repo):
    fake_codex(codex_repo, WORK[:2] + [{'type':'item.completed', 'item':{'id':'one','type':'command_execution','aggregated_output':'429 quota exceeded 401'}}] + WORK[-1:])
    out = orch.run_attempt(dict(ITEM), orch.load_state())
    assert out.kind == 'fail'


def test_codex_scope_change_even_under_continuous_output(orch, codex_repo):
    fake_codex(codex_repo, WORK[:2], tail='import time\nfor i in range(100):\n print(json.dumps({"type":"turn.started"}),flush=True)\n time.sleep(.05)')
    orch.SCOPE_STAMP.write_text('before')
    threading.Timer(.2, lambda: orch.SCOPE_STAMP.write_text('after')).start()
    state = orch.load_state()
    out = orch.run_attempt(dict(ITEM), state)
    assert out.kind == 'interrupted'
    assert not state['retries'].get('demo')


def test_cli_options_are_isolated_and_toml_valid(tmp_path):
    import tomllib
    p = cb.codex_profile(ROOT)
    cmd = cb.worker_command(ROOT, 'codex', p, 'high', 30)
    assert cmd[:2] == ['codex', 'exec']
    # `--model` SUIT le profil actif, il ne se decrete pas ici. Ce test exigeait son absence :
    # il etait vert tant que `manager_model` valait "" et il est devenu rouge le 2026-09-07 a
    # 18:02, quand l'owner a fixe Astra (50e9dc5af6) — une DONNEE livree, pas une regression de
    # code. On mesure desormais l'invariant, dans les DEUX regimes, sur des profils injectes :
    # un verdict de test ne doit pas dependre du fichier de configuration du jour.
    assert _modele(cmd) == p['manager_model']
    # UN MODELE VIDE N'EST PLUS UN REGIME, C'EST UN REFUS
    # (harness-undeclared-profile-attempts, 2026-09-19). Cette ligne exigeait auparavant que
    # la commande parte SANS `--model` — l'invariant qui a laisse partir vingt-huit essais
    # sur un modele que personne n'avait choisi. Le meme profil, ampute du meme champ, doit
    # maintenant lever ; et le refus NOMME le champ, il ne dit pas « profil invalide ».
    for champ in ('manager_model', 'worker_model', 'manager_effort'):
        with pytest.raises(model_profile.ProfileUnresolved) as refus:
            cb.worker_command(ROOT, 'codex', dict(p, **{champ: ''}), 'high', 30)
        assert champ in str(refus.value)
    nomme = cb.worker_command(ROOT, 'codex', dict(p, manager_model='modele-injecte'), 'high', 30)
    assert _modele(nomme) == 'modele-injecte'
    assert nomme.count('--model') == 1
    for i, token in enumerate(cmd):
        if token == '-c':
            tomllib.loads(cmd[i+1])
    assert 'hooks.PreToolUse=' in ' '.join(cmd)
    claude = cb.worker_command(tmp_path, 'claude', {'manager_model':'claude-existing'}, 'medium', 22)
    assert claude[:2] == ['claude','-p']
    assert claude[claude.index('--max-turns')+1] == '22'
    assert '--settings' in claude
    assert 'codex' not in claude


def test_backend_default_environment_and_explicit(monkeypatch):
    from lib import backend_control
    monkeypatch.setattr(backend_control, 'default', lambda: 'claude')
    monkeypatch.delenv('AUTOPORT_BACKEND', raising=False)
    assert cb.selected() == 'claude'
    monkeypatch.setenv('AUTOPORT_BACKEND','codex')
    assert cb.selected() == 'codex'
    assert cb.selected('claude') == 'claude'
    with pytest.raises(ValueError):
        cb.selected('typo')


@pytest.mark.parametrize('name,args', [
    ('Bash', {'command':'adb shell true'}),
    ('exec_command', {'cmd':'cmake -B build'}),
    ('apply_patch', {'command':'*** Begin Patch\n*** Add File: .autoport/reports/demo/proof.png\n+x\n*** End Patch'}),
])
def test_codex_hook_denies_same_rules_without_executing_tools(name,args):
    env = dict(os.environ)
    env.pop('AUTOPORT_PHASE_ID',None)
    r = subprocess.run([sys.executable,str(ROOT/'.autoport/codex/hook.py'),'PreToolUse'],
                       input=json.dumps({'tool_name':name,'tool_input':args,'cwd':str(ROOT)}),
                       text=True,capture_output=True,env=env)
    assert r.returncode == 2, r.stderr


def test_codex_patch_can_quote_forbidden_commands():
    env = dict(os.environ)
    env.pop('AUTOPORT_PHASE_ID',None)
    r = subprocess.run([sys.executable,str(ROOT/'.autoport/codex/hook.py'),'PreToolUse'],
                      input=json.dumps({'tool_name':'apply_patch','tool_input':{'command':'*** Add File: notes.md\n+adb shell cmake -B build'}}),
                      text=True,capture_output=True,env=env)
    assert r.returncode == 0


def test_phase_claim_excludes_other_cli_and_recovers_dead_holder(tmp_path):
    (tmp_path/'.autoport').mkdir()
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(tmp_path))
    script = ROOT/'.autoport/phase_claim.sh'
    # Use real PID/starttime/comm identities, no process-name pattern matching.
    body = 'import ctypes,subprocess,sys,time\nctypes.CDLL(None).prctl(15,sys.argv[1].encode(),0,0,0)\nr=subprocess.run(["bash",sys.argv[2],"claim","demo"])\nprint(r.returncode,flush=True)\ntime.sleep(30) if r.returncode==0 else None\n'
    first = subprocess.Popen([sys.executable,'-c',body,'claude',str(script)],env=env,stdout=subprocess.PIPE,text=True)
    try:
        assert first.stdout.readline().strip() == '0'
        second = subprocess.run([sys.executable,'-c',body,'codex',str(script)],env=env,capture_output=True,text=True,timeout=5)
        assert second.stdout.strip().endswith('3')
    finally:
        first.terminate(); first.wait(timeout=5)
    third = subprocess.Popen([sys.executable,'-c',body,'codex',str(script)],env=env,stdout=subprocess.PIPE,text=True)
    try:
        assert third.stdout.readline().strip() == '0'
        r = subprocess.run(['bash',str(script),'status','demo'],env=env,capture_output=True,text=True)
        assert r.returncode == 0
        assert f'pid={third.pid}' in r.stdout
    finally:
        third.terminate(); third.wait(timeout=5)


def test_codex_success_still_waits_for_owner(orch, codex_repo, monkeypatch):
    fake_codex(codex_repo, WORK)
    orch.GENERIC_VALIDATOR.write_text('exit 0\n')
    # Le faux prenait UN argument ; `close_gate` en recoit DEUX depuis que GATE 0 lit la ligne
    # de base de l'arbre (ff60991381, 2026-09-12). Le test mourait en TypeError DANS
    # l'orchestrateur, donc sur un message qui n'accusait pas le faux. Le faux porte desormais
    # la signature reelle ET verifie qu'on lui passe bien cette ligne de base : s'il derive de
    # nouveau, c'est ici que ca rougit, avec le bon nom.
    # 2026-09-12, seconde derive : GATE -1 (« preuve impossible ») a donne a `close_gate` un
    # `validator_ok` et un `since`, parce qu'elle doit voir AUSSI un essai que le validateur a
    # refuse. Le faux les prend et les VERIFIE : ici, le validateur a passe, et `since` est
    # l'instant ou l'essai a commence — jamais zero, sinon l'etat d'un essai precedent
    # requalifierait celui-ci.
    vus = []
    def faux_close_gate(item, pre_dirty_engine, validator_ok=True, since=0.0):
        vus.append((item['id'], pre_dirty_engine, validator_ok, since))
        return ('awaiting-owner', '')
    monkeypatch.setattr(orch, 'close_gate', faux_close_gate)
    monkeypatch.setattr(orch, 'git_push', lambda: None)
    assert orch.run_attempt(dict(ITEM), orch.load_state()).kind == 'awaiting-owner'
    assert [v[0] for v in vus] == ['demo']
    assert isinstance(vus[0][1], list)
    assert vus[0][2] is True
    assert vus[0][3] > 0


def test_codex_midrun_transport_failure_is_infra(orch, codex_repo):
    fake_codex(codex_repo, WORK[:2] + [{'type':'turn.failed','error':{'message':'stream disconnected before completion: connection reset'}}], rc=1)
    state = orch.load_state()
    out = orch.run_attempt(dict(ITEM), state)
    assert out.kind == 'infra'
    assert not state['retries'].get('demo')


def test_missing_cli_is_logged_without_burning_retry(orch, codex_repo):
    state = orch.load_state()
    # Point at an explicitly missing executable, independently of the real PATH.
    original = cb.worker_command
    cb.worker_command = lambda *a: [str(codex_repo / 'absent')]
    try:
        out = orch.run_attempt(dict(ITEM), state)
    finally:
        cb.worker_command = original
    assert out.kind == 'no-start'
    assert not state['retries'].get('demo')
    assert 'launch_error' in (orch.LOG_ROOT/'demo/attempt-001.jsonl').read_text()


def load_watch():
    spec = importlib.util.spec_from_file_location('autoport_watch_test', ROOT/'.autoport/watch.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_watch_never_consumes_the_interactive_digest_cursor(tmp_path, monkeypatch, capsys):
    w = load_watch()
    (tmp_path/'.autoport').mkdir()
    monkeypatch.setattr(w, 'ROOT', tmp_path)
    class B:
        def status_report(self, changed_only=False):
            assert not changed_only
            return 'En cours : essai local'
        def next_open(self):
            return None
    monkeypatch.setattr(w.backlog, 'load', lambda: B())
    monkeypatch.setattr(w.subprocess, 'Popen', lambda *a,**k: pytest.fail('Observation must not launch'))
    assert w.main(['--backend','codex','--once']) == 0
    assert 'essai local' in capsys.readouterr().out


def test_watch_recognizes_any_existing_orchestrator_lock(tmp_path):
    import fcntl
    w = load_watch()
    (tmp_path/'.autoport').mkdir()
    with (tmp_path/'.autoport/.orchestrator.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert w.orchestrator_running(tmp_path)
    assert not w.orchestrator_running(tmp_path)


def test_supervisor_resume_targets_exact_codex_thread():
    r = subprocess.run(['bash',str(ROOT/'.autoport/supervisor.sh'),'--backend','codex','--check','--resume','test-thread-id'],text=True,capture_output=True)
    assert r.returncode == 0, r.stderr
    cmd = json.loads(r.stdout)['command']
    assert cmd[0] == 'codex'
    assert cmd[-2:] == ['resume','test-thread-id']
    assert '--last' not in cmd
    # Meme cause qu'au-dessus : le modele vient du profil actif, pas d'un decret de ce test.
    assert _modele(cmd) == cb.codex_profile(ROOT)['manager_model']


def test_watch_queues_each_change_once_to_exact_supervisor(tmp_path, monkeypatch):
    w = load_watch()
    (tmp_path/'.autoport').mkdir()
    (tmp_path/'.autoport/.supervisor-codex-session').write_text('supervisor-uuid\n')
    calls = []
    def run(cmd, **kwargs):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, '', '')
    monkeypatch.setattr(w.subprocess, 'run', run)
    assert w.notify_supervisor(tmp_path, 'A tester : une feature')
    assert w.notify_supervisor(tmp_path, 'A tester : une feature')
    assert len(calls) == 1
    assert calls[0][:4] == ['codex','queue','--thread','supervisor-uuid']
    assert w.notify_supervisor(tmp_path, 'A tester : autre feature')
    assert len(calls) == 2
    assert not any('--last' in cmd for cmd in calls)


def test_watch_escalates_blocked_priority_for_repair_without_repeat(tmp_path, monkeypatch):
    w = load_watch()
    (tmp_path / '.autoport').mkdir()
    calls = []
    def run(cmd, **kwargs):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, '', '')
    monkeypatch.setattr(w.subprocess, 'run', run)
    report = 'Bloqué : références HDR'
    assert w.notify_supervisor(tmp_path, report, 'supervisor-uuid')
    assert w.notify_supervisor(tmp_path, report, 'supervisor-uuid', recovery=('lighting-census',))
    assert len(calls) == 2  # escalation is not swallowed by an earlier status-only digest
    prompt = calls[-1][-1]
    assert 'Reprise superviseur requise pour : lighting-census' in prompt
    assert 'corrige le harnais' in prompt
    assert w.notify_supervisor(tmp_path, report, 'supervisor-uuid', recovery=('lighting-census',))
    assert len(calls) == 2


def test_failed_supervisor_queue_is_not_acknowledged(tmp_path, monkeypatch):
    w = load_watch()
    (tmp_path/'.autoport').mkdir()
    monkeypatch.setattr(w.subprocess, 'run', lambda cmd,**kw: subprocess.CompletedProcess(cmd, 1, '', 'offline'))
    assert not w.notify_supervisor(tmp_path, 'A tester', 'uuid')
    assert not (tmp_path/'.autoport/.last_codex_watch').exists()


def test_guard_explanation_never_probes_devices(tmp_path):
    lib = tmp_path/'.autoport/lib'
    lib.mkdir(parents=True)
    picker = lib/'pick_device.sh'
    picker.write_text('#!/bin/bash\ntouch picker-was-run\n')
    picker.chmod(0o755)
    r = subprocess.run(['bash',str(ROOT/'.autoport/hooks/pre-tool.sh')],
                       cwd=tmp_path, input=json.dumps({'tool_name':'Bash','tool_input':{'command':'adb shell true'}}),
                       text=True,capture_output=True)
    assert r.returncode == 2
    assert not (tmp_path/'picker-was-run').exists()


def test_claude_existing_settings_symlink_is_not_registered_twice(tmp_path):
    (tmp_path/'.claude').mkdir()
    (tmp_path/'.autoport').mkdir()
    (tmp_path/'.autoport/settings.json').write_text('{}')
    (tmp_path/'.claude/settings.local.json').symlink_to('../.autoport/settings.json')
    cmd = cb.worker_command(tmp_path,'claude',{'manager_model':'original'},'high',100)
    assert '--settings' not in cmd


def test_watch_restarts_for_an_abandoned_in_progress_item(tmp_path, monkeypatch):
    from types import SimpleNamespace
    w = load_watch()
    (tmp_path/'.autoport').mkdir()
    monkeypatch.setattr(w, 'ROOT', tmp_path)
    b = SimpleNamespace(items=[{'status':'in-progress'}], next_open=lambda:None,
                        status_report=lambda:'En cours : à reprendre')
    monkeypatch.setattr(w.backlog, 'load', lambda:b)
    calls=[]
    def spawn(cmd,**kw):
        calls.append(cmd)
        return SimpleNamespace(pid=123)
    monkeypatch.setattr(w.subprocess,'Popen',spawn)
    assert w.main(['--backend','codex','--once','--maintain']) == 0
    assert calls[0][-3:] == ['--backend','codex','--quiet']


def test_watch_reports_unchanged_status_after_thirty_minutes(tmp_path, monkeypatch):
    w = load_watch()
    (tmp_path / '.autoport').mkdir()
    calls = []
    def run(cmd, **kwargs):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, '', '')
    monkeypatch.setattr(w.subprocess, 'run', run)
    assert w.notify_supervisor(tmp_path, 'En cours HDR', 'supervisor-uuid')
    memo = tmp_path / '.autoport/.last_codex_watch'
    sent = memo.stat().st_mtime
    monkeypatch.setattr(w.time, 'time', lambda: sent + 1799)
    assert w.notify_supervisor(tmp_path, 'En cours HDR', 'supervisor-uuid')
    assert len(calls) == 1
    monkeypatch.setattr(w.time, 'time', lambda: sent + 1800)
    assert w.notify_supervisor(tmp_path, 'En cours HDR', 'supervisor-uuid')
    assert len(calls) == 2
    assert 'Point périodique' in calls[-1][-1]
