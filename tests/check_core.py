"""VtCore.mqh / VtExposure.mqh / VtJournal.mqh against tests/reference.py.

    python3 tests/check_core.py write <dir>      # cases for the dump tool (files folder, sub-folder vttest) + journal paths
    python3 tests/check_core.py check <dir>      # compare out_<k>.txt, out_pip.txt, journal_out.txt with the twin
Cases (CASES) cover hedging and netting (reversals), partial closes, cash flow and credit, commissions/swap/fee, the
filters (symbol, magic, comment, start date), 'now' on a Monday, the 1st of a month, 1 January and a Sunday, an empty
history and a 3,000-position one. Every number of the card is compared with 1e-9 relative tolerance."""
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# Copyright 2026 Allan Niñal (https://www.allanninal.dev/mql5)
import csv
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from reference import DAY, Engine, days_from_civil, pip_multiplier, synth_case  # noqa: E402

COLS = ["time", "pos", "magic", "type", "entry", "volume", "profit", "swap", "commission", "fee", "symbol", "comment"]


def at(y, m, d, h=0, mi=0, s=0):
    return days_from_civil(y, m, d) * DAY + h * 3600 + mi * 60 + s


CASES = [
    dict(name="hedging, plain", kw=dict(seed=1)),
    dict(name="netting reversals", kw=dict(seed=2, n_pos=800, netting=True)),
    dict(name="filter symbol", kw=dict(seed=3, n_pos=500), f=dict(symbol="XAUUSD")),
    dict(name="filter magic+comment", kw=dict(seed=4, n_pos=900), f=dict(magic=11, comment="SCALP")),
    dict(name="now Monday 00:00:05", kw=dict(seed=5, now=at(2026, 10, 19, 0, 0, 5), n_pos=600)),
    dict(name="now 1 Nov (month start)", kw=dict(seed=6, now=at(2026, 11, 1), n_pos=600, netting=True)),
    dict(name="now 1 Jan (year start)", kw=dict(seed=7, now=at(2027, 1, 1, 0, 0, 1), n_pos=700)),
    dict(name="start-date filter", kw=dict(seed=8, n_pos=700), f=dict(start=at(2026, 3, 1))),
    dict(name="empty history", kw=dict(seed=9, n_pos=0, cash=False)),
    dict(name="Sunday, 3000 positions", kw=dict(seed=10, n_pos=3000, now=at(2026, 10, 18, 22), netting=True,
                                                 magics=tuple(range(30)))),
    dict(name="no cash flow", kw=dict(seed=11, n_pos=400, cash=False)),
]
PIPS = [("EURUSD", 5), ("EURUSD", 4), ("USDJPY", 3), ("USDJPY", 2), ("XAUUSD", 2), ("XAUUSD", 3), ("GOLD", 2),
        ("XAGUSD", 3), ("XAGUSD", 4), ("SILVER", 3), ("US30", 1), ("US30", 2), ("GER40", 1), ("BTCUSD", 2),
        ("BTCUSD", 0), ("XAUEUR", 2), ("AUDNZD", 6), ("EURUSD.m", 5), ("GBPJPY", 4)]


def build(k):
    return synth_case(**CASES[k]["kw"])


def run_twin(deals, now, bal, journal, positions, f):
    e = Engine(symbol=f.get("symbol", ""), magic=f.get("magic", -1), comment=f.get("comment", ""),
               start=f.get("start", 0))
    for d in deals:
        e.add(d)
    o = e.report(now, bal, journal)
    o.update(e.positions(positions, bal))
    return o


def write(out: Path):
    out.mkdir(parents=True, exist_ok=True)
    for k, c in enumerate(CASES):
        deals, now, bal, journal, positions = build(k)
        f = c.get("f", {})
        with open(out / f"deals_{k}.csv", "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(COLS)
            for d in deals:
                w.writerow([repr(d[x]) if isinstance(d[x], float) else d[x] for x in COLS])
        with open(out / f"meta_{k}.csv", "w", newline="") as fh:
            fh.write("key,value\n")
            fh.write(f"now,{now}\nbalance,{bal!r}\nf_symbol,{f.get('symbol', '')}\nf_magic,{f.get('magic', -1)}\n")
            fh.write(f"f_comment,{f.get('comment', '')}\nf_start,{f.get('start', 0)}\n")
        with open(out / f"jr_{k}.csv", "w", newline="") as fh:
            fh.write("day,money,pct\n")
            for dn in sorted(journal):
                fh.write(f"{dn},{journal[dn][0]!r},{journal[dn][1]!r}\n")
        with open(out / f"pos_{k}.csv", "w", newline="") as fh:
            fh.write("symbol,magic,comment,dir,volume,profit,pips,sl,risk,value,base,ccy\n")
            for p in positions:
                fh.write(",".join(str(p[x]) if not isinstance(p[x], float) else repr(p[x]) for x in
                                  ("symbol", "magic", "comment", "dir", "volume", "profit", "pips", "sl", "risk", "value",
                                   "base", "ccy")) + "\n")
    with open(out / "pip_test.csv", "w") as fh:
        fh.write("symbol,digits\n")
        for s, dg in PIPS:
            fh.write(f"{s},{dg}\n")
    write_journal(out)
    print(f"wrote {len(CASES)} cases to {out}")


# ---- compare ------------------------------------------------------------------------------------------------------------
def parse_out(p: Path):
    r = {}
    for line in p.read_text().splitlines():
        if "\t" in line:
            k, v = line.split("\t", 1)
            r[k] = v
    return r


def same(a, b):
    try:
        x, y = float(a), float(b)
    except (TypeError, ValueError):
        return str(a) == str(b)
    return abs(x - y) <= 1e-9 * max(1.0, abs(x), abs(y))


def diff(mt, ref):
    bad = []
    for k in sorted(set(mt) | set(ref)):
        if k not in mt:
            bad.append(f"{k}: missing in the terminal (twin {ref[k]})")
        elif k not in ref:
            bad.append(f"{k}: missing in twin (the terminal {mt[k]})")
        elif not same(mt[k], ref[k]):
            bad.append(f"{k}: the terminal {mt[k]} vs twin {ref[k]}")
    return bad


def check(d: Path):
    bad_total = 0
    for k, c in enumerate(CASES):
        p = d / f"out_{k}.txt"
        if not p.exists():
            print(f"case {k} ({c['name']}): out file missing")
            bad_total += 1
            continue
        deals, now, bal, journal, positions = build(k)
        ref = run_twin(deals, now, bal, journal, positions, c.get("f", {}))
        mt = parse_out(p)
        bad = diff(mt, ref)
        print(f"case {k:2} {c['name']:26} deals {len(deals):5} trades {ref['ntrades']:5} values compared {len(ref):6}  "
              f"{'OK' if not bad else 'MISMATCH ' + str(len(bad))}")
        for b in bad[:6]:
            print("     ", b)
        bad_total += len(bad)
    pip = parse_out(d / "out_pip.txt")
    pbad = [f"pip.{i}: {pip.get(f'pip.{i}')} vs {pip_multiplier(s, dg)} ({s},{dg})" for i, (s, dg) in enumerate(PIPS)
            if not same(pip.get(f"pip.{i}"), pip_multiplier(s, dg))]
    print(f"pip table {len(PIPS)} symbols: {'OK' if not pbad else 'MISMATCH'}")
    for b in pbad:
        print("     ", b)
    bad_total += len(pbad)
    print("ALL PASS: 0 mismatches" if not bad_total else f"FAILURES: {bad_total} mismatches")
    return bad_total == 0


# ---- the journal ---------------------------------------------------------------------------------------------------------
class JModel:
    """Python twin of CVtJournal (and the file): memory dict day -> (money, pct); 'file' = list of lines."""
    def __init__(self, files, name, ms):
        self.files, self.name = files, name
        self.mem = {}
        self.dirty = False
        self.last = ms
        for dn, m, p in self.read():
            self.put(dn, m, p)
        self.dirty = False

    def read(self):
        out = []
        for line in self.files.get(self.name, []):
            v = line.split(",")
            if len(v) >= 3 and int(v[0]) > 0:
                out.append((int(v[0]), min(float(v[1]), 0.0), min(float(v[2]), 0.0)))
        return out

    def put(self, dn, m, p):
        if dn in self.mem:
            if m < self.mem[dn][0]:
                self.mem[dn] = (m, p)
                return True
            return False
        self.mem[dn] = (m, p)
        return True

    def sample(self, t, eq, bal, ms):
        day = t // DAY
        money = round(min(eq - bal, 0.0), 2)
        pct = round(money / bal * 100.0 if bal > 0 else 0.0, 4)
        if self.put(day, money, pct):
            self.dirty = True
        if self.dirty and ms - self.last >= 10000:
            self.flush(False, ms)

    def flush(self, force, ms):
        if not self.dirty:
            return
        if not force and ms - self.last < 10000:
            return
        self.last = ms
        for dn, m, p in self.read():
            self.put(dn, m, p)
        self.files[self.name] = ["%d,%.2f,%.4f" % (dn, self.mem[dn][0], self.mem[dn][1]) for dn in sorted(self.mem)]
        self.dirty = False


def journal_script():
    """(seed file lines, [(kind, t, eq, bal, ms)]): midnight crossings, clean and crash restarts, a restart across
    midnight, a three-day gap, a flat day, another chart having written a deeper low."""
    rnd = random.Random(77)
    d0 = days_from_civil(2026, 10, 19)
    seed = ["%d,%.2f,%.4f" % (d0 - 2, -120.5, -1.205), "%d,%.2f,%.4f" % (d0 - 1, 0.0, 0.0),
            "%d,%.2f,%.4f" % (d0, -35.0, -0.35)]
    steps = []
    t = d0 * DAY + 23 * 3600 + 50 * 60
    ms = 5000
    bal = 10000.0
    eq = bal
    for i in range(900):                             # 15 minutes across midnight
        eq = round(bal + rnd.gauss(-20, 60) if rnd.random() < 0.7 else bal + rnd.uniform(0, 80), 2)
        steps.append(("S", t, eq, bal, ms))
        t += 1
        ms += 1000
        if i in (200, 640):
            steps.append(("R", t, 0, 0, ms))         # clean restart
        if i in (400, 700):
            steps.append(("C", t, 0, 0, ms))         # crash restart (no flush)
        if i == 450:
            bal = 10110.33                           # a deposit/close changed the balance
    # restart across midnight and a three-day gap
    steps.append(("C", t, 0, 0, ms))
    t += 3 * DAY + 4000
    ms += 7000
    for i in range(60):
        eq = round(bal - rnd.uniform(0, 300), 2)
        steps.append(("S", t, eq, bal, ms))
        t += 1
        ms += 500                                    # faster than 1 s: throttle matters
    steps.append(("R", t, 0, 0, ms))
    t += 100
    for i in range(30):                              # a flat day: equity never under the balance
        steps.append(("S", t + DAY, bal + rnd.uniform(0, 50), bal, ms))
        t += 1
        ms += 1000
    return seed, steps


def write_journal(out: Path):
    seed, steps = journal_script()
    (out / "jt_seed.csv").write_text("day,money,pct\n" + "\n".join(seed) + "\n")
    with open(out / "jt_paths.csv", "w", newline="") as fh:
        fh.write("kind,time,equity,balance,ms\n")
        for k, t, eq, bal, ms in steps:
            fh.write(f"{k},{t},{eq!r},{bal!r},{ms}\n")


def check_journal(d: Path):
    p = d / "journal_out.txt"
    if not p.exists():
        print("journal: journal_out.txt missing")
        return False
    seed, steps = journal_script()
    files = {"f": list(seed)}
    j = JModel(files, "f", 0)
    snaps, n = [], 0
    for k, t, eq, bal, ms in steps:
        if k == "S":
            j.sample(t, eq, bal, ms)
        else:
            if k == "R":
                j.flush(True, ms)
            j = JModel(files, "f", ms)
            snaps.append(("%d" % n, list(files["f"])))
            n += 1
    j.flush(True, 4000000000)
    snaps.append(("final", list(files["f"])))
    mem = ["%d,%.2f,%.4f" % (dn, j.mem[dn][0], j.mem[dn][1]) for dn in sorted(j.mem)]
    exp = []
    for tag, lines in snaps:
        exp += ["SNAP " + tag] + lines
    exp += ["MEM"] + mem
    got = [x for x in p.read_text().splitlines() if x]
    ok = got == exp
    nsamples = sum(1 for s in steps if s[0] == "S")
    nrestarts = len(steps) - nsamples
    print(f"journal: {nsamples} samples, {nrestarts} restarts, {len(mem)} days; compared {len(exp)} lines: "
          f"{'OK, 0 mismatches' if ok else 'MISMATCH'}")
    if not ok:
        for i, (a, b) in enumerate(zip(got, exp)):
            if a != b:
                print("   first difference at line", i, ": the terminal", a, "| twin", b)
                break
        if len(got) != len(exp):
            print("   line counts: the terminal", len(got), "twin", len(exp))
    return ok


if __name__ == "__main__":
    mode, d = sys.argv[1], Path(sys.argv[2])
    if mode == "write":
        write(d)
    elif mode == "check":
        ok = check(d)
        ok = check_journal(d) and ok if (d / "journal_out.txt").exists() else ok
        sys.exit(0 if ok else 1)
    elif mode == "journal":
        sys.exit(0 if check_journal(d) else 1)
