# OpenGOAL → Android Autoport Drop-in

A complete autonomous orchestration system for porting OpenGOAL to Android using Claude Code. Drops directly into your forked `jak-project` repo.

## What this does

Runs Claude Opus 4.7 at max thinking effort in full `--dangerously-skip-permissions` mode (YOLO), across 12 phases (test harness → AArch64 codegen → Android APK), with rate-limit-aware pausing, automatic per-phase git commits, and optional phone notifications. Designed for a dedicated laptop running for days/weeks.

## Quick start

```bash
# 1. Clone your fork
git clone https://github.com/<your-gh>/jak-project ~/work/autoport
cd ~/work/autoport

# 2. Extract this package into the repo root
tar -xzf /path/to/autoport-dropin.tar.gz --strip-components=1

# 3. One-shot system setup (Fedora)
sudo ./setup-fedora.sh

# 4. Wire up the hooks
./install.sh

# 5. (Optional) configure phone notifications
./install.sh --ntfy autoport-jak-$(uuidgen | cut -c1-8)
# Install ntfy on your phone, subscribe to the topic it prints

# 6. One-time Claude Code trust dialog
claude
# When prompted "Trust this directory?", answer yes, then type /quit

# 7. Launch (runs in foreground)
./launch.sh
```

## Operating mode

- **Foreground** — runs in your terminal. You can see what's happening in real time. Output is also tee'd to `.autoport/logs/orchestrator.log` and a per-run timestamped log.
- **Ctrl+C once** → graceful halt (finishes current attempt, then exits cleanly).
- **Ctrl+C twice** → hard kill.
- **State is persisted** in `.autoport/state.json`, so re-launching with `./launch.sh` resumes from the last incomplete phase.

If you want to detach the orchestrator from your terminal (e.g. log out but keep it running), simple options:

```bash
# Option A: nohup (process survives terminal close, output still in log)
nohup ./launch.sh > /dev/null 2>&1 &

# Option B: tmux (if installed)
tmux new -s autoport './launch.sh'
# Detach: Ctrl+b d   Reattach: tmux a -t autoport

# Option C: just leave the terminal open (most common for dedicated laptops)
```

## Dedicated-laptop gotchas

Two things will silently halt a long run on Fedora unless you fix them:

### 1. Lid-close suspend

Fedora GNOME defaults to suspend when you close the lid. The orchestrator pauses with the OS.

```bash
# GNOME desktop:
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'nothing'

# systemd (belt and suspenders):
sudo sed -i 's/^#*HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind
```

`launch.sh` checks the GNOME setting and warns you on startup if it would suspend.

### 2. Auto-updates that reboot

If `dnf-automatic` is enabled, a kernel update can reboot mid-run. Either disable it or accept the occasional manual re-launch:

```bash
sudo systemctl disable --now dnf-automatic.timer 2>/dev/null || true
sudo systemctl disable --now dnf-automatic-install.timer 2>/dev/null || true
```

## Files added to your repo

```
.autoport/                          # everything lives here
  orchestrator.py                   # the supervisor (Python)
  milestones.yaml                   # phase plan
  settings.json                     # Claude Code hooks config
  hooks/*.sh                        # session lifecycle hooks
  lib/*.sh                          # rate-limit probe + notifications
  prompts/phase-NN-*.md             # one prompt per phase
  validators/phase-NN-*.sh          # one validator per phase
  state.json                        # runtime state (gitignored)
  logs/                             # per-phase logs (gitignored)
.claude/settings.local.json         # symlink -> ../.autoport/settings.json
setup-fedora.sh                     # one-shot system installer
install.sh                          # wires up hooks + venv
launch.sh                           # foreground launcher
```

## Defaults (all hardcoded, no fallback)

- **Model:** `claude-opus-4-7` for every phase
- **Thinking effort:** `max` via `CLAUDE_EFFORT` env + `ultrathink` keyword in prompts
- **Permission mode:** `--dangerously-skip-permissions` (no allowlist; full YOLO)
- **Safety net:** per-phase git commits, easy to bisect or revert anything
- **Rate limits:**
  - 5h session >= 90% -> pause until `resets_at + 90s` (exact epoch from API)
  - Weekly >= 95% -> pause until `resets_at + 90s` (NOT "next Monday" — uses actual epoch)
  - No Sonnet fallback, ever
- **Stuck detection:** if the same validator failure recurs 3 attempts in a row, halt honestly with the recurring error displayed. Retries are otherwise generous (10–20 per phase) — looping itself doesn't waste quota, only fruitless looping does.
- **Autonomy:** no human-review gates. Every phase runs to completion or to a stuck/blocked state on its own.

## When to step in

- ntfy alert says **STUCK** -> same failure 3x. The notification includes the recurring error lines. Either fix the underlying issue (broken validator, wrong assumption in the prompt, missing dependency) or simplify the phase scope, then clear `fingerprints[<phase>]` and `retries[<phase>]` in state.json and restart.
- ntfy alert says **BLOCKED** -> hit `max_retries` without getting stuck. Means slow progress, not no progress. Usually safe to bump `max_retries` in milestones.yaml and restart.

## Tuning knobs

Edit `.autoport/milestones.yaml`:
- `max_turns` per phase
- `max_retries` per phase
- `requires_human_review: true` to pause at a phase

Edit constants at the top of `.autoport/orchestrator.py`:
- Rate-limit thresholds
- Reset buffer seconds
- Polling interval

## Status check while running

```bash
# Live tail of orchestrator output
tail -f .autoport/logs/orchestrator.log

# Manual rate-limit probe (run from another terminal)
.autoport/lib/check_limits.sh

# Current phase
jq . .autoport/state.json

# Per-phase logs
ls -la .autoport/logs/<phase-id>/
```

See `.autoport/README.md` for deeper docs.
