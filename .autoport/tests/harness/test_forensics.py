"""Reading the attempt stream as EVENTS, never as text.

The 529-storm heuristic counted `overloaded` and `\\b529\\b` ANYWHERE in the
attempt JSONL, tool outputs included. Two consequences, both measured:

  * orchestrator.py itself contained six such literals, so a worker that read
    the harness source pre-loaded the counter;
  * any non-zero exit with three hits became an "infra outage" — 58 storms were
    logged, the large majority `exit 143`, which is OUR OWN watchdog SIGTERM.
    The validator was skipped and the WIP commit was not made, for a session we
    killed ourselves.

Only structured API error events count now.
"""
import json


def _jsonl(tmp_path, events):
    p = tmp_path / "attempt-001.jsonl"
    p.write_text("".join(json.dumps(e) + "\n" for e in events))
    return p


def test_a_tool_output_mentioning_529_is_not_a_storm(orch, tmp_path):
    noisy = ("grep found 529 matches; the server was overloaded; "
             "see orchestrator.py line 529 and the \\b529\\b regex")
    p = _jsonl(tmp_path, [
        {"type": "user", "message": {"content": [
            {"type": "tool_result", "content": noisy}]}},
        {"type": "assistant", "message": {"content": [
            {"type": "text", "text": "the API returned 529 Overloaded, apparently"}]}},
        {"type": "result", "subtype": "success", "is_error": False},
    ])
    assert orch.count_api_529(p) == 0


def test_real_api_retries_are_counted(orch, tmp_path):
    p = _jsonl(tmp_path, [
        {"type": "system", "subtype": "api_retry", "attempt": 1,
         "error_status": 529, "error": "rate_limit"},
        {"type": "system", "subtype": "api_retry", "attempt": 2,
         "error_status": 529, "error": "rate_limit"},
        {"type": "system", "subtype": "api_retry", "attempt": 3,
         "error_status": None, "error": "unknown"},
        {"type": "system", "subtype": "api_retry", "attempt": 4,
         "error_status": 529, "error": "rate_limit"},
    ])
    assert orch.count_api_529(p) == 3
    assert orch.count_api_529(p) >= orch.API_529_STORM_THRESHOLD


def test_a_nested_api_error_status_counts(orch, tmp_path):
    p = _jsonl(tmp_path, [
        {"type": "result", "subtype": "error_during_execution",
         "message": {"error": {"api_error_status": 529}}},
    ])
    assert orch.count_api_529(p) == 1


def test_malformed_lines_do_not_break_the_scan(orch, tmp_path):
    p = tmp_path / "attempt-002.jsonl"
    p.write_text("not json at all\n"
                 '{"type": "system", "subtype": "api_retry", "error_status": 529}\n'
                 "\n"
                 "[1, 2, 3]\n")
    assert orch.count_api_529(p) == 1


def test_fatal_config_is_detected_from_the_status_not_from_prose(orch, tmp_path):
    ok = _jsonl(tmp_path, [
        {"type": "assistant", "message": {"content": [
            {"type": "text", "text": 'the docs say "api_error_status":404 means gone'}]}},
    ])
    assert orch.fatal_config_reason(ok) == ""

    bad = _jsonl(tmp_path, [{"type": "result", "api_error_status": 404}])
    assert "404" in orch.fatal_config_reason(bad)


def test_the_reset_hour_comes_from_a_refusal_only(orch, tmp_path):
    allowed = _jsonl(tmp_path, [
        {"type": "rate_limit_event", "rate_limit_info": {
            "status": "allowed", "resetsAt": 1779153000, "rateLimitType": "five_hour"}},
    ])
    assert orch.rate_reset_from_log(allowed) is None

    refused = _jsonl(tmp_path, [
        {"type": "rate_limit_event", "rate_limit_info": {
            "status": "allowed", "resetsAt": 1779153000}},
        {"type": "rate_limit_event", "rate_limit_info": {
            "status": "rejected", "resetsAt": 1779184200}},
    ])
    assert orch.rate_reset_from_log(refused) == 1779184200


def test_no_quota_probing_machinery_survives(orch):
    """The probe made 1105 failed calls against 39 successes and could not pause
    anything: every threshold was 999. The only quota behaviour left is sleeping
    until the reset hour the API returns on a refusal."""
    for gone in ("fetch_rate_status", "wait_for_quota", "maybe_probe_inline",
                 "_parse_rate_payload", "get_oauth_token", "RateStatus",
                 "notify", "spec_sections_remaining", "load_milestones",
                 "NOTIFY_SCRIPT", "HARD_KILL_PCT", "WEEKLY_PAUSE_PCT"):
        assert not hasattr(orch, gone), f"{gone} is dead code and must be gone"
    assert hasattr(orch, "rate_reset_from_log")
    assert hasattr(orch, "sleep_until")
