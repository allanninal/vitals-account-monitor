//+------------------------------------------------------------------+
//|                                                       VtDump.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test helper (not used by the indicator): writes every number the |
//| card shows as "key<TAB>value" lines, the format                  |
//| tests/check_core.py compares with its Python twin.               |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef VTDUMP_MQH
#define VTDUMP_MQH
#include <Vitals/VtCore.mqh>
#include <Vitals/VtExposure.mqh>

int g_out=INVALID_HANDLE;

void W(const string k,const double v)  { FileWriteString(g_out,StringFormat("%s\t%.17g\n",k,v)); }
void WI(const string k,const long v)   { FileWriteString(g_out,StringFormat("%s\t%I64d\n",k,v)); }
void WS(const string k,const string v) { FileWriteString(g_out,k+"\t"+v+"\n"); }

int TypeOf(const string s)  { return(s=="buy" ? VT_T_BUY : (s=="sell" ? VT_T_SELL : (s=="cash" ? VT_T_CASH : VT_T_CREDIT))); }
int EntryOf(const string s) { return(s=="in" ? VT_IN : (s=="out" ? VT_OUT : (s=="inout" ? VT_INOUT : VT_OUTBY))); }

void DumpEngine(CVtEngine &e,const long now,const double bal,const long &jd[],const double &jm[],const double &jp[],const int jn)
  {
   e.Report(now,bal,jd,jm,jp,jn);
   WI("ntrades",e.ntr);
   W("S0",e.s0);
   for(int i=0; i<e.nrows; i++)
     {
      string p=StringFormat("row.%d.",i);
      WI(p+"kind",e.rows[i].kind); WI(p+"day",e.rows[i].day);
      WI(p+"n",e.rows[i].n); WI(p+"w",e.rows[i].w); WI(p+"l",e.rows[i].l);
      W(p+"net",e.rows[i].net); W(p+"lots",e.rows[i].lots);
      WI(p+"gain_ok",e.rows[i].gain_ok); W(p+"gain",e.rows[i].gain);
      WI(p+"dd_ok",e.rows[i].dd_ok); W(p+"dd_pct",e.rows[i].dd_pct);
      WI(p+"dd_approx",e.rows[i].dd_approx);
     }
   WI("nrows",e.nrows);
   WI("avg_day_ok",e.avg_day_ok); W("avg_day",e.avg_day);
   WI("avg_month_ok",e.avg_month_ok); W("avg_month",e.avg_month);
   WI("st.n",e.st.n); WI("st.w",e.st.w); WI("st.l",e.st.l); W("st.gp",e.st.gp); W("st.gl",e.st.gl);
   W("st.winrate",e.st.winrate); W("st.avgwin",e.st.avgwin); W("st.avgloss",e.st.avgloss); W("st.rr",e.st.rr);
   W("st.exp",e.st.expct); WI("st.pf_ok",e.st.pf_ok); W("st.pf",e.st.pf);
   W("st.comm",e.st.comm); W("st.swap",e.st.swap); W("st.fee",e.st.fee); W("st.lots",e.st.lots);
   W("st.maxdd_money",e.st.maxdd_money); W("st.maxdd_pct",e.st.maxdd_pct); WI("st.maxdd_time",e.st.maxdd_time);
   W("st.rel_pct",e.st.rel_pct); W("st.rel_money",e.st.rel_money); WI("st.rel_time",e.st.rel_time);
   WI("st.sharpe_ok",e.st.sharpe_ok); W("st.sharpe",e.st.sharpe);
   WI("st.best_ok",e.st.best_ok);
   W("st.best_pct",e.st.best_pct); WI("st.best_day",e.st.best_day);
   W("st.worst_pct",e.st.worst_pct); WI("st.worst_day",e.st.worst_day);
   WI("st.first_day",e.st.first_day);
   for(int i=0; i<e.ntr; i++)
     {
      string p=StringFormat("trade.%d.",i);
      WI(p+"close",e.tr[i].close_time); W(p+"net",e.tr[i].net);
     }
   WI("ndays",e.ndays);
   for(int i=0; i<e.ndays; i++)
     {
      string p=StringFormat("day.%d.",i);
      double m,pc;
      bool ap;
      e.DdOf(e.days[i].day,jd,jm,jp,jn,m,pc,ap);
      WI(p+"day",e.days[i].day); WI(p+"n",e.days[i].n); W(p+"net",e.days[i].net);
      W(p+"bal",e.days[i].bal); W(p+"dd_money",m); W(p+"dd_pct",pc); WI(p+"dd_approx",ap);
     }
   WI("njournal",jn);
  }


void DumpOpen(CVtEngine &e)
  {
   string nm[3]={"long","short","total"};
   for(int q=0; q<3; q++)
     {
      WI("open."+nm[q]+".n",e.o_n[q]); W("open."+nm[q]+".lots",e.o_lots[q]);
      W("open."+nm[q]+".pl",e.o_pl[q]); W("open."+nm[q]+".pips",e.o_pips[q]);
     }
   W("open.risk",e.o_risk); W("open.risk_pct",e.o_risk_pct); WI("open.nostop",e.o_nostop);
   WS("open.nostop_first",e.o_nostop_first); WI("open.nex",e.o_nex);
   for(int i=0; i<e.o_nex; i++)
     { WS(StringFormat("open.ex.%d.name",i),e.ex_name[i]); W(StringFormat("open.ex.%d.net",i),e.ex_net[i]); }
  }

#endif
