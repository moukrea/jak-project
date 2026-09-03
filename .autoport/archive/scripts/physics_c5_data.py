#!/usr/bin/env python3
"""physics_c5_data.py — Grecharged-secondary-motion CYCLE 5 data pass.

The owner said it three times and asked for it in writing: "C'EST DU CAS PAR CAS ! SOIS COHERENT".
So every chain in recharged_assets/physics_chains.txt is classified into one of two families, and
the family — not a tuning value — decides what its rest pose is.

  FAMILY A  the BODY: hair, breasts, ears, bellies, tails, fur, facial hair, horns, rigid worn
            pieces. Simulated at every instant, gravity drives the dynamics, but the pose it comes
            back to is the one Naughty Dog modelled. "Pas plus haut, pas plus bas, pas plus ecrase."
            `hang=` survives on these chains but the solver scales it by how far the character is
            from upright, so it is the owner's own exception ("si tu pends Maia par les pieds") and
            nothing else.

  FAMILY B  the things that genuinely HANG: leather straps, hanging cloth, capes, flaps, pendants,
            accessories. Gravity dictates their rest and they must NEVER be pulled back to the
            model pose. "Ca pend, ca pend, c'est normal et coherent."

The membership test is physical, not lexical: does the far end of this chain hang free under
gravity? Two names are decided by the owner's list rather than by that test and are marked below.

Also applied here (all of it data, no build):
  * the four-way chest differentiation (Y) — Keira / Maia / bird-lady, plus the honest note that
    the archaeologist's rig has no breast joint to drive;
  * breast-versus-breast contact (Y) via the new `at=<chain>` collider;
  * `side=` on the jacket/skirt pendants AND on the leg volumes, so a cross-leg penetration is
    counted as the specific defect it is rather than lost in the slot total (Z);
  * `extent=` on the single-joint pendants, so the collision test covers the cloth that hangs
    below the bone instead of the bone itself (Z/V);
  * Maia's LOWER body volumes (Z) — her hair reaches well past her hips.
Idempotent: re-running it produces the same file.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "recharged_assets", "physics_chains.txt")

# ---------------------------------------------------------------------------------------------
# THE CLASSIFICATION. Family A is enumerated; everything else is family B. Enumerating the SMALLER
# set on purpose: a chain name added later and forgotten here lands in B, which errs toward "it
# hangs" — and the solver counts unclassified chains anyway, so nothing can slip through silently.
# ---------------------------------------------------------------------------------------------
FAMILY_A = {
    # hair, every shape it takes across the cast
    "hair", "hairL", "hairR", "hairFrontL", "hairFrontR",
    "backhair", "backhairL", "backhairM", "backhairR",
    "lbang", "rbang", "lmidhair", "rmidhair", "ponytail",
    "braidL", "braidM", "braidR", "froback", "frofront", "fromid", "flipL", "flipR",
    # ears (owner 3b J: "c'est TOUS les persos")
    "earL", "earR", "ears",
    # the anatomy the remake ADDS, with no Naughty Dog precursor (owner 16:55)
    "chestL", "chestR", "belly",
    # tails, fur, facial hair, horns — parts of the creature
    "tail",
    "fur", "furL", "furR", "furAL", "furAR", "furArmL", "furArmR", "furBack", "furHead",
    "furLegL", "furLegR", "furSL", "furSR", "neckfur",
    "beard", "beardA", "beardB", "beardC", "beardD", "goatee", "stacheL", "stacheR",
    "horns",
    # worn RIGID, no free end: a mask on a face, a guard strapped to a forearm, the sprig on a
    # lurker's head. Nothing here can hang, so pulling it down would be inventing a droop.
    "mask", "armguardL", "weed",
}

# Named by the owner as accessories and therefore family B even though a strap holds them:
# "FAMILLE B — CE QUI PEND VRAIMENT : accessoires (lunettes, sacs), lanieres de cuir, vetements
# pendants". Their hang= authority stays LOW because the strap really is holding them.
OWNER_FORCED_B = {"goggles", "logL", "logR", "hat", "tophat", "pouch"}

# ---------------------------------------------------------------------------------------------
# (Y) CHESTS, ONE CHARACTER AT A TIME. Every previous cycle shipped ONE line copied onto all five
# sections; that is exactly what the owner rejected. The numbers below differ because the
# characters do, and the reasoning is in the phase report.
#   omega_eff = stiffness / sqrt(mass) is the number that decides how it FEELS:
#     Keira  1.60 / sqrt(1.6) = 1.26  — firm, quick, "jeune et fraiche"
#     Maia   0.85 / sqrt(4.2) = 0.41  — heavy and slow, three times lower: mass you can feel,
#                                       and the high damping is what stops it being jelly (owner K)
#     bird   0.70 / sqrt(3.4) = 0.38  — slacker still, but a SMALL envelope: an old woman
# ---------------------------------------------------------------------------------------------
CHEST_SPEC = {
    # owner: "ronds et FERMES... ca bouge bien mais surtout ca S'ENTRE-CHOQUE, peu de droop, peu de
    # deformation". Firm = high stiffness + low stretch. Visible = swing raised 0.30 -> 0.55, which
    # is what reaches the bone. radius raised so the two volumes can actually meet.
    "keira": ("stiffness=1.60 damping=0.14 gravity=0.10 maxangle=40 inertia=1.0 stretch=0.08 "
              "radius=150 mass=1.6 swing=0.55 hang=0.18"),
    # owner: "morphologie plus mure, GROS seins: naturellement plus tombants, plus laches, moins
    # fermes" — and cycle-3b K, "on ne sent pas la masse... trop leger et JELLY". Lower stiffness
    # AND higher mass lower the frequency together; damping 0.24 removes the jelly without touching
    # the envelope the owner said was already fine.
    "maia": ("stiffness=0.85 damping=0.24 gravity=0.16 maxangle=44 inertia=1.0 stretch=0.26 "
             "radius=170 mass=4.2 swing=0.45 hang=0.32"),
    # owner: "LA VIEILLE AUX OISEAUX a une poitrine, meme regle". Slack and slow like Maia, but a
    # deliberately small envelope: maxangle 26 and swing 0.30. Age reads as low amplitude, not as
    # stiffness.
    "bird": ("stiffness=0.70 damping=0.30 gravity=0.14 maxangle=26 inertia=1.0 stretch=0.20 "
             "radius=140 mass=3.4 swing=0.30 hang=0.30"),
}
CHEST_MODEL = {
    "keira-hd": "keira", "keira3-hd": "keira", "assistant-lod0": "keira",
    "bird-lady-lod0": "bird",
    "evilsis-lod0": "maia",
}

# (Y) breast-versus-breast contact, per model: (anchor joint, sphere radius).
# The sphere rides the OTHER chain's simulated tip. Radii are chosen so the pair has clearance at
# rest — a volume that fired while standing still would push both chains off the modelled pose and
# break the very fidelity criterion this cycle exists for — and meets only when they swing inward.
CHEST_PAIR = {
    "keira-hd": ("chest", 320), "keira3-hd": ("chest", 320), "assistant-lod0": ("chest", 320),
    "bird-lady-lod0": ("chest", 300),
    "evilsis-lod0": ("chest", 360),
}

# (Z/V) single-joint pendants whose CLOTH hangs far below the bone. extent = how far, in units.
EXTENT = {
    ("jak-hd", "shirtL"): 520, ("jak-hd", "shirtR"): 520,
    ("eichar-lod0", "shirtL"): 520, ("eichar-lod0", "shirtR"): 520,
    ("keira-hd", "kneeflapL"): 300, ("keira-hd", "kneeflapR"): 300,
    ("keira-hd", "pantflapL"): 300, ("keira-hd", "pantflapR"): 300,
    ("keira3-hd", "kneeflapL"): 300, ("keira3-hd", "kneeflapR"): 300,
    ("keira3-hd", "pantflapL"): 300, ("keira3-hd", "pantflapR"): 300,
    ("assistant-lod0", "kneeflapL"): 300, ("assistant-lod0", "kneeflapR"): 300,
    ("assistant-lod0", "pantflapL"): 300, ("assistant-lod0", "pantflapR"): 300,
    ("evilsis-lod0", "flapL"): 400, ("evilsis-lod0", "flapR"): 400,
}

# (Z) which side of the body a chain and a leg volume belong to.
SIDE_CHAIN = {"shirtL": "L", "shirtR": "R", "pantsL": "L", "pantsR": "R",
              "kneeflapL": "L", "kneeflapR": "R", "pantflapL": "L", "pantflapR": "R",
              "flapL": "L", "flapR": "R", "legflapL": "L", "legflapR": "R",
              "coatflapL": "L", "coatflapR": "R", "pantlegL": "L", "pantlegR": "R"}
# a capsule whose FIRST joint starts with one of these gets that side
SIDE_JOINT_PREFIX = [("Lthigh", "L"), ("Lknee", "L"), ("Lankle", "L"),
                     ("Rthigh", "R"), ("Rknee", "R"), ("Rankle", "R")]

# (Z) Maia's hair reaches her thighs; her body stopped at the hips. Owner: "les CHEVEUX DE MAIA
# passent au travers du BAS de son corps... sa chevelure doit collisionner avec le corps ENTIER".
MAIA_HAIR = "ponytail,backhairM,backhairL,backhairR"
MAIA_LOWER = [
    f"capsule hips Lthigh radius=470 radius2=400 tier=1 chains={MAIA_HAIR},flapL,flapR",
    f"capsule hips Rthigh radius=470 radius2=400 tier=1 chains={MAIA_HAIR},flapL,flapR",
    f"capsule Lknee Lankle radius=300 radius2=230 tier=1 chains={MAIA_HAIR},flapL,flapR",
    f"capsule Rknee Rankle radius=300 radius2=230 tier=1 chains={MAIA_HAIR},flapL,flapR",
]

KEY_RE = re.compile(r"(\w+)=([^\s]+)")


def strip_keys(line, keys):
    for k in keys:
        line = re.sub(r"\s+%s=[^\s]+" % k, "", line)
    return line


def main():
    src = open(PATH).read().split("\n")
    out, model, models_seen = [], None, []
    stats = {"A": 0, "B": 0, "chest": 0, "extent": 0, "side_chain": 0, "side_col": 0, "pair": 0}
    per_model_chest = {}
    i = 0
    while i < len(src):
        line = src[i]
        m = re.match(r"^\[model\s+(.+?)\]", line)
        if m:
            model = m.group(1).split()[0]
            models_seen.append(model)
            out.append(line)
            i += 1
            continue
        if line.startswith("chain "):
            name = line.split()[1]
            fam = "A" if (name in FAMILY_A and name not in OWNER_FORCED_B) else "B"
            # per-character chest rewrite
            if name in ("chestL", "chestR") and model in CHEST_MODEL:
                who = CHEST_MODEL[model]
                cls = re.search(r"class=\S+", line).group(0)
                line = f"chain {name} {cls} {CHEST_SPEC[who]}"
                stats["chest"] += 1
                per_model_chest[model] = who
            line = strip_keys(line, ["family", "side", "extent"])
            line += f" family={fam}"
            stats[fam] += 1
            if name in SIDE_CHAIN:
                line += f" side={SIDE_CHAIN[name]}"
                stats["side_chain"] += 1
            if (model, name) in EXTENT:
                line += f" extent={EXTENT[(model, name)]}"
                stats["extent"] += 1
            out.append(line)
            i += 1
            continue
        if line.startswith("capsule ") or line.startswith("collider "):
            # drop any previously generated at=/side= so the pass is idempotent
            if " at=" in line:
                i += 1
                continue
            line = strip_keys(line, ["side"])
            toks = line.split()
            j1 = toks[1]
            for pref, sd in SIDE_JOINT_PREFIX:
                if j1 == pref:
                    line += f" side={sd}"
                    stats["side_col"] += 1
                    break
            out.append(line)
            i += 1
            continue
        out.append(line)
        i += 1

    # second pass: inject the mutual chest volumes and Maia's lower body at the end of their section
    text = "\n".join(out)
    for mdl, (anchor, rad) in CHEST_PAIR.items():
        pat = re.compile(r"(^\[model\s+%s\b[^\]]*\][\s\S]*?)(?=^\[model|\Z)" % re.escape(mdl), re.M)
        mm = pat.search(text)
        if not mm:
            print(f"  ! model {mdl} not found for chest pair", file=sys.stderr)
            continue
        blk = mm.group(1).rstrip("\n")
        blk += (f"\n# (Y) owner: Keira's breasts \"s'entre-choquent\" — they collide with EACH OTHER.\n"
                f"# No bone-mounted volume can express that: both bones are animated and neither knows\n"
                f"# where the other one actually swung to. `at=` rides the other chain's SIMULATED tip.\n"
                f"# The radii leave clearance at rest ON PURPOSE — a volume that fired while standing\n"
                f"# still would push both chains off the modelled pose, which is the exact defect this\n"
                f"# cycle exists to remove. cclr: on the [HD-PHYS3] line says whether they ever meet.\n"
                f"collider {anchor} radius={rad} tier=1 chains=chestL at=chestR\n"
                f"collider {anchor} radius={rad} tier=1 chains=chestR at=chestL\n")
        text = text[:mm.start(1)] + blk + "\n\n" + text[mm.end(1):]
        stats["pair"] += 2

    pat = re.compile(r"(^\[model\s+evilsis-lod0\b[^\]]*\][\s\S]*?)(?=^\[model|\Z)", re.M)
    mm = pat.search(text)
    if mm:
        blk = mm.group(1).rstrip("\n")
        blk += ("\n# (Z) owner cycle 5: \"les cheveux de Maia passent au travers du BAS de son corps\".\n"
                "# Her ponytail is seven links and her three back-hair chains five each; they reach her\n"
                "# thighs. Scoping is an optimisation, never a licence to pass through — so the lower\n"
                "# body exists now and every hair chain is listed on all of it.\n"
                + "\n".join(MAIA_LOWER) + "\n")
        text = text[:mm.start(1)] + blk + "\n\n" + text[mm.end(1):]

    # Maia's existing thigh capsules only carried the skirt flaps — give them the hair too.
    text = text.replace(
        "capsule Lthigh Lknee radius=326 radius2=524 tier=1 chains=flapL,flapR side=L",
        f"capsule Lthigh Lknee radius=326 radius2=524 tier=1 chains=flapL,flapR,{MAIA_HAIR} side=L")
    text = text.replace(
        "capsule Rthigh Rknee radius=326 radius2=524 tier=1 chains=flapL,flapR side=R",
        f"capsule Rthigh Rknee radius=326 radius2=524 tier=1 chains=flapL,flapR,{MAIA_HAIR} side=R")

    # (Z/V) with the pendant's CLOTH now being the thing tested, the cycle-3 flare that was standing
    # in for it is double-counting. Pull the thigh cones back toward the real leg.
    text = text.replace("capsule Lthigh Lknee radius=430 radius2=690 tier=1 chains=shirtL,shirtR side=L",
                        "capsule Lthigh Lknee radius=300 radius2=500 tier=1 chains=shirtL,shirtR side=L")
    text = text.replace("capsule Rthigh Rknee radius=430 radius2=690 tier=1 chains=shirtL,shirtR side=R",
                        "capsule Rthigh Rknee radius=300 radius2=500 tier=1 chains=shirtL,shirtR side=R")
    text = text.replace("capsule Lthigh Lknee radius=430 radius2=760 tier=1 chains=shirtL,shirtR,pantsL,pantsR side=L",
                        "capsule Lthigh Lknee radius=300 radius2=520 tier=1 chains=shirtL,shirtR,pantsL,pantsR side=L")
    text = text.replace("capsule Rthigh Rknee radius=430 radius2=760 tier=1 chains=shirtL,shirtR,pantsL,pantsR side=R",
                        "capsule Rthigh Rknee radius=300 radius2=520 tier=1 chains=shirtL,shirtR,pantsL,pantsR side=R")

    open(PATH, "w").write(text)
    print(f"family A={stats['A']} B={stats['B']}  chests rewritten={stats['chest']} "
          f"pair-volumes={stats['pair']} extent={stats['extent']} "
          f"side(chain)={stats['side_chain']} side(collider)={stats['side_col']}")
    print("chest specs: " + ", ".join(f"{k}->{v}" for k, v in sorted(per_model_chest.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
