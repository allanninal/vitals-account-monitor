//+------------------------------------------------------------------+
//|                                                       VtLive.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| The terminal side of Vitals: account figures, open positions     |
//| (risk at the stops, exposure value) and the deal history, read   |
//| incrementally into CVtEngine. Read-only: no order function is    |
//| ever called (OrderCalcProfit only calculates).                   |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef VTLIVE_MQH
#define VTLIVE_MQH
#include "VtCore.mqh"
#include "VtExposure.mqh"

#define VT_SO_PERCENT ACCOUNT_STOPOUT_MODE_PERCENT

struct VtAcct
  {
   long   login,leverage;
   string server,ccy,mode;
   double balance,equity,margin,free,level,so,profit,credit;
   long   so_mode;                       // ACCOUNT_STOPOUT_MODE_PERCENT / _MONEY
  };

void VtReadAccount(VtAcct &a)
  {
   a.login=AccountInfoInteger(ACCOUNT_LOGIN);
   a.leverage=AccountInfoInteger(ACCOUNT_LEVERAGE);
   a.server=AccountInfoString(ACCOUNT_SERVER);
   a.ccy=AccountInfoString(ACCOUNT_CURRENCY);
   long m=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   a.mode=(m==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ? "hedging" : (m==ACCOUNT_MARGIN_MODE_RETAIL_NETTING ? "netting" : "exchange"));
   a.balance=AccountInfoDouble(ACCOUNT_BALANCE);
   a.equity=AccountInfoDouble(ACCOUNT_EQUITY);
   a.margin=AccountInfoDouble(ACCOUNT_MARGIN);
   a.free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   a.level=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   a.so=AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   a.so_mode=AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   a.profit=AccountInfoDouble(ACCOUNT_PROFIT);
   a.credit=AccountInfoDouble(ACCOUNT_CREDIT);
  }

//--- rate profit currency -> account currency from a cross symbol in the terminal (suffix of the position's symbol
//--- tried first); returns 0 when there is none
double VtCrossRate(const string ccy,const string acct,const string suffix)
  {
   if(ccy==acct)
      return(1.0);
   string a=ccy+acct+suffix,b=acct+ccy+suffix,c=ccy+acct,d=acct+ccy;
   string cand[4]={a,b,c,d};
   for(int i=0; i<4; i++)
     {
      if(!SymbolInfoInteger(cand[i],SYMBOL_EXIST))
         continue;
      double bid=SymbolInfoDouble(cand[i],SYMBOL_BID);
      if(bid<=0)
         continue;
      return(i%2==0 ? bid : 1.0/bid);
     }
   return(0.0);
  }

//--- the open positions as engine input. The notional value in account money is volume x contract x price x rate of
//--- the profit currency (cross symbol; else the terminal's own tick value). Risk = OrderCalcProfit at the stop.
int VtReadPositions(VtPos &out[],const string acct_ccy)
  {
   int total=PositionsTotal(),k=0;
   ArrayResize(out,total);
   for(int i=0; i<total; i++)
     {
      ulong t=PositionGetTicket(i);
      if(t==0)
         continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      long type=PositionGetInteger(POSITION_TYPE);
      double vol=PositionGetDouble(POSITION_VOLUME);
      double po=PositionGetDouble(POSITION_PRICE_OPEN);
      double pc=PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl=PositionGetDouble(POSITION_SL);
      out[k].symbol=sym;
      out[k].magic=PositionGetInteger(POSITION_MAGIC);
      out[k].comment=PositionGetString(POSITION_COMMENT);
      out[k].dir=(type==POSITION_TYPE_BUY ? 0 : 1);
      out[k].volume=vol;
      out[k].profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      out[k].sl=sl;
      int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      double point=SymbolInfoDouble(sym,SYMBOL_POINT);
      int mult=VtPipMult(sym,digits);
      double pips=0;
      if(point>0)
         pips=(pc-po)/point/mult;
      out[k].pips=(type==POSITION_TYPE_BUY ? pips : -pips);
      out[k].risk=0;
      if(sl>0)
        {
         double r=0;
         if(OrderCalcProfit(type==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,sym,vol,po,sl,r))
            out[k].risk=r;
        }
      out[k].base=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
      out[k].ccy=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
      string suffix=(StringLen(sym)>6 ? StringSubstr(sym,6) : "");
      double rate=VtCrossRate(out[k].ccy,acct_ccy,suffix);
      double contract=SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
      if(rate<=0)                                   // no cross symbol: the terminal's own conversion
        {
         double tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE),ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
         rate=(contract>0 && ts>0 ? tv/ts/contract : 0.0);
        }
      out[k].value=vol*contract*pc*rate;
      if(out[k].base=="")
         out[k].base=sym;
      if(out[k].ccy=="")
         out[k].ccy=sym;
      k++;
     }
   ArrayResize(out,k);
   return(k);
  }

//--- the deal history, read incrementally into the engine
class CVtHistory
  {
public:
   long     last_time;
   ulong    last_ticket;
   int      ndeals;
   long     login;
            CVtHistory(): last_time(0),last_ticket(0),ndeals(0),login(0) {}
   void     Forget() { last_time=0; last_ticket=0; ndeals=0; }
   //--- read deals [first..] of the current selection into the engine
   int      Process(CVtEngine &e,const int first)
     {
      int n=HistoryDealsTotal(),added=0;
      for(int i=first; i<n; i++)
        {
         ulong tk=HistoryDealGetTicket(i);
         if(tk==0)
            continue;
         long ty=HistoryDealGetInteger(tk,DEAL_TYPE);
         long en=HistoryDealGetInteger(tk,DEAL_ENTRY);
         last_ticket=tk;
         last_time=HistoryDealGetInteger(tk,DEAL_TIME);
         VtDeal d;
         d.time=last_time;
         d.pos=HistoryDealGetInteger(tk,DEAL_POSITION_ID);
         d.magic=HistoryDealGetInteger(tk,DEAL_MAGIC);
         d.profit=HistoryDealGetDouble(tk,DEAL_PROFIT);
         d.swap=HistoryDealGetDouble(tk,DEAL_SWAP);
         d.commission=HistoryDealGetDouble(tk,DEAL_COMMISSION);
         d.fee=HistoryDealGetDouble(tk,DEAL_FEE);
         d.volume=0; d.symbol=""; d.comment="";
         d.entry=VT_IN;
         if(ty==DEAL_TYPE_BUY || ty==DEAL_TYPE_SELL)
           {
            d.type=(ty==DEAL_TYPE_BUY ? VT_T_BUY : VT_T_SELL);
            if(en==DEAL_ENTRY_IN) d.entry=VT_IN;
            else if(en==DEAL_ENTRY_OUT) d.entry=VT_OUT;
            else if(en==DEAL_ENTRY_INOUT) d.entry=VT_INOUT;
            else if(en==DEAL_ENTRY_OUT_BY) d.entry=VT_OUTBY;
            else continue;                           // DEAL_ENTRY_STATE: a restored state, no result
            d.volume=HistoryDealGetDouble(tk,DEAL_VOLUME);
            d.symbol=HistoryDealGetString(tk,DEAL_SYMBOL);
            d.comment=HistoryDealGetString(tk,DEAL_COMMENT);
           }
         else
            d.type=(ty==DEAL_TYPE_CREDIT ? VT_T_CREDIT : VT_T_CASH);   // balance, charges, corrections ... = cash flow
         e.Add(d);
         ndeals++;
         added++;
        }
      return(added);
     }
   //--- full rebuild
   bool     Rebuild(CVtEngine &e)
     {
      e.Reset();
      Forget();
      if(!HistorySelect(0,(datetime)4102444800))
         return(false);
      Process(e,0);
      return(true);
     }
   //--- new deals since the last call; rebuilds when the history was rewritten. true when the engine changed.
   bool     Refresh(CVtEngine &e,bool &rebuilt)
     {
      rebuilt=false;
      long lg=AccountInfoInteger(ACCOUNT_LOGIN);
      if(last_ticket==0 || lg!=login)
        {
         login=lg;
         rebuilt=true;
         Rebuild(e);
         return(true);
        }
      if(!HistorySelect((datetime)last_time,(datetime)4102444800))
         return(false);
      int n=HistoryDealsTotal();
      if(n==0)
        { rebuilt=true; Rebuild(e); return(true); }
      int at=-1;
      for(int i=0; i<n; i++)
        {
         ulong tk=HistoryDealGetTicket(i);
         if(tk==last_ticket)
           { at=i; break; }
         if(HistoryDealGetInteger(tk,DEAL_TIME)>last_time)
            break;
        }
      if(at<0)
        { rebuilt=true; Rebuild(e); return(true); }
      if(at==n-1)
         return(false);
      return(Process(e,at+1)>0);
     }
  };

#endif
//+------------------------------------------------------------------+
