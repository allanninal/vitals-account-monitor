//+------------------------------------------------------------------+
//|                                                   VtExposure.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Open positions: long / short / total, risk at the stops, the     |
//| positions without a stop, and the net exposure per currency in   |
//| account money. Pure aggregation of numbers the live layer        |
//| (VtLive.mqh) read from the terminal: the same function runs in   |
//| the tests (tests/reference.py twins it).                         |
//|   Exposure of a position = +/- its notional (account money):     |
//|   long = + base currency, - profit currency. When base ==        |
//|   profit currency (an index CFD) the symbol is the "currency".   |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef VTEXPOSURE_MQH
#define VTEXPOSURE_MQH
#include "VtCore.mqh"

struct VtPos
  {
   long   magic;
   string symbol,comment;
   int    dir;                           // 0 long, 1 short
   double volume,profit,pips,sl,risk,value;   // profit incl. swap; risk = OrderCalcProfit at the stop (<=0 is a loss)
   string base,ccy;                      // base and profit currency
  };

void VtSummarize(CVtEngine &e,const VtPos &pos[],const int n,const double balance)
  {
   for(int k=0; k<3; k++)
     { e.o_n[k]=0; e.o_lots[k]=0; e.o_pl[k]=0; e.o_pips[k]=0; }
   e.o_risk=0; e.o_nostop=0; e.o_nostop_first=""; e.o_nex=0;
   ArrayResize(e.ex_name,0,8);
   ArrayResize(e.ex_net,0,8);
   for(int i=0; i<n; i++)
     {
      if(!e.PassPos(pos[i].symbol,pos[i].magic,pos[i].comment))
         continue;
      for(int k=0; k<3; k++)
         if(k==2 || k==pos[i].dir)
           {
            e.o_n[k]++;
            e.o_lots[k]+=pos[i].volume;
            e.o_pl[k]+=pos[i].profit;
            e.o_pips[k]+=pos[i].pips;
           }
      if(pos[i].sl>0)
         e.o_risk+=pos[i].risk;
      else
        {
         e.o_nostop++;
         if(e.o_nostop_first=="")
            e.o_nostop_first=StringFormat("%s %s %.2f",pos[i].symbol,pos[i].dir==0 ? "long" : "short",pos[i].volume);
        }
      double s=(pos[i].dir==0 ? 1.0 : -1.0);
      string key[2];
      double val[2];
      int    nk=0;
      if(pos[i].base==pos[i].ccy)
        { key[0]=pos[i].symbol; val[0]=s*pos[i].value; nk=1; }
      else
        { key[0]=pos[i].base; val[0]=s*pos[i].value; key[1]=pos[i].ccy; val[1]=-s*pos[i].value; nk=2; }
      for(int q=0; q<nk; q++)
        {
         int f=-1;
         for(int j=0; j<e.o_nex; j++)
            if(e.ex_name[j]==key[q])
              { f=j; break; }
         if(f<0)
           {
            f=e.o_nex++;
            ArrayResize(e.ex_name,e.o_nex,8);
            ArrayResize(e.ex_net,e.o_nex,8);
            e.ex_name[f]=key[q]; e.ex_net[f]=0;
           }
         e.ex_net[f]+=val[q];
        }
     }
   e.o_risk_pct=(balance>0 ? 100.0*e.o_risk/balance : 0.0);
   for(int i=1; i<e.o_nex; i++)                  // |net| descending, then name
     {
      string nm=e.ex_name[i];
      double v=e.ex_net[i];
      int j=i-1;
      while(j>=0 && (MathAbs(e.ex_net[j])<MathAbs(v) ||
            (MathAbs(e.ex_net[j])==MathAbs(v) && StringCompare(e.ex_name[j],nm)>0)))
        { e.ex_name[j+1]=e.ex_name[j]; e.ex_net[j+1]=e.ex_net[j]; j--; }
      e.ex_name[j+1]=nm; e.ex_net[j+1]=v;
     }
  }

#endif
