"""PANNE-D-AUTH/ — un refus d'authentification de l'API n'est pas un echec du chantier.

25/09 : jeton OAuth revoque, 25 items BLOQUES en cascade sur « erreur API 401 », et l'essai qui
travaillait deja COMPTE. Les evenements ci-dessous sont ceux des journaux reels de ce jour-la.
"""
import json

from test_attempt import ITEM, _fake_claude

TXT = "Failed to authenticate. API Error: 401 OAuth access token has been revoked."
RETRY = {"type": "system", "subtype": "api_retry", "error_status": 401,
         "error": "authentication_failed"}
SYNTH = {"type": "assistant", "message": {"model": "<synthetic>", "role": "assistant",
         "content": [{"type": "text", "text": TXT}]}, "error": "authentication_failed"}
RES_401 = {"type": "result", "subtype": "success", "is_error": True,
           "terminal_reason": "api_error", "api_error_status": 401, "result": TXT}
TOOL = {"type": "assistant", "message": {"usage": {"input_tokens": 10, "output_tokens": 5},
        "content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "true"}}]}}


def _body(*events, rc=1):
    return "".join("echo '%s'\nsleep 0.1\n" % json.dumps(e) for e in events) + "exit %d\n" % rc


def test_le_classement_ne_lit_que_ce_que_la_cli_a_ecrit():
    from lib import auth_outage
    assert auth_outage.refusal([RETRY, SYNTH, RES_401]).startswith("API 401")
    # Un 401 CITE dans la sortie d'un outil (un worker qui lit ce code) n'est pas un refus.
    cite = {"type": "user", "message": {"content": [{"type": "tool_result", "content": TXT}]}}
    assert auth_outage.refusal([cite, {"type": "result", "is_error": False}]) == ""
    # La CLI a reessaye en 401 puis a fini normalement : pas de refus.
    assert auth_outage.refusal([RETRY, {"type": "result", "is_error": False}]) == ""
    # Un 404 (modele absent) reste une erreur de configuration.
    assert auth_outage.refusal([dict(RES_401, api_error_status=404, result="404")]) == ""


def test_un_401_en_plein_travail_n_est_ni_compte_ni_bloque(orch, sandbox, monkeypatch):
    creds = orch.AUTOPORT_DIR / "creds.json"
    creds.write_text("{}")
    monkeypatch.setattr(orch, "CREDENTIALS_PATH", creds)
    monkeypatch.setattr(orch, "build_instructions", lambda item, seq: "prompt\n")
    monkeypatch.setattr(orch, "READ_POLL_SEC", 0.2)
    (orch.AUTOPORT_DIR / "prompts").mkdir(parents=True, exist_ok=True)
    (orch.AUTOPORT_DIR / "prompts" / "item-demo.md").write_text("Fais la chose.\n")
    orch.GENERIC_VALIDATOR.write_text("#!/usr/bin/env bash\nexit 1\n")
    orch.GENERIC_VALIDATOR.chmod(0o755)
    _fake_claude(orch, _body({"type": "system", "subtype": "init", "session_id": "s"},
                             TOOL, RETRY, SYNTH, RES_401))
    state = orch.load_state()
    out = orch.run_attempt(dict(ITEM), state)
    assert out.kind == "auth"
    assert state["retries"].get("demo", 0) == 0
    assert not list((orch.LOG_ROOT / "demo").glob("validator-*.txt"))


def test_la_pause_resonde_et_reprend_seule_avec_une_alerte_unique(orch, sandbox, monkeypatch):
    monkeypatch.setattr(orch, "AUTH_PAUSE_NOW", orch.LOG_ROOT / "auth-pause.json")
    monkeypatch.setattr(orch, "AUTH_JOURNAL", orch.LOG_ROOT / "auth-outage.jsonl")
    monkeypatch.setattr(orch, "AUTH_PROBE_EVERY_S", 0)
    monkeypatch.setattr(orch, "AUTH_ALERT_AFTER_S", 0)
    monkeypatch.setattr(orch, "nap", lambda s: None)
    answers = iter([False, False, True])
    monkeypatch.setattr(orch, "auth_probe", lambda: (next(answers), "API simulee"))
    assert orch.auth_pause("demo", "API 401") is True
    events = [json.loads(l)["event"] for l in
              (orch.LOG_ROOT / "auth-outage.jsonl").read_text().splitlines()]
    assert events == ["pause", "probe", "alert", "probe", "probe", "resume"]
    assert not (orch.LOG_ROOT / "auth-pause.json").exists()
