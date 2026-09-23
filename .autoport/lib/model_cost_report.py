#!/usr/bin/env python3
"""Cout par modele et par role, mesure en continu sur les journaux d'essais.

POURQUOI CE FICHIER EXISTE (owner-attention-aux-profils-opus-5-5-bouscule-tout, livrable 4).
`autoport cost` ne mesurait que le SUPERVISEUR. Personne ne lisait, jour apres jour, combien
coute le manager face aux sous-agents, ni si un essai croise (trial) vaut ce qu'il coute.
Ce module lit les journaux d'essais (`logs/<item>/attempt-*.jsonl`), les verdicts
(`logs/<item>/validator-*.txt`), le cache du superviseur (`supervisor_cost.py`) et les essais
croises actifs (`model-profiles.json`), et publie un tableau compact plus une alerte quand le
cout par item valide grimpe de plus de 50 % d'une fenetre glissante a l'autre.

Aucune ecriture : ce module ne fait que lire et publier.
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIB_DIR = HERE
AP_DIR = os.path.dirname(HERE)                 # .../.autoport
DEFAULT_ROOT = os.path.dirname(AP_DIR)         # repo root

TAIL_BYTES = 512 * 1024


def _fmt_fr(n):
    """1234.5 -> '1234,5'"""
    s = "%.2f" % n
    return s.replace(".", ",")


def _parse_iso(s):
    if not s:
        return None
    try:
        s2 = s.replace("Z", "+00:00")
        d = datetime.datetime.fromisoformat(s2)
        if d.tzinfo is None:
            d = d.replace(tzinfo=datetime.timezone.utc)
        return d
    except Exception:                                    # noqa: BLE001
        return None


def _read_first_line(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            line = fh.readline()
    except OSError:
        return None
    line = line.strip()
    if not line:
        return None
    try:
        return json.loads(line)
    except Exception:                                     # noqa: BLE001
        return None


def _find_tagged_lines(text, tag):
    """Lignes contenant `tag` (sous-chaine), dans l'ordre du texte."""
    out = []
    for line in text.splitlines():
        if tag in line:
            out.append(line)
    return out


def _last_matching(path, tag):
    """Le dernier objet JSON d'une ligne contenant `tag`. Lit d'abord les 512 derniers Ko ;
    si rien n'y est trouve, relit le fichier entier (les lignes candidates seulement)."""
    try:
        size = os.path.getsize(path)
    except OSError:
        return None
    try:
        with open(path, "rb") as fh:
            if size > TAIL_BYTES:
                fh.seek(size - TAIL_BYTES)
                chunk = fh.read()
            else:
                fh.seek(0)
                chunk = fh.read()
    except OSError:
        return None
    text = chunk.decode("utf-8", errors="replace")
    cands = _find_tagged_lines(text, tag)
    obj = None
    for line in reversed(cands):
        try:
            obj = json.loads(line)
            break
        except Exception:                                 # noqa: BLE001
            continue
    if obj is not None or size <= TAIL_BYTES:
        return obj
    # pas trouve dans la queue : relire tout le fichier, ligne candidate seulement
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if tag in line:
                    try:
                        obj = json.loads(line)
                    except Exception:                      # noqa: BLE001
                        continue
    except OSError:
        return obj
    return obj


def _attempt_paths(root):
    logs_dir = os.path.join(root, ".autoport", "logs")
    out = []
    try:
        items = sorted(os.listdir(logs_dir))
    except OSError:
        return out
    for item in items:
        idir = os.path.join(logs_dir, item)
        if not os.path.isdir(idir):
            continue
        try:
            names = os.listdir(idir)
        except OSError:
            continue
        for n in names:
            if n.startswith("attempt-") and n.endswith(".jsonl"):
                out.append((item, n, os.path.join(idir, n)))
    return out


def _attempt_number(fname):
    """attempt-001.jsonl / attempt-01.jsonl -> 1"""
    core = fname[len("attempt-"):-len(".jsonl")]
    try:
        return int(core)
    except ValueError:
        return None


def _verdict(root, item_id, attempt):
    idir = os.path.join(root, ".autoport", "logs", item_id)
    try:
        names = os.listdir(idir)
    except OSError:
        return "sans-verdict"
    for n in names:
        if not (n.startswith("validator-") and n.endswith(".txt")):
            continue
        core = n[len("validator-"):-len(".txt")]
        try:
            num = int(core)
        except ValueError:
            continue
        if num != attempt:
            continue
        try:
            with open(os.path.join(idir, n), "r", encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            return "sans-verdict"
        ok = any(ln.startswith("[%s ok]" % item_id) for ln in lines)
        fail = any(ln.startswith("[%s FAIL]" % item_id) for ln in lines)
        if ok and not fail:
            return "pass"
        return "fail"
    return "sans-verdict"


def load_attempts(root):
    """Une entree par fichier attempt-*.jsonl reussi a se lire, plus des compteurs de defauts."""
    out = []
    unparsed = []
    unfinished = 0
    without_verdict = 0
    for item_id, fname, path in _attempt_paths(root):
        attempt_num_from_name = _attempt_number(fname)
        start = _read_first_line(path)
        if not isinstance(start, dict) or start.get("event") != "attempt_start":
            unparsed.append(path)
            continue
        attempt = start.get("attempt", attempt_num_from_name)
        result = _last_matching(path, '"type":"result"') or {}
        end = _last_matching(path, '"event":"attempt_end"') or _last_matching(
            path, '"event": "attempt_end"') or {}
        model_usage = result.get("modelUsage") if isinstance(result, dict) else None
        model_usage = model_usage if isinstance(model_usage, dict) else {}
        num_turns = result.get("num_turns") if isinstance(result, dict) else None
        cost_usd = end.get("cost_usd") if isinstance(end, dict) else None
        if cost_usd is None and not model_usage:
            unfinished += 1
        model = start.get("model", "") or ""
        manager_cost = None
        if model and model in model_usage and isinstance(model_usage[model], dict):
            manager_cost = model_usage[model].get("costUSD")
        if manager_cost is None:
            manager_cost = cost_usd if cost_usd is not None else 0.0
        sub_model = start.get("subagent_model", "") or ""
        sub_cost = 0.0
        sub_inseparable = False
        if sub_model and sub_model != model:
            for mid, u in model_usage.items():
                if mid != model and isinstance(u, dict):
                    sub_cost += u.get("costUSD", 0.0) or 0.0
        elif sub_model and sub_model == model:
            sub_inseparable = True
        verdict = _verdict(root, item_id, attempt) if isinstance(attempt, int) else "sans-verdict"
        if verdict == "sans-verdict":
            without_verdict += 1
        started_at = _parse_iso(start.get("started_at", ""))
        out.append({
            "item_id": item_id, "attempt": attempt, "model": model,
            "effort": start.get("effort", "") or "",
            "subagent_model": sub_model,
            "sub_inseparable": sub_inseparable,
            "profile": start.get("profile", "") or "",
            "started_at": started_at,
            "trials": start.get("trials") or {},
            "code_scope": start.get("code_scope", "") or "",
            "manager_cost": manager_cost or 0.0,
            "sub_cost": sub_cost,
            "cost_usd": cost_usd if cost_usd is not None else (manager_cost or 0.0),
            "num_turns": num_turns,
            "verdict": verdict,
            "path": path,
        })
    return out, unparsed, unfinished, without_verdict


def _window(attempts, lo, hi):
    return [a for a in attempts if a["started_at"] is not None and lo < a["started_at"] <= hi]


def _mean(vals):
    return statistics.mean(vals) if vals else None


def _median(vals):
    return statistics.median(vals) if vals else None


def _metrics(items):
    """items: liste d'attempts (dicts) pour un role/cle donne, cost deja choisi par l'appelant
    via la clef 'cost' posee sur chaque item."""
    n = len(items)
    costs = [it["cost"] for it in items]
    validated = sum(1 for it in items if it.get("verdict") == "pass")
    cpv = (sum(costs) / validated) if validated else None
    first = [it for it in items if it.get("attempt") == 1]
    first_pass = sum(1 for it in first if it.get("verdict") == "pass")
    first_rate = (first_pass / len(first)) if first else None
    turns = [it["num_turns"] for it in items if it.get("num_turns") is not None]
    return {
        "attempts": n,
        "cost_total": sum(costs),
        "cost_mean": _mean(costs) if n else None,
        "cost_median": _median(costs) if n else None,
        "validated": validated,
        "cost_per_validated_item": cpv,
        "first_n": len(first),
        "first_pass": first_pass,
        "first_rate": first_rate,
        "turns_mean": _mean(turns) if turns else None,
    }


def build_manager_sub(attempts):
    """(manager_role, sous-agents_role) : {"aggregate":..., "groups": {key: {...}}} par fenetre
    n'existent pas ici, on rend juste les items annotes de leur cout par role/cle pour un appel
    unique de fenetre (voir build_report)."""
    manager = []
    sous = []
    for a in attempts:
        key = "%s @ %s" % (a["model"] or "inconnu", a["effort"] or "inconnu")
        manager.append(dict(a, cost=a["manager_cost"], key=key))
        skey = a["subagent_model"] or "inconnu"
        cost = 0.0 if a["sub_inseparable"] else a["sub_cost"]
        sitem = dict(a, cost=cost, key=skey, inseparable=a["sub_inseparable"])
        sous.append(sitem)
    return manager, sous


def _group_by_key(items):
    groups = {}
    for it in items:
        groups.setdefault(it["key"], []).append(it)
    return groups


def role_block(cur_items, prev_items):
    cur_groups = _group_by_key(cur_items)
    prev_groups = _group_by_key(prev_items)
    keys = sorted(set(cur_groups) | set(prev_groups))
    groups = {}
    for k in keys:
        g = {"cur": _metrics(cur_groups.get(k, [])), "prev": _metrics(prev_groups.get(k, []))}
        if any(it.get("inseparable") for it in cur_groups.get(k, [])):
            g["inseparable"] = True
        groups[k] = g
    aggregate = {"cur": _metrics(cur_items), "prev": _metrics(prev_items)}
    return {"aggregate": aggregate, "groups": groups}


def supervisor_block(root, cur_attempts, prev_attempts, cur_lo, cur_hi, prev_lo, prev_hi):
    sup_launches_path = os.path.join(root, ".autoport", "logs", "supervisor-launches.jsonl")

    def launches_in(lo, hi):
        models = set()
        try:
            with open(sup_launches_path, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        d = json.loads(line)
                    except Exception:                      # noqa: BLE001
                        continue
                    ts = _parse_iso(d.get("ts", ""))
                    if ts is not None and lo < ts <= hi:
                        models.add(d.get("model") or "inconnu")
        except OSError:
            pass
        return models

    sys.path.insert(0, LIB_DIR)
    try:
        import supervisor_cost as sc
        d = sc.charger_cache()
        r = sc.releve(d)
        par_jour = r.get("par_jour", {})
        par_jour_modeles = r.get("par_jour_modeles", {})
        mesurable = True
    except Exception:                                      # noqa: BLE001
        par_jour = {}
        par_jour_modeles = {}
        mesurable = False

    def cost_in(lo, hi):
        if not mesurable:
            return None
        total = 0.0
        day = lo.date()
        end_day = hi.date()
        step = datetime.timedelta(days=1)
        seen_any = False
        d = day
        while d <= end_day:
            key = d.isoformat()
            if key in par_jour:
                total += par_jour[key]
                seen_any = True
            d += step
        return total if seen_any or par_jour else (0.0 if not par_jour else total)

    def models_in(lo, hi):
        """Modeles factures (cout > 0) dans la fenetre, lus jour par jour comme cost_in."""
        models = set()
        day = lo.date()
        end_day = hi.date()
        step = datetime.timedelta(days=1)
        d = day
        while d <= end_day:
            key = d.isoformat()
            for modele, cout_m in (par_jour_modeles.get(key) or {}).items():
                if cout_m and cout_m > 0:
                    models.add(modele)
            d += step
        return models

    def validated_in(attempts_window):
        return len({a["item_id"] for a in attempts_window if a.get("verdict") == "pass"})

    cur_billed = models_in(cur_lo, cur_hi) if mesurable else set()
    prev_billed = models_in(prev_lo, prev_hi) if mesurable else set()
    if cur_billed or prev_billed:
        cur_key = "+".join(sorted(cur_billed)) if cur_billed else "inconnu"
        prev_key = "+".join(sorted(prev_billed)) if prev_billed else "inconnu"
    else:
        cur_models = launches_in(cur_lo, cur_hi)
        prev_models = launches_in(prev_lo, prev_hi)
        cur_key = ("+".join(sorted(cur_models)) if cur_models else "inconnu") + " (registre)"
        prev_key = ("+".join(sorted(prev_models)) if prev_models else "inconnu") + " (registre)"
    cur = {
        "attempts": None, "cost_total": cost_in(cur_lo, cur_hi), "cost_mean": None,
        "cost_median": None, "validated": validated_in(cur_attempts),
        "cost_per_validated_item": None, "first_n": None, "first_pass": None,
        "first_rate": None, "turns_mean": None,
        "key": cur_key,
    }
    prev = {
        "attempts": None, "cost_total": cost_in(prev_lo, prev_hi), "cost_mean": None,
        "cost_median": None, "validated": validated_in(prev_attempts),
        "cost_per_validated_item": None, "first_n": None, "first_pass": None,
        "first_rate": None, "turns_mean": None,
        "key": prev_key,
    }
    for blk in (cur, prev):
        if blk["cost_total"] is not None and blk["validated"]:
            blk["cost_per_validated_item"] = blk["cost_total"] / blk["validated"]
    key = cur["key"]
    groups = {key: {"cur": cur, "prev": prev}}
    if not mesurable:
        groups = {}
    aggregate = {"cur": cur if mesurable else None, "prev": prev if mesurable else None}
    return {"aggregate": aggregate, "groups": groups, "mesurable": mesurable}


def trials_block(root, cur_attempts):
    path = os.path.join(root, ".autoport", "model-profiles.json")
    try:
        cfg = json.loads(open(path, encoding="utf-8").read())
    except Exception:                                      # noqa: BLE001
        return {}
    trials_cfg = cfg.get("trials") or {}
    out = {}
    for name, spec in trials_cfg.items():
        if name.startswith("_"):
            continue
        if not isinstance(spec, dict) or not spec.get("active"):
            continue
        arms = spec.get("arms") or {}
        arm_data = {}
        for arm_label in arms:
            arm_data[arm_label] = []
        # also collect any "hors-essai*" labels actually present in the data
        for a in cur_attempts:
            lbl = (a.get("trials") or {}).get(name)
            if not lbl:
                continue
            if lbl not in arm_data:
                arm_data[lbl] = []
            arm_data[lbl].append(a)
        arm_metrics = {}
        for lbl, items in arm_data.items():
            costs = [it.get("cost_usd", 0.0) for it in items]
            validated = sum(1 for it in items if it.get("verdict") == "pass")
            first = [it for it in items if it.get("attempt") == 1]
            first_pass = sum(1 for it in first if it.get("verdict") == "pass")
            turns = [it["num_turns"] for it in items if it.get("num_turns") is not None]
            arm_metrics[lbl] = {
                "attempts": len(items),
                "validated": validated,
                "cost_total": sum(costs),
                "cost_per_validated_item": (sum(costs) / validated) if validated else None,
                "first_rate": (first_pass / len(first)) if first else None,
                "turns_mean": _mean(turns) if turns else None,
            }
        out[name] = arm_metrics
    return out


def banned_count(root, cur_attempts):
    sys.path.insert(0, LIB_DIR)
    try:
        import model_profile
        spec = model_profile.banned_spec(model_profile.load())
    except Exception:                                      # noqa: BLE001
        return None
    n = 0
    for a in cur_attempts:
        if model_profile.is_banned(a.get("model", ""), spec) or \
           model_profile.is_banned(a.get("subagent_model", ""), spec):
            n += 1
    return n


def build_report(root, days, now):
    attempts, unparsed, unfinished, without_verdict = load_attempts(root)
    cur_hi = now
    cur_lo = now - datetime.timedelta(days=days)
    prev_hi = cur_lo
    prev_lo = now - datetime.timedelta(days=2 * days)

    cur_all = _window(attempts, cur_lo, cur_hi)
    prev_all = _window(attempts, prev_lo, prev_hi)

    cur_mgr, cur_sub = build_manager_sub(cur_all)
    prev_mgr, prev_sub = build_manager_sub(prev_all)

    roles = {
        "manager": role_block(cur_mgr, prev_mgr),
        "sous-agents": role_block(cur_sub, prev_sub),
        "superviseur": supervisor_block(root, cur_all, prev_all, cur_lo, cur_hi, prev_lo, prev_hi),
    }

    trials = trials_block(root, cur_all)

    alerts = []
    for role_name in ("manager", "sous-agents", "superviseur"):
        agg = roles[role_name]["aggregate"]
        c = agg.get("cur")
        p = agg.get("prev")
        if not c or not p:
            continue
        cv = c.get("cost_per_validated_item")
        pv = p.get("cost_per_validated_item")
        if cv is not None and pv is not None and pv > 0 and cv > 1.5 * pv:
            pct = (cv / pv - 1.0) * 100.0
            alerts.append(
                "ALERTE %s : coût par item validé %s $ sur %d j contre %s $ les %d j "
                "d'avant (+%s %%)" % (role_name, _fmt_fr(cv), days, _fmt_fr(pv), days,
                                       _fmt_fr(pct)))

    banned = banned_count(root, cur_all)

    return {
        "now": now.isoformat(),
        "days": days,
        "windows": {
            "cur": [cur_lo.isoformat(), cur_hi.isoformat()],
            "prev": [prev_lo.isoformat(), prev_hi.isoformat()],
        },
        "roles": roles,
        "trials": trials,
        "alerts": alerts,
        "banned_model_attempts": banned,
        "attempts_read": len(attempts),
        "attempts_unparsed": len(unparsed),
        "attempts_unparsed_example": unparsed[0] if unparsed else None,
        "attempts_unfinished": unfinished,
        "attempts_without_verdict": without_verdict,
    }


def _fmt_role_line(role, key, m_cur, m_prev):
    parts = ["  %-12s %-32s" % (role, key)]
    parts.append("essais %-4d" % (m_cur["attempts"] or 0))
    cm = m_cur.get("cost_mean")
    parts.append("coût/essai %s $" % (_fmt_fr(cm) if cm is not None else "-"))
    cpv = m_cur.get("cost_per_validated_item")
    extra = ""
    if cpv is not None and m_prev and m_prev.get("cost_per_validated_item") is not None:
        extra = " (%dj avant : %s $)" % (0, _fmt_fr(m_prev["cost_per_validated_item"]))
    parts.append("coût/item validé %s $%s" % (_fmt_fr(cpv) if cpv is not None else "-", extra))
    fr = m_cur.get("first_rate")
    parts.append("1er essai %s" % ("%d %%" % round(fr * 100) if fr is not None else "-"))
    tm = m_cur.get("turns_mean")
    if tm is not None:
        parts.append("tours %d" % round(tm))
    return "  ".join(parts)


def render_text(rep):
    lines = []
    date_txt = rep["now"][:10]
    lines.append("Coût par modèle et par rôle — %d j glissants (au %s)"
                  % (rep["days"], date_txt))
    days = rep["days"]
    for role_name in ("manager", "sous-agents", "superviseur"):
        block = rep["roles"][role_name]
        groups = block["groups"]
        for key in sorted(groups):
            g = groups[key]
            cur = g["cur"]
            prev = g["prev"]
            if cur is None:
                continue
            line = "  %-12s %-32s essais %-4s coût/essai %s $  coût/item validé %s $" % (
                role_name, key,
                str(cur.get("attempts")) if cur.get("attempts") is not None else "-",
                _fmt_fr(cur["cost_mean"]) if cur.get("cost_mean") is not None else "-",
                _fmt_fr(cur["cost_per_validated_item"]) if cur.get("cost_per_validated_item")
                is not None else "-",
            )
            if prev and prev.get("cost_per_validated_item") is not None:
                line += "  (%d j avant : %s $)" % (days, _fmt_fr(prev["cost_per_validated_item"]))
            fr = cur.get("first_rate")
            if fr is not None:
                line += "  1er essai %d %%" % round(fr * 100)
            tm = cur.get("turns_mean")
            if tm is not None:
                line += "  tours %d" % round(tm)
            if g.get("inseparable"):
                line += "  [cout non separable]"
            lines.append(line)
    lines.append("Essais croisés")
    if rep["trials"]:
        for name, arms in rep["trials"].items():
            lines.append("  %s" % name)
            for arm, m in arms.items():
                cpv = m.get("cost_per_validated_item")
                fr = m.get("first_rate")
                lines.append(
                    "    %-12s essais %-4d validés %-4d coût/item validé %s $  1er essai %s"
                    % (arm, m["attempts"], m["validated"],
                       _fmt_fr(cpv) if cpv is not None else "-",
                       "%d %%" % round(fr * 100) if fr is not None else "-"))
    else:
        lines.append("  aucun essai croisé actif")
    if rep["alerts"]:
        lines.extend(rep["alerts"])
    else:
        lines.append("Aucune alerte (seuil +50 %).")
    lines.append("Modèles bannis dans les essais des %d j : %s"
                  % (days, rep["banned_model_attempts"] if rep["banned_model_attempts"]
                     is not None else "non mesurable"))
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--now", default=None)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    now = _parse_iso(args.now) if args.now else datetime.datetime.now(datetime.timezone.utc)
    if now is None:
        now = datetime.datetime.now(datetime.timezone.utc)

    rep = build_report(args.root, args.days, now)
    if args.json:
        print(json.dumps(rep, indent=2, ensure_ascii=False))
    else:
        print(render_text(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
