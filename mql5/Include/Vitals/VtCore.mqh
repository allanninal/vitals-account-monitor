//+------------------------------------------------------------------+
//|                                                       VtCore.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Vitals engine. Pure computation on a deal list: no terminal      |
//| calls, so tests/reference.py (its Python twin) can be compared   |
//| with it number for number (tests/check_core.py).                 |
//|   Trade  = deals grouped by position id; net = profit +          |
//|            commission + swap + fee of all its deals; it belongs  |
//|            to the day of its closing deal.                       |
//|   Cash   = balance deals (deposits, withdrawals, charges ...):   |
//|            never a trade, but part of the rebuilt balance.       |
//|   Credit = never a trade, not part of the balance.               |
//|   Gain % = period net / balance at the period start (current     |
//|            balance minus every deal since, cash flow included).  |
//|   Floating drawdown of a day: the journal (VtJournal.mqh) when   |
//|            it has the day, else the peak-to-trough of that day's |
//|            closed-trade curve, flagged approximate.              |
//|   Stats follow the usual prop-firm formulas (see the README).    |
//| Day = server calendar day (seconds / 86400); week starts Monday. |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef VTCORE_MQH
#define VTCORE_MQH

#define VT_T_BUY    0
#define VT_T_SELL   1
#define VT_T_CASH   2
#define VT_T_CREDIT 3
#define VT_IN       0
#define VT_OUT      1
#define VT_INOUT    2
#define VT_OUTBY    3
#define VT_EPS      1e-8
#define VT_DAY      86400
#define VT_MAXROWS  8

struct VtDeal
  {
   long   time,pos,magic;
   int    type,entry;
   double volume,profit,swap,commission,fee;
   string symbol,comment;
  };

struct VtTrade
  {
   long   open_time,close_time;
   double volume,net,comm,swap,fee;
  };

struct VtOpenPos
  {
   long   magic;
   string symbol,comment;
   long   open_time,pos;
   double vol,tvol,net,comm,swap,fee;
  };

struct VtDay
  {
   long   day;
   int    n,w,l;
   double net,lots,fb,fbp,c,pk,bal;
  };

struct VtRow
  {
   int    kind;                         // 0 one day, 1 week, 2 month, 3 year
   long   day;                          // first calendar day
   int    n,w,l,gain_ok,dd_ok,dd_approx;
   double net,lots,gain,dd_pct;
  };

struct VtStats
  {
   int    n,w,l,pf_ok,sharpe_ok,best_ok;
   double gp,gl,winrate,avgwin,avgloss,rr,expct,pf,comm,swap,fee,lots;
   double maxdd_money,maxdd_pct,rel_pct,rel_money,sharpe;
   long   maxdd_time,rel_time,first_day;
   double best_pct,worst_pct;
   long   best_day,worst_day;
  };

//--- points per pip: how many price points make one pip on this symbol. Classified by instrument kind and digits.
int VtPipMult(const string sym,const int digit)
  {
   bool fx_jpy=(StringFind(sym,"JPY")>-1);
   bool gold=(StringFind(sym,"XAU")>-1 || StringFind(sym,"GOLD")>-1);
   bool silver=(StringFind(sym,"XAG")>-1 || StringFind(sym,"SILVER")>-1);
   bool yen_or_silver=(fx_jpy || silver);
   //--- a pip is 10 points on 5-digit FX and 1-digit quotes, on 3-digit yen/silver and 2-digit gold ...
   if(digit==5 || digit==1 || (digit==3 && yen_or_silver) || (digit==2 && gold))
      return(10);
   //--- ... and 100 points with one more digit (6, 4-digit yen/silver, 3-digit gold) or on 2-digit quotes
   if(digit==6 || digit==2 || (digit==4 && yen_or_silver) || (digit==3 && gold))
      return(100);
   return(1);
  }

//--- calendar of the server clock (whole seconds since 1970, no zones): days <-> y/m/d
void VtCivil(long z,int &y,int &m,int &d)
  {
   z+=719468;
   long era=(z>=0 ? z : z-146096)/146097;
   long doe=z-era*146097;
   long yoe=(doe-doe/1460+doe/36524-doe/146096)/365;
   long yy=yoe+era*400;
   long doy=doe-(365*yoe+yoe/4-yoe/100);
   long mp=(5*doy+2)/153;
   d=(int)(doy-(153*mp+2)/5+1);
   m=(int)(mp<10 ? mp+3 : mp-9);
   y=(int)(yy+(m<=2 ? 1 : 0));
  }

long VtDaysFromCivil(int y,const int m,const int d)
  {
   if(m<=2)
      y--;
   long era=(y>=0 ? y : y-399)/400;
   long yoe=y-era*400;
   long doy=(153*(m>2 ? m-3 : m+9)+2)/5+d-1;
   long doe=yoe*365+yoe/4-yoe/100+doy;
   return(era*146097+doe-719468);
  }

int VtWeekday(const long day) { return((int)((day+3)%7)); }   // Monday = 0

class CVtEngine
  {
public:
   //--- filters (apply to trades and positions; the balance never is filtered)
   string   f_symbol;
   long     f_magic;
   string   f_comment;                   // lower case
   long     f_start;
   //--- the book
   VtOpenPos op[];
   int      nop,hint;
   VtTrade  tr[];
   int      ntr;
   long     ct[];                        // time of every balance-affecting deal
   double   cc[];                        // running sum of their pnl
   int      ncc;
   //--- the report
   VtRow    rows[VT_MAXROWS];
   int      nrows;
   VtStats  st;
   double   s0;
   VtDay    days[];
   int      ndays;
   double   avg_day,avg_month;
   int      avg_day_ok,avg_month_ok;
   //--- open positions
   int      o_n[3];                      // long, short, total
   double   o_lots[3],o_pl[3],o_pips[3];
   double   o_risk,o_risk_pct;
   int      o_nostop,o_nex;
   string   o_nostop_first;
   string   ex_name[];
   double   ex_net[];

            CVtEngine() { Filter("",-1,"",0); Reset(); }
   void     Filter(const string symbol,const long magic,const string comment,const long start)
     {
      f_symbol=symbol; f_magic=magic; f_start=start;
      f_comment=comment; StringToLower(f_comment);
     }
   void     Reset()
     {
      ArrayResize(op,0,64); nop=0; hint=0;
      ArrayResize(tr,0,1024); ntr=0;
      ArrayResize(ct,0,4096); ArrayResize(cc,0,4096); ncc=0;
      ArrayResize(days,0,256); ndays=0;
      nrows=0;
     }
   bool     PassPos(const string symbol,const long magic,const string comment) const
     {
      if(f_symbol!="" && symbol!=f_symbol)
         return(false);
      if(f_magic>=0 && magic!=f_magic)
         return(false);
      if(f_comment!="")
        {
         string c=comment;
         StringToLower(c);
         if(StringFind(c,f_comment)<0)
            return(false);
        }
      return(true);
     }
   int      OpIdx(const long pos)
     {
      if(hint<nop && op[hint].pos==pos)
         return(hint);
      for(int i=nop-1; i>=0; i--)
         if(op[i].pos==pos)
           { hint=i; return(i); }
      return(-1);
     }
   int      NewOp(const long pos)
     {
      int k=nop++;
      ArrayResize(op,nop,64);
      op[k].pos=pos; hint=k;
      return(k);
     }
   //--- one deal, in time order; true when it completed a trade that passes the filters
   bool     Add(const VtDeal &d);
   double   BalBefore(const long t,const double bal_now) const;
   void     Report(const long now,const double bal_now,const long &jd[],const double &jm[],const double &jp[],const int jn);
   //--- helpers for the views
   int      DayIdx(const long day) const;
   bool     DdOf(const long dn,const long &jd[],const double &jm[],const double &jp[],const int jn,
                 double &money,double &pct,bool &approx) const;
  };

bool CVtEngine::Add(const VtDeal &d)
  {
   double pnl=d.profit+d.swap+d.commission+d.fee;
   if(d.type==VT_T_CREDIT)
      return(false);
   double total=(ncc>0 ? cc[ncc-1] : 0.0)+pnl;
   ArrayResize(ct,ncc+1,4096);
   ArrayResize(cc,ncc+1,4096);
   ct[ncc]=d.time; cc[ncc]=total; ncc++;
   if(d.type==VT_T_CASH)
      return(false);
   int pi=OpIdx(d.pos);
   if(d.entry==VT_IN)
     {
      if(pi<0)
        {
         pi=NewOp(d.pos);
         op[pi].magic=d.magic; op[pi].symbol=d.symbol; op[pi].comment=d.comment;
         op[pi].open_time=d.time;
         op[pi].vol=0; op[pi].tvol=0; op[pi].net=0; op[pi].comm=0; op[pi].swap=0; op[pi].fee=0;
        }
      op[pi].vol+=d.volume;
      op[pi].tvol+=d.volume;
     }
   else
      if(pi<0)                                    // the opening deal is not in the history
        {
         pi=NewOp(d.pos);
         op[pi].magic=d.magic; op[pi].symbol=d.symbol; op[pi].comment=d.comment;
         op[pi].open_time=d.time;
         op[pi].vol=d.volume; op[pi].tvol=d.volume; op[pi].net=0; op[pi].comm=0; op[pi].swap=0;
         op[pi].fee=0;
        }
   op[pi].net+=pnl;
   op[pi].comm+=d.commission;
   op[pi].swap+=d.swap;
   op[pi].fee+=d.fee;
   bool closed=false;
   double rest=0;
   if(d.entry==VT_OUT || d.entry==VT_OUTBY)
     {
      op[pi].vol-=d.volume;
      closed=(op[pi].vol<=VT_EPS);
     }
   else
      if(d.entry==VT_INOUT)
        {
         rest=d.volume-op[pi].vol;                // the part beyond the open volume opens the other way
         closed=true;
        }
   if(!closed)
      return(false);
   bool ok=(PassPos(op[pi].symbol,op[pi].magic,op[pi].comment) && d.time>=f_start);
   if(ok)
     {
      int k=ntr++;
      ArrayResize(tr,ntr,1024);
      tr[k].open_time=op[pi].open_time; tr[k].close_time=d.time; tr[k].volume=op[pi].tvol; tr[k].net=op[pi].net;
      tr[k].comm=op[pi].comm; tr[k].swap=op[pi].swap; tr[k].fee=op[pi].fee;
     }
   if(d.entry==VT_INOUT && rest>VT_EPS)           // the rest opens the other way
     {
      op[pi].open_time=d.time;
      op[pi].vol=rest; op[pi].tvol=rest; op[pi].net=0; op[pi].comm=0; op[pi].swap=0; op[pi].fee=0;
     }
   else
     {
      nop--;
      if(pi<nop)
         op[pi]=op[nop];
      hint=0;
     }
   return(ok);
  }

double CVtEngine::BalBefore(const long t,const double bal_now) const
  {
   int lo=0,hi=ncc;                              // first index with ct >= t
   while(lo<hi)
     {
      int mid=(lo+hi)/2;
      if(ct[mid]<t)
         lo=mid+1;
      else
         hi=mid;
     }
   double before=(lo>0 ? cc[lo-1] : 0.0);
   double total=(ncc>0 ? cc[ncc-1] : 0.0);
   return(bal_now-(total-before));
  }

int CVtEngine::DayIdx(const long day) const
  {
   int lo=0,hi=ndays;
   while(lo<hi)
     {
      int mid=(lo+hi)/2;
      if(days[mid].day<day)
         lo=mid+1;
      else
         hi=mid;
     }
   return(lo<ndays && days[lo].day==day ? lo : -1);
  }

//--- the floating drawdown of one calendar day: the journal's, else the closed-trade fallback (approx)
bool CVtEngine::DdOf(const long dn,const long &jd[],const double &jm[],const double &jp[],const int jn,
                     double &money,double &pct,bool &approx) const
  {
   int lo=0,hi=jn;
   while(lo<hi)
     {
      int mid=(lo+hi)/2;
      if(jd[mid]<dn)
         lo=mid+1;
      else
         hi=mid;
     }
   if(lo<jn && jd[lo]==dn)
     {
      money=MathMin(jm[lo],0.0); pct=MathMin(jp[lo],0.0); approx=false;
      return(true);
     }
   int i=DayIdx(dn);
   if(i>=0)
     {
      money=days[i].fb; pct=days[i].fbp; approx=true;
      return(true);
     }
   money=0; pct=0; approx=false;
   return(false);
  }

void CVtEngine::Report(const long now,const double bal_now,const long &jd[],const double &jm[],const double &jp[],const int jn)
  {
   long nowday=now/VT_DAY;
   //--- days with trades (trades are in close order)
   ndays=0;
   ArrayResize(days,0,256);
   for(int i=0; i<ntr; i++)
     {
      long dn=tr[i].close_time/VT_DAY;
      if(ndays==0 || days[ndays-1].day!=dn)
        {
         ArrayResize(days,ndays+1,256);
         int k=ndays++;
         days[k].day=dn; days[k].n=0; days[k].w=0; days[k].l=0; days[k].net=0; days[k].lots=0;
         days[k].fb=0; days[k].fbp=0; days[k].c=0; days[k].pk=0; days[k].bal=0;
        }
      int x=ndays-1;
      days[x].n++;
      days[x].net+=tr[i].net;
      days[x].lots+=tr[i].volume;
      if(tr[i].net>0)
         days[x].w++;
      else
         if(tr[i].net<0)
            days[x].l++;
      days[x].c+=tr[i].net;
      days[x].pk=MathMax(days[x].pk,days[x].c);
      days[x].fb=MathMin(days[x].fb,days[x].c-days[x].pk);
     }
   s0=bal_now;
   if(ntr>0)
     {
      long mo=tr[0].open_time;
      for(int i=1; i<ntr; i++)
         mo=MathMin(mo,tr[i].open_time);
      s0=BalBefore(mo,bal_now);
     }
   for(int i=0; i<ndays; i++)
     {
      days[i].bal=BalBefore(days[i].day*VT_DAY,bal_now);
      days[i].fbp=(days[i].bal>0 ? 100.0*days[i].fb/days[i].bal : 0.0);
     }
   //--- period rows
   long a[VT_MAXROWS];
   int  kd[VT_MAXROWS];
   nrows=0;
   a[nrows]=nowday; kd[nrows]=0; nrows++;
   for(int i=ndays-1; i>=0 && nrows<5; i--)
      if(days[i].day<nowday)
        { a[nrows]=days[i].day; kd[nrows]=0; nrows++; }
   int y,m,dd;
   VtCivil(nowday,y,m,dd);
   a[nrows]=nowday-VtWeekday(nowday); kd[nrows]=1; nrows++;
   a[nrows]=VtDaysFromCivil(y,m,1); kd[nrows]=2; nrows++;
   a[nrows]=VtDaysFromCivil(y,1,1); kd[nrows]=3; nrows++;
   for(int r=0; r<nrows; r++)
     {
      long from=a[r],to=(kd[r]==0 ? a[r]+1 : nowday+1);
      rows[r].kind=kd[r]; rows[r].day=from;
      rows[r].n=0; rows[r].w=0; rows[r].l=0; rows[r].net=0; rows[r].lots=0;
      for(int i=0; i<ndays; i++)
         if(days[i].day>=from && days[i].day<to)
           {
            rows[r].n+=days[i].n; rows[r].w+=days[i].w; rows[r].l+=days[i].l;
            rows[r].net+=days[i].net; rows[r].lots+=days[i].lots;
           }
      double bal=BalBefore(from*VT_DAY,bal_now);
      rows[r].gain_ok=(bal>0 ? 1 : 0);
      rows[r].gain=(bal>0 ? 100.0*rows[r].net/bal : 0.0);
      bool ok=false,ba=false;
      double bp=0;
      for(long dn=from; dn<to; dn++)
        {
         double mny,pc;
         bool ap;
         if(DdOf(dn,jd,jm,jp,jn,mny,pc,ap) && (!ok || pc<bp))
           { ok=true; bp=pc; ba=ap; }
        }
      rows[r].dd_ok=(ok ? 1 : 0); rows[r].dd_pct=bp; rows[r].dd_approx=(ba ? 1 : 0);
     }
   //--- daily returns, averages
   double rv[];
   long   rd[];
   int    nr=0;
   ArrayResize(rv,ndays); ArrayResize(rd,ndays);
   for(int i=0; i<ndays; i++)
      if(days[i].bal>0)
        { rv[nr]=100.0*days[i].net/days[i].bal; rd[nr]=days[i].day; nr++; }
   avg_day_ok=(nr>0 ? 1 : 0);
   double sum=0;
   for(int i=0; i<nr; i++)
      sum+=rv[i];
   avg_day=(nr>0 ? sum/nr : 0.0);
   double msum=0;
   int    mcount=0;
   long   mkey=-1;
   double mnet=0;
   long   mfirst=0;
   for(int i=0; i<=ndays; i++)
     {
      long key=-1;
      if(i<ndays)
        {
         int yy,mm,d2;
         VtCivil(days[i].day,yy,mm,d2);
         key=(long)yy*12+mm;
        }
      if(i==ndays || key!=mkey)
        {
         if(mkey>=0)
           {
            double b=BalBefore(mfirst*VT_DAY,bal_now);
            if(b>0)
              { msum+=100.0*mnet/b; mcount++; }
           }
         if(i<ndays)
           {
            int yy,mm,d2;
            VtCivil(days[i].day,yy,mm,d2);
            mkey=key; mnet=0; mfirst=VtDaysFromCivil(yy,mm,1);
           }
        }
      if(i<ndays)
         mnet+=days[i].net;
     }
   avg_month_ok=(mcount>0 ? 1 : 0);
   avg_month=(mcount>0 ? msum/mcount : 0.0);
   //--- statistics
   st.n=ntr; st.w=0; st.l=0; st.gp=0; st.gl=0; st.comm=0; st.swap=0; st.fee=0; st.lots=0;
   for(int i=0; i<ntr; i++)
     {
      st.lots+=tr[i].volume; st.comm+=tr[i].comm; st.swap+=tr[i].swap; st.fee+=tr[i].fee;
      if(tr[i].net>0)
        { st.w++; st.gp+=tr[i].net; }
      else
         if(tr[i].net<0)
           { st.l++; st.gl+=-tr[i].net; }
     }
   st.winrate=(ntr>0 ? 100.0*st.w/ntr : 0.0);
   st.avgwin=(st.w>0 ? st.gp/st.w : 0.0);
   st.avgloss=(st.l>0 ? -st.gl/st.l : 0.0);
   st.rr=((st.w>0 && st.l>0 && st.gl>0) ? (st.gp/st.w)/(st.gl/st.l) : 0.0);
   st.expct=(ntr>0 ? (st.gp-st.gl)/ntr : 0.0);
   st.pf_ok=(st.gl>0 ? 1 : 0);
   st.pf=(st.gl>0 ? st.gp/st.gl : 0.0);
   double c=s0,peak=s0;
   st.maxdd_money=0; st.maxdd_pct=0; st.maxdd_time=0; st.rel_pct=0; st.rel_money=0; st.rel_time=0;
   for(int i=0; i<ntr; i++)
     {
      c+=tr[i].net;
      peak=MathMax(peak,c);
      double ddm=peak-c;
      if(ddm>st.maxdd_money)
        { st.maxdd_money=ddm; st.maxdd_pct=(peak>0 ? 100.0*ddm/peak : 0.0); st.maxdd_time=tr[i].close_time; }
      double rp=(peak>0 ? 100.0*ddm/peak : 0.0);
      if(rp>st.rel_pct)
        { st.rel_pct=rp; st.rel_money=ddm; st.rel_time=tr[i].close_time; }
     }
   st.sharpe_ok=0; st.sharpe=0;
   //--- Sharpe over the last 60 calendar days only (a ~2-month horizon; today and the 59 days before it)
     {
      double ss=0;
      int    k=0;
      for(int i=0; i<nr; i++)
         if(rd[i]>=nowday-59)
           { ss+=rv[i]; k++; }
      if(k>=2)
        {
         double mean=ss/k,var=0;
         for(int i=0; i<nr; i++)
            if(rd[i]>=nowday-59)
               var+=(rv[i]-mean)*(rv[i]-mean);
         var/=(k-1);
         double sd=MathSqrt(var);
         st.sharpe_ok=(sd>1e-12 ? 1 : 0);
         st.sharpe=(sd>1e-12 ? ss/sd : 0.0);
        }
     }
   st.best_ok=(nr>0 ? 1 : 0);
   st.best_pct=0; st.best_day=0; st.worst_pct=0; st.worst_day=0;
   if(nr>0)
     {
      int bi=0,wi=0;
      for(int i=0; i<nr; i++)
        {
         if(rv[i]>rv[bi]) bi=i;
         if(rv[i]<rv[wi]) wi=i;
        }
      st.best_pct=rv[bi]; st.best_day=rd[bi];
      st.worst_pct=rv[wi]; st.worst_day=rd[wi];
     }
   st.first_day=(ntr>0 ? tr[0].close_time/VT_DAY : 0);
  }

#endif
//+------------------------------------------------------------------+
