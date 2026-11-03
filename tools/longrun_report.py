#!/usr/bin/env python3
"""Summary of tests/longrun_test.gd CSVs: per-phase curves (days 1-10, 11-30, 31-40) and outliers.

    python tools/longrun_report.py build/longrun*.csv

Per file: the header line (seed, mode, result), a table per phase (mean of the stocks / people / morale, the change of the
running totals over the phase, the max save size), then the outliers: death spikes, stocks at 0, the collapse day.
With several files, a last table averages each phase over all of them.
"""
import csv
import statistics
import sys

PHASES = [("1-10", 1, 10), ("11-30", 11, 30), ("31-40", 31, 40)]
MEAN = ["scrap", "metal", "parts", "electronics", "food", "water", "fuel", "ammo", "people", "injured", "morale", "base_hp", "outposts", "garrison", "villages", "trucks", "late"]
DELTA = ["deaths", "kills", "points", "delivered", "village_supply", "convoys_sent", "convoys_back", "convoys_lost", "wrecks_hooked",
         "repaired", "missions_done", "missions_failed", "outposts_fell", "villages_fell", "events", "boss_kills", "trade_spent", "trade_got"]
ZERO = ["food", "water", "fuel", "ammo"]
SPIKE_MIN = 3  # deaths in one day below this are never a spike


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def read(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    head = " ".join(l[1:].strip() for l in lines if l.startswith("#"))
    rows = list(csv.DictReader(l for l in lines if l and not l.startswith("#")))
    return head, rows


def phase_rows(rows, a, b):
    return [r for r in rows if a <= int(r["day"]) <= b]


def summary(rows):
    """{phase: {column: value}} for one run."""
    out = {}
    for name, a, b in PHASES:
        ph = phase_rows(rows, a, b)
        if not ph:
            continue
        before = [r for r in rows if int(r["day"]) < a]
        s = {"days": len(ph)}
        for c in MEAN:
            vals = [num(r.get(c)) for r in ph if num(r.get(c)) is not None]
            if vals:
                s[c] = statistics.mean(vals)
        for c in DELTA:
            if c in ph[0] and num(ph[-1][c]) is not None:
                s["+" + c] = num(ph[-1][c]) - (num(before[-1][c]) if before else 0.0)
        sizes = [num(r.get("save_bytes")) for r in ph if num(r.get("save_bytes"))]
        if sizes:
            s["save_kb_max"] = max(sizes) / 1024.0
        out[name] = s
    return out


def outliers(head, rows, days_wanted):
    out = []
    deaths = [num(r["deaths"]) for r in rows]
    daily = [d - (deaths[i - 1] if i else 0.0) for i, d in enumerate(deaths)]
    if len(daily) > 2:
        mu, sd = statistics.mean(daily), statistics.pstdev(daily)
        for r, d in zip(rows, daily):
            if d >= SPIKE_MIN and d > mu + 2 * sd:
                out.append("day %s: death spike %d (mean %.1f)" % (r["day"], d, mu))
    for c in ZERO:
        zero = [r["day"] for r in rows if num(r.get(c)) is not None and num(r[c]) <= 0]
        if zero:
            out.append("%s at 0 on %d day(s): %s" % (c, len(zero), ",".join(zero[:12]) + (" ..." if len(zero) > 12 else "")))
    last = int(rows[-1]["day"]) if rows else 0
    if "COLLAPSED" in head or last < days_wanted:
        out.append("COLLAPSE after day %d (%s)" % (last, head.split("result", 1)[-1].strip() if "result" in head else "no result line"))
    return out


def table(title, summ):
    cols = ["days"] + MEAN + ["+" + c for c in DELTA] + ["save_kb_max"]
    cols = [c for c in cols if any(c in s for s in summ.values())]
    print(title)
    print("  %-17s" % "column" + "".join("%11s" % p for p, _, _ in PHASES if p in summ))
    for c in cols:
        print("  %-17s" % c + "".join("%11s" % ("%.1f" % summ[p][c] if c in summ[p] else "-") for p, _, _ in PHASES if p in summ))


def selftest():
    """python tools/longrun_report.py --selftest"""
    rows = [{"day": str(d), "deaths": str(10 if d > 5 else 0), "food": str(0 if d == 3 else 50), "save_bytes": str(1000 * d)} for d in range(1, 13)]
    s = summary(rows)
    assert s["1-10"]["days"] == 10 and s["11-30"]["days"] == 2 and s["1-10"]["+deaths"] == 10 and s["11-30"]["+deaths"] == 0, s
    o = outliers("seed 1 days 40 result COLLAPSED x", rows, 40)
    assert any("spike" in x and "day 6" in x for x in o) and any("food at 0" in x for x in o) and any("COLLAPSE after day 12" in x for x in o), o
    print("selftest OK")
    return 0


def main(paths):
    if paths == ["--selftest"]:
        return selftest()
    if not paths:
        print(__doc__)
        return 2
    all_s = []
    for path in paths:
        head, rows = read(path)
        if not rows:
            print("%s: no rows" % path)
            continue
        want = int(head.split("days", 1)[1].split()[0]) if " days " in " " + head else 40
        s = summary(rows)
        all_s.append(s)
        table("%s  [%s]" % (path, head), s)
        for o in outliers(head, rows, want):
            print("  ! " + o)
        print()
    if len(all_s) > 1:
        avg = {}
        for p, _, _ in PHASES:
            runs = [s[p] for s in all_s if p in s]
            if runs:
                keys = set().union(*runs)
                avg[p] = {k: statistics.mean(r[k] for r in runs if k in r) for k in keys}
        table("MEAN over %d runs" % len(all_s), avg)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
