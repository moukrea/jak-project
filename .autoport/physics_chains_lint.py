#!/usr/bin/env python3
"""physics_chains_lint.py — Grecharged-secondary-motion WAVE 2 data gate.

Every stock-cast chain in recharged_assets/physics_chains.txt is declared by JOINT NAME against a
rig we do not author: the shipped jak1 art files. A single mistyped name does not crash anything —
the chain is simply resolved to nothing at runtime and the character silently has no physics. The
only honest way to catch that for the WHOLE cast is to check the names against the rigs themselves,
offline, instead of hoping a play-through happens to visit every level.

Source of truth: decompiler/config/jak1/ntsc_v1/joint-node-info.min.json — the decompiler's own
art-joint-geo reader output, keyed by joint-geo name ("sage-lod0-jg"), listing every joint name of
every rig the game ships. That is the same key the runtime rider uses ((-> draw jgeo name)), so a
name that passes here is a name the rig really has.

Checks, for every `[model ...]` section that is not one of our own `-hd` companion rigs:
  1. every alias name in the header is a real rig;
  2. every `j <joint>` line names a joint that rig actually has;
  3. every `collider`/`capsule` joint likewise;
  4. every name in a `chains=` filter is a chain declared in that same model;
  5. no joint is claimed by two chains of the same model (the runtime keeps only one role per name);
  6. per-model chain and joint counts fit the sim pools (24 chains / 48 joints).
Exit 0 = clean. Exit 1 = at least one error, all of them printed.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAINS = os.path.join(ROOT, "recharged_assets", "physics_chains.txt")
RIGS = os.path.join(ROOT, "decompiler", "config", "jak1", "ntsc_v1", "joint-node-info.min.json")

MAX_CHAINS = 24  # PHYS-CPS
MAX_JOINTS = 48  # PHYS-JPS


def main() -> int:
    with open(RIGS) as f:
        rigs = {name: {j[1] for j in joints} for name, joints in json.load(f).items()}

    errors, warnings, models, checked_joints = [], [], 0, 0
    header, aliases, chains, order = None, [], {}, []
    colliders = []  # (line_no, [joints], [chain filters])
    cur = None

    def flush():
        """validate the section that just ended"""
        nonlocal models, checked_joints
        if header is None:
            return
        # `-hd` sections describe OUR generated companion rigs; ND's dump knows nothing about them.
        # Everything else is keyed the way the RUNTIME names a joint-geo, which is the plain LOD
        # name — `(-> draw jgeo name)` reads "sage-lod0", measured on a live boot. The decompiler
        # dump disambiguates the elements of an art group by appending -jg / -mg, so the lookup
        # here has to add the suffix back. Getting this wrong is invisible at build time and shows
        # up only as a character with no physics, which is exactly why it is gated.
        if header.endswith("-hd"):
            return
        models += 1
        if (header + "-jg") not in rigs:
            errors.append(f"[model {header}] is not a rig shipped by the game")
            return
        have = rigs[header + "-jg"]
        for alias in aliases:
            if (alias + "-jg") not in rigs:
                errors.append(f"[model {header}] alias '{alias}' is not a rig shipped by the game")
        seen = {}
        for cname in order:
            for ln, jname in chains[cname]:
                checked_joints += 1
                if jname not in have:
                    errors.append(f"{header}:{ln} chain '{cname}' names joint '{jname}' — not in this rig")
                elif jname in seen:
                    errors.append(f"{header}:{ln} joint '{jname}' is claimed by both '{seen[jname]}' and '{cname}'")
                else:
                    seen[jname] = cname
                # An ALIAS rig is a level variant of the same character and usually differs by a
                # prop or two (Keira loses her torch outside the village). A joint the variant does
                # not have is not an error — the runtime drops that chain and says so — but it is
                # not something to discover on the owner's screen either, so it is reported.
                for alias in aliases:
                    if (alias + "-jg") in rigs and jname in have and jname not in rigs[alias + "-jg"]:
                        warnings.append(f"{header}:{ln} joint '{jname}' is absent from variant '{alias}' "
                                        f"— chain '{cname}' will be dropped there")
        for ln, cjoints, cfilter in colliders:
            for jname in cjoints:
                checked_joints += 1
                if jname not in have:
                    errors.append(f"{header}:{ln} collider joint '{jname}' — not in this rig")
            for cn in cfilter:
                if cn not in chains:
                    errors.append(f"{header}:{ln} chains= names '{cn}', which this model does not declare")
        if len(order) > MAX_CHAINS:
            errors.append(f"[model {header}] {len(order)} chains > {MAX_CHAINS} (PHYS-CPS)")
        njoints = sum(len(v) for v in chains.values())
        if njoints > MAX_JOINTS:
            errors.append(f"[model {header}] {njoints} sim joints > {MAX_JOINTS} (PHYS-JPS)")

    with open(CHAINS) as f:
        for ln, raw in enumerate(f, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            tok = line.split()
            if tok[0] == "[levels]":
                flush()
                header, aliases, chains, order, colliders, cur = None, [], {}, [], [], None
            elif tok[0] == "[model":
                flush()
                names = [t.rstrip("]") for t in tok[1:] if t.rstrip("]")]
                header = names[0] if names else None
                aliases, chains, order, colliders, cur = names[1:], {}, [], [], None
            elif tok[0] == "chain" and header:
                cur = tok[1]
                if cur in chains:
                    errors.append(f"{header}:{ln} duplicate chain name '{cur}'")
                chains[cur] = []
                order.append(cur)
                # CYCLE 5 (owner, third repetition: "C'EST DU CAS PAR CAS"). Classification is
                # MANDATORY, and it is checked here rather than only at runtime because an
                # unclassified chain does not crash — it silently inherits family A's behaviour, and
                # a hanging strap that quietly returns to its modelled pose is exactly as wrong as a
                # drooping breast. The runtime counts them too (unclass= on [HD-PHYS4]); this is the
                # check that fails BEFORE a build is spent.
                fam = [t[len("family="):] for t in tok[2:] if t.startswith("family=")]
                if not fam:
                    errors.append(f"{header}:{ln} chain '{cur}' declares no family= "
                                  f"(A = body, returns to the model pose; B = hangs, gravity rules)")
                elif fam[0] not in ("A", "B"):
                    errors.append(f"{header}:{ln} chain '{cur}' family='{fam[0]}' — must be A or B")
            elif tok[0] == "j" and header:
                if cur is None:
                    errors.append(f"{header}:{ln} 'j {tok[1]}' outside any chain")
                else:
                    chains[cur].append((ln, tok[1]))
            elif tok[0] in ("collider", "capsule") and header:
                njoint = 1 if tok[0] == "collider" else 2
                cjoints = [t for t in tok[1:1 + njoint] if "=" not in t]
                cfilter = []
                for t in tok[1:]:
                    if t.startswith("chains="):
                        cfilter = [c for c in t[len("chains="):].split(",") if c]
                colliders.append((ln, cjoints, cfilter))
    flush()

    for w in warnings:
        print(f"[phys-lint WARN] {w}")
    for e in errors:
        print(f"[phys-lint FAIL] {e}")
    print(f"[phys-lint] {models} stock rig section(s), {checked_joints} joint name(s) checked "
          f"against {len(rigs)} shipped rigs, {len(errors)} error(s), {len(warnings)} variant warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
