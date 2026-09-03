#!/usr/bin/env python3
"""gdp_analyze.py — Ggrass-density-presets : les lignes de preuve, tirees des COURSES.

Ce script ne DECIDE rien. Il lit les journaux que la campagne a produits et en extrait les
grandeurs que le validateur exige, en publiant a cote de chaque verdict le materiau qui l'a fait
(nombre de lignes lues, fichiers). Une ligne qu'aucune course n'a produite ne sort pas d'ici : elle
manque, et le validateur le dira.
"""
import glob
import os
import re
import subprocess
import sys

OUT = ".autoport/reports/Ggrass-density-presets"
FR3 = "out/jak1/fr3"
SLUGS = ["very-low", "low", "medium", "high", "very-high"]
PCT = {"very-low": 50, "low": 100, "medium": 150, "high": 200, "very-high": 250}


def verdict(tag):
    p = f"{OUT}/{tag}.verdict"
    if not os.path.exists(p):
        return {}
    return dict(re.findall(r"(\w+)=([^\s]+)", open(p).read()))


def place_lines(tag):
    p = f"{OUT}/{tag}.log"
    if not os.path.exists(p):
        return []
    return [
        dict(re.findall(r"(\w+)=([^\s]+)", l))
        for l in re.findall(r"^.*PLACE-TIME .*$", open(p, errors="replace").read(), re.M)
    ]


def main():
    lines = []
    A = lines.append

    # ---- 1. GRASSPRESET : un bake par palier, relu sur le fichier livre -----------------------
    fr3_size = os.path.getsize(f"{FR3}/training.fr3")
    for sg in SLUGS:
        f = f"{FR3}/training.{sg}.grassbake"
        if not os.path.exists(f):
            A(f"# MANQUE {f}")
            continue
        hdr = subprocess.run(
            ["python3", "scripts/shell/grassbake_header.py", f], capture_output=True, text=True
        ).stdout
        d = dict(re.findall(r"(\w+)=([^\s]+)", hdr))
        A(
            "GRASSPRESET palier={} niveau={} bake_octets={} fr3_size={} densite_pct={} ncand={}".format(
                sg, d.get("niveau"), os.path.getsize(f), d.get("fr3_size"), d.get("densite"),
                d.get("ncand"),
            )
        )

    # ---- 2. GRASSLIVE : combien de courses, combien ont bascule en direct ----------------------
    courses = 0
    basculements = 0
    couverts = set()
    for sg in SLUGS:
        pl = place_lines(f"p-{sg}")
        v = verdict(f"p-{sg}")
        # une COURSE = un chargement du niveau a herbe demande dans la jambe
        courses += int(v.get("cycles_atteints", 0))
        for d in pl:
            if d.get("mode") == "live":
                basculements += 1
            if d.get("palier_servi") == sg:
                couverts.add(sg)
    A(
        "GRASSLIVE courses={} basculements_en_direct={} paliers_couverts={} lignes_place_time={}".format(
            courses, basculements, len(couverts),
            sum(len(place_lines(f"p-{s}")) for s in SLUGS),
        )
    )

    # ---- 3. GRASSMEM : le pic RSS, par palier, contre la ligne de base du chemin direct --------
    base = verdict("en-direct")
    if base:
        A(
            "GRASSMEM palier=en-direct rss_max_mo={:.1f} instances={} place_ms={}".format(
                int(base["rss_max_kb"]) / 1024.0,
                (place_lines("en-direct") or [{}])[0].get("instances", "?"),
                re.sub(r"ms$", "", (place_lines("en-direct") or [{}])[0].get("total", "?")),
            )
        )
    for sg in SLUGS:
        v = verdict(f"p-{sg}")
        pl = place_lines(f"p-{sg}")
        if not v:
            A(f"# MANQUE verdict p-{sg}")
            continue
        A(
            "GRASSMEM palier={} rss_max_mo={:.1f} instances={} place_ms={} densite_bake={}".format(
                sg, int(v["rss_max_kb"]) / 1024.0,
                (pl or [{}])[0].get("instances", "?"),
                re.sub(r"ms$", "", (pl or [{}])[0].get("total", "?")),
                (pl or [{}])[0].get("densite_bake", "?"),
            )
        )

    # ---- 4. GRASSPACK : recompte sur le zip livre ----------------------------------------------
    zp = "android/app/src/jak1/assets-slim/bundle/jak1_custom.zip"
    if os.path.exists(zp):
        listing = subprocess.run(["unzip", "-Z1", zp], capture_output=True, text=True).stdout
        n = len([l for l in listing.splitlines() if l.endswith(".grassbake")])
        A(f"GRASSPACK bakes_dans_le_pack={n} zip={zp} octets={os.path.getsize(zp)}")
    else:
        A(f"# MANQUE le pack {zp}")

    # ---- 5. GRASSBEACH : le cout de la plage, avant et apres son retrait -----------------------
    beach_legs = [("avant", "avant-beach"), ("apres", "apres-beach")]
    for extra in sorted(glob.glob(f"{OUT}/apres-beach[0-9].verdict")):
        beach_legs.append(("apres-repetition", os.path.basename(extra)[: -len(".verdict")]))
    for etat, tag in beach_legs:
        v = verdict(tag)
        pl = place_lines(tag)
        if not v:
            A(f"# MANQUE verdict {tag}")
            continue
        A(
            "GRASSBEACH etat={} jambe={} rss_max_mo={:.1f} brins={} place_ms={} chargements={}".format(
                etat, tag, int(v["rss_max_kb"]) / 1024.0,
                (pl or [{}])[0].get("instances", "0"),
                re.sub(r"ms$", "", (pl or [{}])[0].get("total", "0")),
                v.get("cycles_atteints", "?"),
            )
        )

    print("\n".join(lines))


if __name__ == "__main__":
    sys.exit(main())
