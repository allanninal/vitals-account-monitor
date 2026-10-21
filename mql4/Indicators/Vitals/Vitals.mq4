//+------------------------------------------------------------------+
//|                            Vitals.mq4                            |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Vitals (free): your whole account on one card - equity, floating |
//| drawdown against today's worst and the worst day, margin, open   |
//| positions, risk at the stops, exposure per currency, history by  |
//| period, statistics. Read-only; it never places or changes an     |
//| order. Engine: Include/Vitals/VtCore.mqh.                        |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property copyright   "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property link        "https://www.allanninal.dev/mql5"
#property version     "1.00"
#property description "Your whole account on one card: floating drawdown journal, margin, positions, risk at stops, exposure, history and statistics."
#property description "Read-only: it never places, changes or closes orders."
#property strict
#property indicator_chart_window
#property indicator_buffers 1      // one hidden buffer: MT4 keeps an iCustom instance (tests, EAs) only when it has a buffer

#include <Vitals/VtApp.mqh>

double g_hidden[];                    // never drawn, never filled
int OnInit()
  {
   SetIndexBuffer(0,g_hidden);
   SetIndexStyle(0,DRAW_NONE);
   SetIndexLabel(0,NULL);               // no row in the Data Window
   return(VtInit());
  }
void OnDeinit(const int reason) { VtDeinit(reason); }
void OnTimer() { VtTimer(); }
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   VtCalc();
   return(rates_total);
  }
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam) { VtEvent(id,lparam,dparam,sparam); }
//+------------------------------------------------------------------+
