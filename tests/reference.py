"""Python twin of mql5/Include/Vitals/VtCore.mqh (+ VtExposure.mqh): trades from deals, periods, gain, floating-drawdown
journal fallback, statistics, open-position summary, exposure. Operation for operation, so the dump of the MetaTrader
code can be compared with tests/check_core.py.

    from reference import Engine, synth_case
    e = Engine(symbol="", magic=-1, comment="", start=0)
    for d in deals: e.add(d)
    out = e.report(now, balance, journal)        # flat dict of every number the card shows

Deal: dict(time, pos, magic, type 'buy'|'sell'|'cash'|'credit', entry 'in'|'out'|'inout'|'outby', volume, profit,
swap, commission, fee, symbol, comment)."""
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# Copyright 2026 Allan Niñal (https://www.allanninal.dev/mql5)
import bisect
import math
import random

EPS = 1e-8
DAY = 86400


# ---- calendar (server clock = whole seconds since 1970; no time zone) ------------------------------------------------
def civil_from_days(z):
    z += 719468
    era = z // 146097
    doe = z - era * 146097
    yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    y = yoe + era * 400
    doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    mp = (5 * doy + 2) // 153
    d = doy - (153 * mp + 2) // 5 + 1
    m = mp + 3 if mp < 10 else mp - 9
    return (y + (1 if m <= 2 else 0), m, d)


def days_from_civil(y, m, d):
    if m <= 2:
        y -= 1
    era = y // 400
    yoe = y - era * 400
    doy = (153 * (m - 3 if m > 2 else m + 9) + 2) // 5 + d - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468


def weekday(day):          # Monday = 0
    return (day + 3) % 7


# ---- points per pip (kind of instrument and digits) ------------------------------------------------------------------
def pip_multiplier(symbol, digits):
    yen_or_silver = "JPY" in symbol or "XAG" in symbol or "SILVER" in symbol
    gold = "XAU" in symbol or "GOLD" in symbol
    if digits in (5, 1) or (digits == 3 and yen_or_silver) or (digits == 2 and gold):
        return 10
    if digits in (6, 2) or (digits == 4 and yen_or_silver) or (digits == 3 and gold):
        return 100
    return 1


# ---- the engine -------------------------------------------------------------------------------------------------------
class Engine:
    def __init__(self, symbol="", magic=-1, comment="", start=0):
        self.f_symbol, self.f_magic, self.f_comment, self.f_start = symbol, magic, comment.lower(), start
        self.open = {}                     # pos -> dict
        self.trades = []
        self.ct = []                       # time of every balance-affecting deal
        self.cc = []                       # running sum of their pnl (cc[i] = sum up to and including i)

    # -- filters
    def pass_pos(self, symbol, magic, comment):
        return ((self.f_symbol == "" or symbol == self.f_symbol) and (self.f_magic < 0 or magic == self.f_magic)
                and (self.f_comment == "" or self.f_comment in comment.lower()))

    # -- one deal, in time order. Returns True when it completed a trade that passes the filters.
    def add(self, d):
        pnl = d["profit"] + d["swap"] + d["commission"] + d["fee"]
        if d["type"] == "credit":
            return False
        total = (self.cc[-1] if self.cc else 0.0) + pnl
        self.ct.append(d["time"])
        self.cc.append(total)
        if d["type"] == "cash":
            return False
        p = self.open.get(d["pos"])
        if d["entry"] == "in":
            if p is None:
                p = self.open[d["pos"]] = dict(magic=d["magic"], symbol=d["symbol"], comment=d["comment"],
                                               open_time=d["time"], vol=0.0, tvol=0.0, net=0.0, comm=0.0, swap=0.0,
                                               fee=0.0)
            p["vol"] += d["volume"]
            p["tvol"] += d["volume"]
        elif p is None:                    # the opening deal is not in the history
            p = self.open[d["pos"]] = dict(magic=d["magic"], symbol=d["symbol"], comment=d["comment"],
                                           open_time=d["time"], vol=d["volume"], tvol=d["volume"], net=0.0, comm=0.0,
                                           swap=0.0, fee=0.0)
        p["net"] += pnl
        p["comm"] += d["commission"]
        p["swap"] += d["swap"]
        p["fee"] += d["fee"]
        closed = False
        rest = 0.0
        if d["entry"] in ("out", "outby"):
            p["vol"] -= d["volume"]
            closed = p["vol"] <= EPS
        elif d["entry"] == "inout":
            rest = d["volume"] - p["vol"]
            closed = True
        if not closed:
            return False
        ok = (self.pass_pos(p["symbol"], p["magic"], p["comment"]) and d["time"] >= self.f_start)
        if ok:
            self.trades.append(dict(open_time=p["open_time"], close_time=d["time"], volume=p["tvol"], net=p["net"],
                                    comm=p["comm"], swap=p["swap"], fee=p["fee"]))
        if d["entry"] == "inout" and rest > EPS:     # the rest opens the other way
            self.open[d["pos"]] = dict(magic=p["magic"], symbol=p["symbol"], comment=p["comment"],
                                       open_time=d["time"], vol=rest, tvol=rest, net=0.0, comm=0.0, swap=0.0, fee=0.0)
        else:
            del self.open[d["pos"]]
        return ok

    # -- balance just before time t: current balance minus every deal at or after t (cash flow included)
    def bal_before(self, t, bal_now):
        i = bisect.bisect_left(self.ct, t)
        before = self.cc[i - 1] if i > 0 else 0.0
        total = self.cc[-1] if self.cc else 0.0
        return bal_now - (total - before)

    # -- every number of the card
    def report(self, now, bal_now, journal):
        o = {}
        T = self.trades
        nowday = now // DAY
        o["ntrades"] = len(T)
        # days with trades (trades are in close order)
        days = []
        for t in T:
            dn = t["close_time"] // DAY
            if not days or days[-1]["day"] != dn:
                days.append(dict(day=dn, n=0, w=0, l=0, net=0.0, lots=0.0, fb=0.0, fbp=0.0, c=0.0, pk=0.0))
            x = days[-1]
            x["n"] += 1
            x["net"] += t["net"]
            x["lots"] += t["volume"]
            if t["net"] > 0:
                x["w"] += 1
            elif t["net"] < 0:
                x["l"] += 1
            x["c"] += t["net"]
            x["pk"] = max(x["pk"], x["c"])
            x["fb"] = min(x["fb"], x["c"] - x["pk"])
        dindex = {x["day"]: i for i, x in enumerate(days)}
        s0 = bal_now
        if T:
            s0 = self.bal_before(min(t["open_time"] for t in T), bal_now)
        o["S0"] = s0
        for x in days:
            x["bal"] = self.bal_before(x["day"] * DAY, bal_now)
            x["fbp"] = 100.0 * x["fb"] / x["bal"] if x["bal"] > 0 else 0.0

        def dd_of(dn):                      # (found, money, pct, approx)
            j = journal.get(dn)
            if j is not None:
                return True, min(j[0], 0.0), min(j[1], 0.0), False
            i = dindex.get(dn)
            if i is not None:
                return True, days[i]["fb"], days[i]["fbp"], True
            return False, 0.0, 0.0, False

        def row(i, kind, a, b):             # calendar days [a, b)
            n = w = l = 0
            net = lots = 0.0
            for x in days:
                if a <= x["day"] < b:
                    n += x["n"]
                    w += x["w"]
                    l += x["l"]
                    net += x["net"]
                    lots += x["lots"]
            bal = self.bal_before(a * DAY, bal_now)
            p = "row.%d." % i
            o[p + "kind"], o[p + "day"] = kind, a
            o[p + "n"], o[p + "w"], o[p + "l"], o[p + "net"], o[p + "lots"] = n, w, l, net, lots
            o[p + "gain_ok"] = 1 if bal > 0 else 0
            o[p + "gain"] = 100.0 * net / bal if bal > 0 else 0.0
            ok, bp, ba = False, 0.0, False
            for dn in range(a, b):
                f, m, pc, ap = dd_of(dn)
                if f and (not ok or pc < bp):
                    ok, bp, ba = True, pc, ap
            o[p + "dd_ok"] = 1 if ok else 0
            o[p + "dd_pct"], o[p + "dd_approx"] = bp, 1 if ba else 0

        rows = [(0, nowday)]
        for x in reversed(days):
            if x["day"] < nowday and len(rows) < 5:
                rows.append((0, x["day"]))
        y, m, _ = civil_from_days(nowday)
        rows.append((1, nowday - weekday(nowday)))
        rows.append((2, days_from_civil(y, m, 1)))
        rows.append((3, days_from_civil(y, 1, 1)))
        for i, (kind, a) in enumerate(rows):
            row(i, kind, a, a + 1 if kind == 0 else nowday + 1)
        o["nrows"] = len(rows)
        # averages and the daily-return series
        r = []                              # (return %, day)
        for x in days:
            if x["bal"] > 0:
                r.append((100.0 * x["net"] / x["bal"], x["day"]))
        o["avg_day_ok"] = 1 if r else 0
        o["avg_day"] = sum(v[0] for v in r) / len(r) if r else 0.0
        months = []                         # (key, net, first day)
        for x in days:
            yy, mm, _ = civil_from_days(x["day"])
            key = yy * 12 + mm
            if not months or months[-1][0] != key:
                months.append([key, 0.0, days_from_civil(yy, mm, 1)])
            months[-1][1] += x["net"]
        mr = []
        for key, net, d1 in months:
            b = self.bal_before(d1 * DAY, bal_now)
            if b > 0:
                mr.append(100.0 * net / b)
        o["avg_month_ok"] = 1 if mr else 0
        o["avg_month"] = sum(mr) / len(mr) if mr else 0.0
        # statistics
        n = len(T)
        gp = gl = 0.0
        w = l = 0
        comm = swp = fee = lots = 0.0
        for t in T:
            lots += t["volume"]
            comm += t["comm"]
            swp += t["swap"]
            fee += t["fee"]
            if t["net"] > 0:
                w += 1
                gp += t["net"]
            elif t["net"] < 0:
                l += 1
                gl += -t["net"]
        o["st.n"], o["st.w"], o["st.l"], o["st.gp"], o["st.gl"] = n, w, l, gp, gl
        o["st.winrate"] = 100.0 * w / n if n else 0.0
        o["st.avgwin"] = gp / w if w else 0.0
        o["st.avgloss"] = -gl / l if l else 0.0
        o["st.rr"] = (gp / w) / (gl / l) if w and l and gl > 0 else 0.0
        o["st.exp"] = (gp - gl) / n if n else 0.0
        o["st.pf_ok"] = 1 if gl > 0 else 0
        o["st.pf"] = gp / gl if gl > 0 else 0.0
        o["st.comm"], o["st.swap"], o["st.fee"], o["st.lots"] = comm, swp, fee, lots
        c = peak = s0
        mdd = mdd_pct = rel = rel_money = 0.0
        mdd_t = rel_t = 0
        for t in T:
            c += t["net"]
            peak = max(peak, c)
            dd = peak - c
            if dd > mdd:
                mdd, mdd_pct, mdd_t = dd, (100.0 * dd / peak if peak > 0 else 0.0), t["close_time"]
            rp = 100.0 * dd / peak if peak > 0 else 0.0
            if rp > rel:
                rel, rel_money, rel_t = rp, dd, t["close_time"]
        o["st.maxdd_money"], o["st.maxdd_pct"], o["st.maxdd_time"] = mdd, mdd_pct, mdd_t
        o["st.rel_pct"], o["st.rel_money"], o["st.rel_time"] = rel, rel_money, rel_t
        rs = [v[0] for v in r if v[1] >= now // DAY - 59]      # last 60 calendar days
        if len(rs) >= 2:
            mean = sum(rs) / len(rs)
            var = sum((v - mean) ** 2 for v in rs) / (len(rs) - 1)
            sd = math.sqrt(var)
            o["st.sharpe_ok"] = 1 if sd > 1e-12 else 0
            o["st.sharpe"] = sum(rs) / sd if sd > 1e-12 else 0.0
        else:
            o["st.sharpe_ok"], o["st.sharpe"] = 0, 0.0
        o["st.best_ok"] = 1 if r else 0
        if r:
            bi = wi = 0
            for i, v in enumerate(r):
                if v[0] > r[bi][0]:
                    bi = i
                if v[0] < r[wi][0]:
                    wi = i
            o["st.best_pct"], o["st.best_day"] = r[bi]
            o["st.worst_pct"], o["st.worst_day"] = r[wi]
        else:
            o["st.best_pct"] = o["st.best_day"] = 0
            o["st.worst_pct"] = o["st.worst_day"] = 0
        o["st.first_day"] = T[0]["close_time"] // DAY if T else 0
        for i, t in enumerate(T):
            p = "trade.%d." % i
            o[p + "close"], o[p + "net"] = t["close_time"], t["net"]
        # days
        o["ndays"] = len(days)
        for i, x in enumerate(days):
            p = "day.%d." % i
            ok, m_, pc, ap = dd_of(x["day"])
            o[p + "day"], o[p + "n"], o[p + "net"], o[p + "bal"] = x["day"], x["n"], x["net"], x["bal"]
            o[p + "dd_money"], o[p + "dd_pct"], o[p + "dd_approx"] = m_, pc, 1 if ap else 0
        # journal-only days are not listed; a one-line summary of the journal
        o["njournal"] = len(journal)
        return o

    # -- open positions (summary and exposure) -----------------------------------------------------------------------
    def positions(self, pos, balance):
        o = {}
        P = [p for p in pos if self.pass_pos(p["symbol"], p["magic"], p["comment"])]
        for name, sel in (("long", lambda p: p["dir"] == 0), ("short", lambda p: p["dir"] == 1), ("total", lambda p: True)):
            n, lots, pl, pips = 0, 0.0, 0.0, 0.0
            for p in P:
                if sel(p):
                    n += 1
                    lots += p["volume"]
                    pl += p["profit"]
                    pips += p["pips"]
            o["open.%s.n" % name], o["open.%s.lots" % name] = n, lots
            o["open.%s.pl" % name], o["open.%s.pips" % name] = pl, pips
        risk, nst = 0.0, 0
        first = ""
        for p in P:
            if p["sl"] > 0:
                risk += p["risk"]
            else:
                nst += 1
                if first == "":
                    first = "%s %s %.2f" % (p["symbol"], "long" if p["dir"] == 0 else "short", p["volume"])
        o["open.risk"] = risk
        o["open.risk_pct"] = 100.0 * risk / balance if balance > 0 else 0.0
        o["open.nostop"] = nst
        o["open.nostop_first"] = first
        ex = {}
        names = []
        for p in P:
            s = 1.0 if p["dir"] == 0 else -1.0
            if p["base"] == p["ccy"]:
                for k, v in ((p["symbol"], s * p["value"]),):
                    if k not in ex:
                        names.append(k)
                    ex[k] = ex.get(k, 0.0) + v
            else:
                for k, v in ((p["base"], s * p["value"]), (p["ccy"], -s * p["value"])):
                    if k not in ex:
                        names.append(k)
                    ex[k] = ex.get(k, 0.0) + v
        rows = sorted(ex.items(), key=lambda kv: (-abs(kv[1]), kv[0]))
        o["open.nex"] = len(rows)
        for i, (k, v) in enumerate(rows):
            o["open.ex.%d.name" % i], o["open.ex.%d.net" % i] = k, v
        return o


# ---- synthetic histories ----------------------------------------------------------------------------------------------
SYMS = [("EURUSD", 5, 1.08), ("GBPJPY", 3, 190.0), ("XAUUSD", 2, 2400.0), ("USDJPY", 3, 150.0), ("US30", 1, 38000.0),
        ("BTCUSD", 2, 60000.0)]
COMMENTS = ["", "", "trend", "scalp 1", "Manual", "[sl 1.0]"]


def synth_case(seed, n_pos=300, magics=(0, 11, 22, 771500), symbols=SYMS, now=None, netting=False, cash=True,
               start_bal=10000.0, span_days=480):
    """(deals, now, balance, journal, positions): deals in time order, 'now' near the end, balance = start + all pnl."""
    rnd = random.Random(seed)
    t_end = now if now is not None else days_from_civil(2026, 10, 21) * DAY + 14 * 3600
    t0 = t_end - span_days * DAY
    ev = []
    for i in range(n_pos):
        m = rnd.choice(magics)
        sym, _dig, _px = rnd.choice(symbols)
        comment = rnd.choice(COMMENTS)
        t = t0 + rnd.randint(0, span_days * DAY - 3 * DAY)
        vol = round(rnd.choice([0.01, 0.02, 0.05, 0.1, 0.3, 1.0]), 2)
        typ = rnd.choice(["buy", "sell"])
        pid = 5000 + i
        ev.append(dict(time=t, pos=pid, magic=m, type=typ, entry="in", volume=vol, profit=0.0, swap=0.0,
                       commission=-round(vol * 3.5, 2), fee=0.0, symbol=sym, comment=comment))
        if rnd.random() < 0.06:
            continue                                         # still open
        parts = rnd.choice([1, 1, 1, 2, 3]) if vol >= 0.03 else 1
        left = vol
        for k in range(parts):
            t += rnd.randint(60, 200_000)
            v = left if k == parts - 1 else round(left / 2, 2)
            left = round(left - v, 2)
            kind = "out"
            if netting and k == parts - 1 and rnd.random() < 0.08:
                kind = "inout"
                v = round(v + rnd.choice([0.01, 0.1]), 2)
            elif rnd.random() < 0.03:
                kind = "outby"
            ev.append(dict(time=t, pos=pid, magic=0 if (m and rnd.random() < 0.15) else m,
                           type="sell" if typ == "buy" else "buy", entry=kind, volume=v,
                           profit=round(rnd.gauss(0.5, 30) * v * 10, 2),
                           swap=round(rnd.gauss(0, 1), 2) if rnd.random() < 0.4 else 0.0,
                           commission=-round(v * 3.5, 2), fee=-0.05 if rnd.random() < 0.05 else 0.0,
                           symbol=sym, comment=rnd.choice(["", "[tp 1.1]", "[sl 1.0]"])))
    if cash:
        ev.append(dict(time=t0 + 100, pos=0, magic=0, type="cash", entry="in", volume=0.0,
                       profit=start_bal, swap=0.0, commission=0.0, fee=0.0, symbol="", comment="deposit"))
        for _ in range(4):
            ev.append(dict(time=t0 + rnd.randint(100, span_days * DAY - 10), pos=0, magic=0, type="cash", entry="in",
                           volume=0.0, profit=round(rnd.choice([-1, 1]) * rnd.uniform(100, 2000), 2), swap=0.0,
                           commission=0.0, fee=0.0, symbol="", comment="transfer"))
        ev.append(dict(time=t0 + rnd.randint(100, span_days * DAY - 10), pos=0, magic=0, type="credit", entry="in",
                       volume=0.0, profit=500.0, swap=0.0, commission=0.0, fee=0.0,
                       symbol="", comment="credit"))
    ev = [e for e in ev if e["time"] <= t_end]
    ev.sort(key=lambda d: (d["time"], d["pos"]))
    bal = start_bal + sum(e["profit"] + e["swap"] + e["commission"] + e["fee"] for e in ev if e["type"] != "credit")
    if cash:
        bal -= start_bal                       # start_bal came in as the deposit deal
    # journal: some recent days, some old
    journal = {}
    nd = t_end // DAY
    for dd in range(nd - 60, nd + 1):
        if rnd.random() < 0.55:
            mny = -round(rnd.uniform(0, 400), 2) if rnd.random() < 0.9 else 0.0
            journal[dd] = (mny, round(mny / 10000.0 * 100.0, 4))
    # open positions
    positions = []
    for _ in range(rnd.randint(0, 6)):
        sym, dig, px = rnd.choice(symbols)
        base = sym[:3] if len(sym) == 6 else sym
        ccy = sym[3:] if len(sym) == 6 else sym
        d = rnd.choice([0, 1])
        v = round(rnd.choice([0.1, 0.3, 0.6]), 2)
        has = rnd.random() < 0.7
        positions.append(dict(symbol=sym, magic=rnd.choice(magics), comment=rnd.choice(COMMENTS), dir=d, volume=v,
                              profit=round(rnd.gauss(0, 60), 2), pips=round(rnd.gauss(0, 25), 1),
                              sl=px * 0.99 if has else 0.0, risk=-round(rnd.uniform(20, 200), 2) if has else 0.0,
                              value=round(v * rnd.uniform(5000, 120000), 2), base=base, ccy=ccy))
    return ev, t_end, round(bal, 2), journal, positions
