#!/usr/bin/env python3
"""Grass placement analyzer for Goverhang4.

Analyzes grass_bake --dump instance/tri CSVs. numpy only.
Instance classes are decoded from nspare; metrics measure row-periodicity
(spacing), tip-plane clipping (overhang), and seam continuity across tri edges.
"""
import argparse
import sys
import math
import numpy as np

U = 4096.0
TILT = 0.30
NOFF = 0.03 * U
PLANE_CLEAR = 0.02 * U


def dsl(nx, ny, nz):
    """In-plane down-slope unit vector from a surface normal. None if flat."""
    h2 = 1.0 - ny * ny
    if h2 < 1e-6:
        return None
    r = math.sqrt(h2)
    return np.array([nx * ny, ny * ny - 1.0, nz * ny]) / r


def load_instances(path):
    # idx,px,py,pz,h,yaw,tint,curve,phase,gspare,nx,ny,nz,nspare,tri
    return np.loadtxt(path, delimiter=",", skiprows=1)


def load_tris(path):
    # idx,p0x,p0y,p0z,e1x,e1y,e1z,e2x,e2y,e2z,nx,ny,nz,flags,area_m2
    return np.loadtxt(path, delimiter=",", skiprows=1)


# ---- column indices ----
I_PX, I_PY, I_PZ, I_H, I_YAW, I_TINT, I_CURVE, I_PHASE, I_GSP = 1, 2, 3, 4, 5, 6, 7, 8, 9
I_NX, I_NY, I_NZ, I_NSP, I_TRI = 10, 11, 12, 13, 14

T_P0X, T_P0Y, T_P0Z = 1, 2, 3
T_E1X, T_E1Y, T_E1Z = 4, 5, 6
T_E2X, T_E2Y, T_E2Z = 7, 8, 9
T_NX, T_NY, T_NZ = 10, 11, 12


def tri_p0(tris, ti):
    return tris[ti, T_P0X:T_P0Z + 1]


def tri_e1(tris, ti):
    return tris[ti, T_E1X:T_E1Z + 1]


def tri_e2(tris, ti):
    return tris[ti, T_E2X:T_E2Z + 1]


def tri_n(tris, ti):
    return tris[ti, T_NX:T_NZ + 1]


def classify(inst, gen):
    """Return dict class-name -> (row-index array, w array or None)."""
    nsp = inst[:, I_NSP]
    out = {}
    if gen == 3:
        droop = np.where((nsp > 1.5) & (nsp < 2.5))[0]
        twins = np.where((nsp > 2.5) & (nsp < 4.5))[0]
        comb = np.where(nsp < -0.5)[0]
        out["droop"] = (droop, None)
        out["twins"] = (twins, nsp[twins] - 3.0)
        out["comb"] = (comb, -nsp[comb] - 1.0)
    else:
        droop = np.where((nsp > 1.5) & (nsp < 2.5))[0]
        comb = np.where(nsp > 4.5)[0]
        out["droop"] = (droop, None)
        out["comb"] = (comb, nsp[comb] - 5.0)
    return out


# =====================================================================
# METRIC 1 - SPACING
# =====================================================================
def metric_spacing(inst, tris, cls):
    droop_idx = cls["droop"][0]
    if droop_idx.size == 0:
        print("G4METRIC spacing_hist_peak_ratio=0")
        print("G4METRIC spacing_hist_peak_at=0")
        print("G4METRIC spacing_pairs=0")
        return
    # group droop by tri
    tri_of = inst[droop_idx, I_TRI].astype(np.int64)
    order = np.argsort(tri_of, kind="stable")
    droop_sorted = droop_idx[order]
    tri_sorted = tri_of[order]

    nbins = 50  # 0.02 m over [0,1.0]
    binw = 0.02
    hist = np.zeros(nbins, dtype=np.int64)
    total_pairs = 0

    # iterate contiguous groups
    start = 0
    n = tri_sorted.size
    while start < n:
        end = start
        t = tri_sorted[start]
        while end < n and tri_sorted[end] == t:
            end += 1
        members = droop_sorted[start:end]
        start = end
        if members.size < 8:
            continue
        u = dsl(tri_n(tris, t)[0], tri_n(tris, t)[1], tri_n(tris, t)[2])
        if u is None:
            continue
        p0 = tri_p0(tris, t)
        pos = inst[members][:, I_PX:I_PZ + 1]
        s = (pos - p0) @ u / U  # meters
        s = np.sort(s)
        # pairwise |s_i - s_j|, i<j
        # vectorized: diffs
        diffs = np.abs(s[:, None] - s[None, :])
        iu = np.triu_indices(s.size, k=1)
        d = diffs[iu]
        total_pairs += d.size
        # histogram over [0,1.0)
        bi = np.floor(d / binw).astype(np.int64)
        m = (bi >= 0) & (bi < nbins)
        np.add.at(hist, bi[m], 1)

    # peak bin in [0.20, 0.36]
    def bin_range(lo, hi):
        return int(math.floor(lo / binw)), int(math.floor(hi / binw))

    plo, phi = bin_range(0.20, 0.36)
    peak_region = hist[plo:phi + 1]
    if peak_region.size == 0:
        peak_val = 0
        peak_bin = plo
    else:
        rel = int(np.argmax(peak_region))
        peak_val = int(peak_region[rel])
        peak_bin = plo + rel
    peak_center = (peak_bin + 0.5) * binw

    # median over nonzero bins in [0.06, 1.0]
    mlo, mhi = bin_range(0.06, 1.0)
    med_region = hist[mlo:mhi + 1]
    nz = med_region[med_region > 0]
    if nz.size == 0:
        median = 0.0
    else:
        median = float(np.median(nz))
    if median <= 0:
        ratio = 0.0
    else:
        ratio = peak_val / median

    print(f"G4METRIC spacing_hist_peak_ratio={ratio:.4f}")
    print(f"G4METRIC spacing_hist_peak_at={peak_center:.4f}")
    print(f"G4METRIC spacing_pairs={total_pairs}")


# =====================================================================
# grid helpers
# =====================================================================
def build_tri_grid(tris, cell):
    """XZ grid hash: cell coord -> list of tri idx. Insert into every cell
    the tri's XZ AABB overlaps."""
    grid = {}
    n = tris.shape[0]
    for ti in range(n):
        p0 = tri_p0(tris, ti)
        e1 = tri_e1(tris, ti)
        e2 = tri_e2(tris, ti)
        xs = [p0[0], p0[0] + e1[0], p0[0] + e2[0]]
        zs = [p0[2], p0[2] + e1[2], p0[2] + e2[2]]
        cx0 = int(math.floor(min(xs) / cell))
        cx1 = int(math.floor(max(xs) / cell))
        cz0 = int(math.floor(min(zs) / cell))
        cz1 = int(math.floor(max(zs) / cell))
        for cx in range(cx0, cx1 + 1):
            for cz in range(cz0, cz1 + 1):
                grid.setdefault((cx, cz), []).append(ti)
    return grid


def barycentric_inside(proj, p0, e1, e2):
    """Solve proj = p0 + a*e1 + b*e2 via 2x2 normal equations; inside test."""
    d = proj - p0
    a11 = e1 @ e1
    a12 = e1 @ e2
    a22 = e2 @ e2
    b1 = e1 @ d
    b2 = e2 @ d
    det = a11 * a22 - a12 * a12
    if abs(det) < 1e-9:
        return False
    a = (b1 * a22 - b2 * a12) / det
    b = (a11 * b2 - a12 * b1) / det
    return (a >= -0.02) and (b >= -0.02) and (a + b <= 1.04)


# =====================================================================
# METRIC 2 - TIP-PLANE violations
# =====================================================================
def compute_tip(row, w, gen, cls_name):
    pos = row[I_PX:I_PZ + 1]
    h = row[I_H]
    yaw = row[I_YAW]
    curve = row[I_CURVE]
    nxyz = row[I_NX:I_NZ + 1]
    fwdv = np.array([math.sin(yaw), 0.0, math.cos(yaw)])

    if gen == 3:
        if cls_name == "droop":
            # nxyz IS dsl
            return pos + nxyz * h + np.array([0.0, -0.15 * h, 0.0]), pos, None
        if cls_name == "twins":
            tip = pos + fwdv * ((1 - w) * curve * h + w * 0.6 * h) + \
                np.array([0.0, (1 - w) * h + w * 0.25 * h, 0.0])
            return tip, pos, None
        if cls_name == "comb":
            n = nxyz  # face normal
            dv = dsl(n[0], n[1], n[2])
            if dv is None:
                return None, pos, None
            axis = np.array([n[0] * TILT, 1.0, n[2] * TILT]) * (1 - w) + dv * w
            tip = pos + axis * h + fwdv * curve * h * (1 - 0.6 * w)
            return tip, pos, None
    else:
        if cls_name == "comb":
            n = nxyz  # smooth normal
            dv = dsl(n[0], n[1], n[2])
            if dv is None:
                return None, pos, None
            axis = np.array([n[0] * TILT, 1.0, n[2] * TILT]) * (1 - w) + dv * w
            base_r = pos + n * NOFF * w
            tip0 = base_r + axis * h + fwdv * curve * h * (1 - 0.6 * w)
            db = (tip0 - pos) @ n
            if db < 0:
                return tip0 - n * db, pos, n
            return tip0, pos, n
        if cls_name == "droop":
            n = nxyz  # smooth normal
            dv = dsl(n[0], n[1], n[2])
            if dv is None:
                return None, pos, None
            tip0 = pos + n * NOFF + dv * h
            db = (tip0 - pos) @ n
            if db < 0:
                return tip0 - n * db, pos, n
            return tip0, pos, n
    return None, pos, None


def metric_tips(inst, tris, cls, gen):
    grid = build_tri_grid(tris, 2.0 * U)
    if gen == 3:
        classes = ["droop", "twins", "comb"]
    else:
        classes = ["droop", "comb"]

    for cname in classes:
        idxs, ws = cls[cname]
        count = idxs.size
        viol = 0
        for k in range(count):
            ri = idxs[k]
            row = inst[ri]
            w = ws[k] if ws is not None else 0.0
            tip, pos, _ = compute_tip(row, w, gen, cname)
            if tip is None:
                continue
            host = int(row[I_TRI])
            cx = int(math.floor(tip[0] / (2.0 * U)))
            cz = int(math.floor(tip[2] / (2.0 * U)))
            hit = False
            seen = set()
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for ti in grid.get((cx + dx, cz + dz), ()):
                        if ti == host or ti in seen:
                            continue
                        seen.add(ti)
                        p0 = tri_p0(tris, ti)
                        nT = tri_n(tris, ti)
                        sd_base = (pos - p0) @ nT
                        if sd_base < -PLANE_CLEAR:
                            continue
                        sd_tip = (tip - p0) @ nT
                        if sd_tip >= -PLANE_CLEAR:
                            continue
                        proj = tip - nT * sd_tip
                        e1 = tri_e1(tris, ti)
                        e2 = tri_e2(tris, ti)
                        if barycentric_inside(proj, p0, e1, e2):
                            hit = True
                            break
                    if hit:
                        break
                if hit:
                    break
            if hit:
                viol += 1
        rate = (viol / count) if count else 0.0
        label = cname
        print(f"G4METRIC tip_violations_{label}={viol} of={count} rate={rate:.4f}")


# =====================================================================
# METRIC 3 - SEAM continuity
# =====================================================================
def comb_axis(row, w, gen):
    n = row[I_NX:I_NZ + 1]
    dv = dsl(n[0], n[1], n[2])
    if dv is None:
        return None
    axis = np.array([n[0] * TILT, 1.0, n[2] * TILT]) * (1 - w) + dv * w
    nrm = np.linalg.norm(axis)
    if nrm < 1e-9:
        return None
    return axis / nrm


def build_pt_grid(pts, cell):
    grid = {}
    for i in range(pts.shape[0]):
        cx = int(math.floor(pts[i, 0] / cell))
        cz = int(math.floor(pts[i, 2] / cell))
        grid.setdefault((cx, cz), []).append(i)
    return grid


def percentile_or_zero(arr, p):
    if len(arr) == 0:
        return 0.0
    return float(np.percentile(arr, p))


def metric_seam(inst, tris, cls, gen):
    comb_idx, comb_w = cls["comb"]
    if comb_idx.size == 0:
        print("G4METRIC seam_pairs=0")
        print("G4METRIC seam_dw_max=0 G4METRIC seam_dw_p99=0")
        print("G4METRIC seam_axis_deg_max=0 G4METRIC seam_axis_deg_p99=0")
        print("G4METRIC boundary_w_max=0")
        return

    cpos = inst[comb_idx][:, I_PX:I_PZ + 1]
    ctri = inst[comb_idx, I_TRI].astype(np.int64)
    caxis = []
    for k in range(comb_idx.size):
        ax = comb_axis(inst[comb_idx[k]], comb_w[k], gen)
        caxis.append(ax)

    cell = 0.5 * U
    thr = 0.06 * U
    grid = build_pt_grid(cpos, cell)

    dws = []
    angs = []
    seen_pairs = set()
    for i in range(comb_idx.size):
        cx = int(math.floor(cpos[i, 0] / cell))
        cz = int(math.floor(cpos[i, 2] / cell))
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for j in grid.get((cx + dx, cz + dz), ()):
                    if j <= i:
                        continue
                    if ctri[i] == ctri[j]:
                        continue
                    d = cpos[i] - cpos[j]
                    if d @ d > thr * thr:
                        continue
                    dws.append(abs(comb_w[i] - comb_w[j]))
                    ai, aj = caxis[i], caxis[j]
                    if ai is not None and aj is not None:
                        dot = float(np.clip(ai @ aj, -1.0, 1.0))
                        angs.append(math.degrees(math.acos(dot)))
    seam_pairs = len(dws)
    print(f"G4METRIC seam_pairs={seam_pairs}")
    print(f"G4METRIC seam_dw_max={(max(dws) if dws else 0.0):.4f} "
          f"G4METRIC seam_dw_p99={percentile_or_zero(dws, 99):.4f}")
    print(f"G4METRIC seam_axis_deg_max={(max(angs) if angs else 0.0):.4f} "
          f"G4METRIC seam_axis_deg_p99={percentile_or_zero(angs, 99):.4f}")

    # TAG BOUNDARY check: comb blades with an untagged (nspare==0) neighbor <0.06m
    nsp_all = inst[:, I_NSP]
    walk_idx = np.where(np.abs(nsp_all) < 1e-6)[0]
    wpos = inst[walk_idx][:, I_PX:I_PZ + 1]
    wgrid = build_pt_grid(wpos, cell)
    boundary_w_max = 0.0
    for i in range(comb_idx.size):
        cx = int(math.floor(cpos[i, 0] / cell))
        cz = int(math.floor(cpos[i, 2] / cell))
        found = False
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for gj in wgrid.get((cx + dx, cz + dz), ()):
                    d = cpos[i] - wpos[gj]
                    if d @ d <= thr * thr:
                        found = True
                        break
                if found:
                    break
            if found:
                break
        if found and comb_w[i] > boundary_w_max:
            boundary_w_max = comb_w[i]
    print(f"G4METRIC boundary_w_max={boundary_w_max:.4f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--instances", required=True)
    ap.add_argument("--tris", required=True)
    ap.add_argument("--gen", type=int, choices=[3, 4], required=True)
    args = ap.parse_args()

    inst = load_instances(args.instances)
    tris = load_tris(args.tris)
    if inst.ndim == 1:
        inst = inst.reshape(1, -1)
    if tris.ndim == 1:
        tris = tris.reshape(1, -1)

    cls = classify(inst, args.gen)
    for cn, (idxs, _) in cls.items():
        print(f"G4METRIC class_{cn}_count={idxs.size}", file=sys.stderr)

    metric_spacing(inst, tris, cls)
    metric_tips(inst, tris, cls, args.gen)
    metric_seam(inst, tris, cls, args.gen)


if __name__ == "__main__":
    main()
