//+------------------------------------------------------------------+
//|                                                       VtLive.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| MT4 edition of the terminal side of Vitals: account figures,     |
//| open positions (risk at the stops, exposure value) and the order |
//| history turned into the engine's deal list. Read-only: no order  |
//| function is ever called.                                         |
//|   MT4 keeps ORDERS, not deals, so every order becomes an IN deal at its open time and, once      |
//|   closed, an OUT deal at its close time carrying profit, swap    |
//|   and commission. A partial close leaves an order for the closed |
//|   part and opens a new one commented "from #<ticket>": the chain |
//|   is ONE position (the engine's trade), keyed by the first ticket.|
//|   Balance records (type 6) are cash flow, credit (7) is credit.  |
//|   There is no fee in MT4. Prices come from MarketInfo (the       |
//|   SymbolInfo bid/ask is 0 for some symbols in the tester);       |
//|   there is no OrderCalcProfit: risk at a stop = distance / tick  |
//|   size x tick value x lots, with the documented fallback when the|
//|   tester gives MODE_TICKVALUE 0 (gold, crypto).                  |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef VTLIVE_MQH
#define VTLIVE_MQH
#include "VtCore.mqh"
#include "VtExposure.mqh"

#define VT_SO_PERCENT 0                  // AccountStopoutMode(): 0 = percent, 1 = money

//--- the server clock: the last tick's time (MQL4 has no TimeTradeServer); in the tester the simulated time
long VtServerNow() { return((long)TimeCurrent()); }
//--- microsecond counter stand-in (MQL4 has no GetMicrosecondCount): milliseconds x 1000, good enough for the perf log
ulong VtMicros() { return((ulong)GetTickCount()*1000); }

struct VtAcct
  {
   long   login,leverage;
   string server,ccy,mode;
   double balance,equity,margin,free,level,so,profit,credit;
   long   so_mode;                       // VT_SO_PERCENT / 1 = money
  };

void VtReadAccount(VtAcct &a)
  {
   a.login=AccountNumber();
   a.leverage=AccountLeverage();
   a.server=AccountServer();
   a.ccy=AccountCurrency();
   a.mode="hedging";
   a.balance=AccountBalance();
   a.equity=AccountEquity();
   a.margin=AccountMargin();
   a.free=AccountFreeMargin();
   a.level=(a.margin>0 ? 100.0*a.equity/a.margin : 0.0);
   a.so=AccountStopoutLevel();
   a.so_mode=AccountStopoutMode();
   a.profit=AccountProfit();
   a.credit=AccountCredit();
  }

//--- rate profit currency -> account currency from a cross symbol in the terminal (suffix of the position's symbol
//--- tried first); returns 0 when there is none
double VtCrossRate(const string ccy,const string acct,const string suffix)
  {
   if(ccy==acct)
      return(1.0);
   string a=ccy+acct+suffix,b=acct+ccy+suffix,c=ccy+acct,d=acct+ccy;
   string cand[4];
   cand[0]=a; cand[1]=b; cand[2]=c; cand[3]=d;
   for(int i=0; i<4; i++)
     {
      ResetLastError();
      double bid=MarketInfo(cand[i],MODE_BID);
      if(bid<=0 || GetLastError()!=0)
         continue;
      return(i%2==0 ? bid : 1.0/bid);
     }
   return(0.0);
  }

//--- account money of one tick of one lot: MODE_TICKVALUE; when the terminal gives 0 (tester: gold, crypto),
//--- tick size x contract size x the profit currency's rate to the account currency
double VtTickValue(const string sym,const string acct_ccy,double &tick_size)
  {
   tick_size=MarketInfo(sym,MODE_TICKSIZE);
   double tv=MarketInfo(sym,MODE_TICKVALUE);
   if(tv>0)
      return(tv);
   double contract=MarketInfo(sym,MODE_LOTSIZE);
   string ccy=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
   if(tick_size<=0 || contract<=0 || ccy=="")
      return(0.0);
   string suffix=(StringLen(sym)>6 ? StringSubstr(sym,6) : "");
   double rate=VtCrossRate(ccy,acct_ccy,suffix);
   return(rate>0 ? tick_size*contract*rate : 0.0);
  }

//--- loss (<= 0) of `lots` from `open` to `stop`, in account money; 0 when the symbol gives no tick value
double VtRiskMoney(const string sym,const int dir,const double lots,const double open,const double stop,const string acct_ccy)
  {
   double ts;
   double tv=VtTickValue(sym,acct_ccy,ts);
   if(tv<=0 || ts<=0)
      return(0.0);
   double dist=(dir==0 ? stop-open : open-stop);
   return(dist/ts*tv*lots);
  }

//--- the open positions as engine input
int VtReadPositions(VtPos &out[],const string acct_ccy)
  {
   int total=OrdersTotal(),k=0;
   ArrayResize(out,total);
   for(int i=0; i<total; i++)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || OrderType()>OP_SELL)
         continue;
      string sym=OrderSymbol();
      int type=OrderType();
      double vol=OrderLots(),po=OrderOpenPrice(),sl=OrderStopLoss();
      double pc=OrderClosePrice();                  // the current price of an open order
      out[k].symbol=sym;
      out[k].magic=OrderMagicNumber();
      out[k].comment=OrderComment();
      out[k].dir=(type==OP_BUY ? 0 : 1);
      out[k].volume=vol;
      out[k].profit=OrderProfit()+OrderSwap();
      out[k].sl=sl;
      int digits=(int)MarketInfo(sym,MODE_DIGITS);
      double point=MarketInfo(sym,MODE_POINT);
      int mult=VtPipMult(sym,digits);
      double pips=0;
      if(point>0)
         pips=(pc-po)/point/mult;
      out[k].pips=(type==OP_BUY ? pips : -pips);
      out[k].risk=0;
      if(sl>0)
         out[k].risk=VtRiskMoney(sym,out[k].dir,vol,po,sl,acct_ccy);
      out[k].base=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
      out[k].ccy=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
      string suffix=(StringLen(sym)>6 ? StringSubstr(sym,6) : "");
      double rate=VtCrossRate(out[k].ccy,acct_ccy,suffix);
      double contract=MarketInfo(sym,MODE_LOTSIZE);
      if(rate<=0)                                   // no cross symbol: the terminal's own conversion
        {
         double ts;
         double tv=VtTickValue(sym,acct_ccy,ts);
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

//--- "from #123" = the rest of a partially closed order; the chain's first ticket is the position
long VtFromTicket(const string c)
  {
   if(StringFind(c,"from #")!=0)
      return(0);
   return(StringToInteger(StringSubstr(c,6)));
  }

//--- the comment an EA gave the order: the server's own notes are not part of it
string VtCleanComment(string c)
  {
   if(StringFind(c,"from #")==0 || StringFind(c,"to #")==0 || StringFind(c,"partial close")==0 || StringFind(c,"close hedge")==0)
      return("");
   int k=StringFind(c,"[");                    // "[sl]", "[tp]", "[so]" added when the server closed it
   if(k==0)
      return("");                              // (StringSubstr with length 0 would return the WHOLE string)
   if(k>0)
      c=StringSubstr(c,0,k);
   StringTrimRight(c);
   return(c);
  }

//--- the order history, rebuilt into the engine whenever it changes
class CVtHistory
  {
public:
   long     last_time;
   ulong    last_ticket;
   int      ndeals;
   long     login;
   string   m_sig;
            CVtHistory(): last_time(0),last_ticket(0),ndeals(0),login(0),m_sig("") {}
   //--- what changes when the history or the open orders change
   string   Signature()
     {
      int nh=OrdersHistoryTotal(),no=OrdersTotal();
      double st=0,sl=0;
      for(int i=0; i<no; i++)
         if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
           { st+=OrderTicket(); sl+=OrderLots(); }
      long lt=0;
      if(nh>0 && OrderSelect(nh-1,SELECT_BY_POS,MODE_HISTORY))
         lt=OrderTicket();
      return(StringFormat("%d|%d|%.0f|%.2f|%I64d|%I64d",nh,no,st,sl,lt,AccountNumber()));
     }
   //--- the orders as deals, in time order (IN before OUT at the same second), into the engine
   bool     Rebuild(CVtEngine &e)
     {
      e.Reset();
      ndeals=0; last_time=0; last_ticket=0;
      int nh=OrdersHistoryTotal(),no=OrdersTotal(),n=0;
      long   tk[],par[],ot[],ct[],mg[];
      int    ty[];
      double lt[],pf[],sw[],cm[];
      string cmt[],sy[];
      int cap=nh+no;
      ArrayResize(tk,cap); ArrayResize(par,cap); ArrayResize(ot,cap); ArrayResize(ct,cap); ArrayResize(mg,cap); ArrayResize(ty,cap);
      ArrayResize(lt,cap); ArrayResize(pf,cap); ArrayResize(sw,cap); ArrayResize(cm,cap);
      ArrayResize(cmt,cap); ArrayResize(sy,cap);
      for(int pass=0; pass<2; pass++)
         for(int i=0; i<(pass==0 ? nh : no); i++)
           {
            if(!OrderSelect(i,SELECT_BY_POS,pass==0 ? MODE_HISTORY : MODE_TRADES))
               continue;
            int t=OrderType();
            if(t>OP_SELL && t!=6 && t!=7)
               continue;                            // pending orders: not trades
            tk[n]=OrderTicket(); ty[n]=t; cmt[n]=OrderComment(); par[n]=VtFromTicket(cmt[n]);
            ot[n]=(long)OrderOpenTime(); ct[n]=(pass==0 ? (long)OrderCloseTime() : 0); mg[n]=OrderMagicNumber();
            lt[n]=OrderLots(); pf[n]=OrderProfit(); sw[n]=OrderSwap(); cm[n]=OrderCommission();
            sy[n]=OrderSymbol();
            n++;
           }
      //--- position of each order: follow "from #" to the first ticket (tickets sorted for the lookup)
      double idx[][2];
      ArrayResize(idx,n);
      for(int i=0; i<n; i++)
        { idx[i][0]=(double)tk[i]; idx[i][1]=i; }
      if(n>1)
         ArraySort(idx);
      long root[];
      ArrayResize(root,n);
      for(int i=0; i<n; i++)
        {
         long r=tk[i],p=par[i];
         for(int guard=0; p!=0 && guard<10000; guard++)
           {
            r=p;
            p=0;
            int lo=0,hi=n-1;                        // binary search for ticket r
            while(lo<=hi)
              {
               int mid=(lo+hi)/2;
               if(idx[mid][0]<(double)r)
                  lo=mid+1;
               else
                  if(idx[mid][0]>(double)r)
                     hi=mid-1;
                  else
                    { p=par[(int)idx[mid][1]]; break; }
              }
           }
         root[i]=r;
        }
      //--- the deals; phase 0 cash, 1 opening, 2 closing; sorted by time, phase, reading order
      int nd=0;
      VtDeal dl[];
      double key[][2];
      ArrayResize(dl,2*n); ArrayResize(key,2*n);
      for(int i=0; i<n; i++)
        {
         if(ty[i]==6 || ty[i]==7)
           {
            VtDeal d;
            d.time=ct[i]>0 ? ct[i] : ot[i]; d.pos=tk[i]; d.magic=0; d.type=(ty[i]==6 ? VT_T_CASH : VT_T_CREDIT); d.entry=VT_IN;
            d.volume=0; d.profit=pf[i]; d.swap=0; d.commission=0; d.fee=0; d.symbol=""; d.comment="";
            dl[nd]=d;
            key[nd][0]=((double)d.time*3.0+0)*1048576.0+nd; key[nd][1]=nd; nd++;
            continue;
           }
         for(int e2=0; e2<2; e2++)
           {
            if(e2==1 && ct[i]==0)
               continue;
            VtDeal d;
            d.time=(e2==0 ? ot[i] : ct[i]); d.pos=root[i]; d.magic=mg[i];
            d.type=(e2==0 ? (ty[i]==OP_BUY ? VT_T_BUY : VT_T_SELL) : (ty[i]==OP_BUY ? VT_T_SELL : VT_T_BUY));
            d.entry=(e2==0 ? VT_IN : VT_OUT);
            d.volume=lt[i];
            d.profit=(e2==0 ? 0 : pf[i]); d.swap=(e2==0 ? 0 : sw[i]); d.commission=(e2==0 ? 0 : cm[i]); d.fee=0;
            d.symbol=sy[i]; d.comment=(e2==0 ? VtCleanComment(cmt[i]) : "");
            dl[nd]=d;
            key[nd][0]=((double)d.time*3.0+(e2==0 ? 1 : 2))*1048576.0+nd; key[nd][1]=nd; nd++;
           }
        }
      ArrayResize(key,nd);
      if(nd>1)
         ArraySort(key);
      for(int i=0; i<nd; i++)
        {
         VtDeal d=dl[(int)key[i][1]];
         e.Add(d);
         last_time=d.time;
         ndeals++;
        }
      last_ticket=(ndeals>0 ? 1 : 0);
      m_sig=Signature();
      return(true);
     }
   //--- true when the engine changed (a new order, a close, a partial close, another account)
   bool     Refresh(CVtEngine &e,bool &rebuilt)
     {
      rebuilt=false;
      long lg=AccountNumber();
      string sg=Signature();
      if(sg==m_sig && lg==login)
         return(false);
      login=lg;
      rebuilt=true;
      Rebuild(e);
      return(true);
     }
  };

#endif
//+------------------------------------------------------------------+
