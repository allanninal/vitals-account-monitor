//+------------------------------------------------------------------+
//|                                                      VtViews.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| The model and the three tabs: Overview, History and Stats. Each |
//| Draw* function paints into the card from the body top and        |
//| returns the y (logical units) where it ended.                    |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef VTVIEWS_MQH
#define VTVIEWS_MQH
#include "VtCore.mqh"
#include "VtExposure.mqh"
#include "VtJournal.mqh"
#include "VtLive.mqh"
#include "VtCard.mqh"

#define VT_BODY_X   12
#define VT_BODY_R   448
#define VT_BODY_TOP 64

//--- the model the views read
CVtEngine  g_eng;
CVtJournal g_jr;
CVtCard    g_card;
VtAcct     g_acct;
VtPos      g_pos[];
int        g_npos=0;
long       g_server_now=0;
long       g_today_low_time=0;          // when today's floating low was set (memory only)
string     g_filter_text="";

//--- formatting -----------------------------------------------------------------------------------------------------
string VtMinus() { return(ShortToString(0x2212)); }

string VtGroup(const string s)           // 1234567.89 -> 1,234,567.89
  {
   int dot=StringFind(s,".");
   string ip=(dot>=0 ? StringSubstr(s,0,dot) : s),fp=(dot>=0 ? StringSubstr(s,dot) : "");
   string o="";
   int n=StringLen(ip);
   for(int i=0; i<n; i++)
     {
      o+=StringSubstr(ip,i,1);
      int left=n-1-i;
      if(left>0 && left%3==0)
         o+=",";
     }
   return(o+fp);
  }
string VtNum(const double v,const int d=2)
  {
   string s=VtGroup(DoubleToString(MathAbs(v),d));
   return(v<0 && StringToDouble(DoubleToString(MathAbs(v),d))>0 ? VtMinus()+s : s);
  }
string VtSgn(const double v,const int d=2)
  {
   double r=StringToDouble(DoubleToString(MathAbs(v),d));
   if(r==0)
      return(VtGroup(DoubleToString(0,d)));
   return((v<0 ? VtMinus() : "+")+VtGroup(DoubleToString(MathAbs(v),d)));
  }
color VtSignClr(const double v,const int d=2)
  {
   double r=StringToDouble(DoubleToString(MathAbs(v),d));
   return(r==0 ? g_card.pal.dim : (v>0 ? g_card.pal.pos : g_card.pal.neg));
  }
string VtWd3(const long day)
  {
   string n[7]={"Mon","Tue","Wed","Thu","Fri","Sat","Sun"};
   return(n[VtWeekday(day)]);
  }
string VtMon3(const int m)
  {
   string n[12]={"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
   return(n[(m-1+12)%12]);
  }
string VtMonFull(const int m)
  {
   string n[12]={"January","February","March","April","May","June","July","August","September","October","November","December"};
   return(n[(m-1+12)%12]);
  }
string VtDM(const long day)                  // "12 Oct"
  {
   int y,m,d;
   VtCivil(day,y,m,d);
   return(IntegerToString(d)+" "+VtMon3(m));
  }
string VtDMY(const long day)                 // "5 Jan 2026"
  {
   int y,m,d;
   VtCivil(day,y,m,d);
   return(IntegerToString(d)+" "+VtMon3(m)+" "+IntegerToString(y));
  }
string VtHM(const long t)
  {
   return(StringFormat("%02d:%02d",(int)((t%86400)/3600),(int)((t%3600)/60)));
  }
string VtMaskLogin(const long login)
  {
   string s=IntegerToString(login);
   int n=StringLen(s);
   if(n<7)
      return(s);
   return(StringSubstr(s,0,4)+ShortToString(0x2022)+ShortToString(0x2022)+ShortToString(0x2022)+StringSubstr(s,n-2));
  }
//--- building blocks ------------------------------------------------------------------------------------------------
double VtSec(CVtCard &c,const double y,const string left,const string right="",const color rclr=clrNONE)
  {
   string u=left;
   StringToUpper(u);
   c.Txt(VT_BODY_X,y,u,c.pal.label,VTK_SEC);
   if(right!="")
      c.Txt(VT_BODY_R,y,right,rclr==clrNONE ? c.pal.dim : rclr,VTK_SMALL,1);
   return(y+16);
  }

void VtKV(CVtCard &c,const double x1,const double x2,const double y,const string k,const string v,const color vc)
  {
   c.Txt(x1,y,k,c.pal.label,VTK_SANS);
   c.Txt(x2,y,v,vc,VTK_MONO,1);
  }

//--- OVERVIEW ---------------------------------------------------------------------------------------------------------
double VtDrawOverview(CVtCard &c)
  {
   double y=VT_BODY_TOP;
   VtAcct a=g_acct;
   double floating=a.equity-a.balance-a.credit;
   //--- hero
   c.Txt(VT_BODY_X,y,"EQUITY",c.pal.label,VTK_SEC);
   c.Txt(190,y,"BALANCE",c.pal.label,VTK_SEC);
   c.Txt(320,y,"FLOATING",c.pal.label,VTK_SEC);
   c.Txt(VT_BODY_X,y+12,VtNum(a.equity),c.pal.ink,VTK_BIG);
   c.Txt(VT_BODY_X,y+40,a.balance>0 ? DoubleToString(100.0*a.equity/a.balance,2)+"% of balance" : "-",c.pal.label,VTK_MONOS);
   c.Txt(190,y+16,VtNum(a.balance),c.pal.ink,VTK_MONO);
   c.Txt(320,y+16,VtSgn(floating),VtSignClr(floating),VTK_MONO);
   c.Txt(320,y+34,a.balance>0 ? VtSgn(100.0*floating/a.balance)+"%" : "-",VtSignClr(floating),VTK_MONOS);
   y+=60;
   //--- floating drawdown
   string since="";
   if(g_jr.n>0)
      since="journal since "+VtDM(g_jr.d[0]);
   y=VtSec(c,y,"Floating drawdown",since);
   double now_pct=(a.balance>0 && floating<0 ? 100.0*floating/a.balance : 0.0);
   long today=g_server_now/86400;
   double tw_pct=0,tw_money=0;
   bool tw_ok=false;
   if(g_jr.n>0 && g_jr.d[g_jr.n-1]==today)
     { tw_pct=g_jr.p[g_jr.n-1]; tw_money=g_jr.m[g_jr.n-1]; tw_ok=true; }
   double ww_pct=0;
   long   ww_day=0;
   bool   ww_ok=false;
   for(int i=0; i<g_jr.n; i++)
      if(!ww_ok || g_jr.p[i]<ww_pct)
        { ww_pct=g_jr.p[i]; ww_day=g_jr.d[i]; ww_ok=true; }
   double mx=MathMax(MathMax(MathAbs(ww_pct),MathAbs(tw_pct)),MathMax(MathAbs(now_pct),0.0001));
   double gx1=VT_BODY_X,gx2=VT_BODY_R,gy=y+2,gh=16;
   c.Fill(gx1,gy,gx2,gy+gh,c.pal.track);
   double wfull=gx2-gx1;
   if(tw_ok && tw_pct<0)
      c.Fill(gx2-wfull*MathAbs(tw_pct)/mx,gy,gx2,gy+gh,c.pal.neg,90);
   if(now_pct<0)
      c.Fill(gx2-wfull*MathAbs(now_pct)/mx,gy,gx2,gy+gh,c.pal.neg);
   if(tw_ok && tw_pct<0)
      c.Fill(gx2-wfull*MathAbs(tw_pct)/mx-1,gy-3,gx2-wfull*MathAbs(tw_pct)/mx+1,gy+gh+3,c.pal.warn);
   y=gy+gh+7;
   c.Txt(VT_BODY_X,y,"Now",c.pal.label,VTK_SMALL);
   c.Txt(VT_BODY_X+30,y,now_pct<0 ? VtSgn(now_pct)+"%" : "0.00%",now_pct<0 ? c.pal.neg : c.pal.dim,VTK_MONOS);
   string twt=(tw_ok && tw_pct<0 ? VtSgn(tw_pct)+"%" : "0.00%");
   c.Txt(150,y,"Today's worst",c.pal.label,VTK_SMALL);
   c.Txt(150+78,y,twt,tw_ok && tw_pct<0 ? c.pal.warn : c.pal.dim,VTK_MONOS);
   if(tw_ok && tw_pct<0 && g_today_low_time>0 && g_today_low_time/86400==today)
      c.Txt(150+78+c.TextW(twt,VTK_MONOS)+6,y,VtHM(g_today_low_time),c.pal.dim,VTK_MONOS);
   string wwt=(ww_ok && ww_pct<0 ? VtSgn(ww_pct)+"%" : "-");
   c.Txt(VT_BODY_R,y,(ww_ok && ww_pct<0 ? VtDM(ww_day) : ""),c.pal.dim,VTK_MONOS,1);
   int dw=(ww_ok && ww_pct<0 ? c.TextW(VtDM(ww_day),VTK_MONOS)+6 : 0);
   c.Txt(VT_BODY_R-dw,y,wwt,ww_ok && ww_pct<0 ? c.pal.neg : c.pal.dim,VTK_MONOS,1);
   c.Txt(VT_BODY_R-dw-c.TextW(wwt,VTK_MONOS)-6,y,"Worst day",c.pal.label,VTK_SMALL,1);
   y+=20;
   //--- margin
   y=VtSec(c,y,"Margin");
   string lvl=(a.margin>0 ? VtNum(a.level,0)+"%" : "-");
   string so=(a.so_mode==VT_SO_PERCENT ? DoubleToString(a.so,0)+"%" : VtNum(a.so));
   VtKV(c,VT_BODY_X,206,y,"Used",VtNum(a.margin),c.pal.ink);
   VtKV(c,242,VT_BODY_R,y,"Free",VtNum(a.free),c.pal.ink);
   y+=17;
   VtKV(c,VT_BODY_X,206,y,"Level",lvl,c.pal.ink);
   VtKV(c,242,VT_BODY_R,y,"Stop out",so,c.pal.dim);
   y+=22;
   //--- open positions
   string rk="";
   color rkc=c.pal.dim;
   if(g_eng.o_nostop<g_eng.o_n[2] || g_eng.o_risk!=0)
     {
      rk="risk at stops "+VtSgn(g_eng.o_risk)+" ("+DoubleToString(MathAbs(g_eng.o_risk_pct),2)+"%)";
      rkc=(g_eng.o_risk<0 ? c.pal.neg : c.pal.pos);
     }
   y=VtSec(c,y,"Open positions",rk,rkc);
   double cx[5]={VT_BODY_X,236,284,364,VT_BODY_R};
   c.Txt(cx[1],y,"COUNT",c.pal.label,VTK_SEC,1);
   c.Txt(cx[2],y,"LOTS",c.pal.label,VTK_SEC,1);
   c.Txt(cx[3],y,"P/L",c.pal.label,VTK_SEC,1);
   c.Txt(cx[4],y,"PIPS",c.pal.label,VTK_SEC,1);
   y+=15;
   c.HLine(VT_BODY_X,VT_BODY_R,y,c.pal.rule);
   y+=3;
   string nm[3]={"Long","Short","Total"};
   for(int k=0; k<3; k++)
     {
      if(k==2)
        { c.HLine(VT_BODY_X,VT_BODY_R,y,c.pal.edge); y+=2; }
      c.Txt(cx[0],y,nm[k],k==2 ? c.pal.ink : c.pal.label,VTK_SANS);
      c.Txt(cx[1],y,IntegerToString(g_eng.o_n[k]),c.pal.ink,VTK_MONO,1);
      c.Txt(cx[2],y,DoubleToString(g_eng.o_lots[k],2),c.pal.ink,VTK_MONO,1);
      c.Txt(cx[3],y,VtSgn(g_eng.o_pl[k]),VtSignClr(g_eng.o_pl[k]),VTK_MONO,1);
      c.Txt(cx[4],y,VtSgn(g_eng.o_pips[k],1),VtSignClr(g_eng.o_pips[k],1),VTK_MONO,1);
      y+=17;
     }
   if(g_eng.o_nostop>0)
     {
      y+=3;
      string t=(g_eng.o_nostop==1 ? "1 position without a stop" : IntegerToString(g_eng.o_nostop)+" positions without a stop")+
               " "+ShortToString(0x00B7)+" "+g_eng.o_nostop_first+(g_eng.o_nostop>1 ? " +"+IntegerToString(g_eng.o_nostop-1) : "");
      int tw=c.TextW(t,VTK_SMALL);
      c.Box(VT_BODY_X,y,VT_BODY_X+tw+12,y+17,c.pal.warn);
      c.Txt(VT_BODY_X+6,y+2,t,c.pal.warn,VTK_SMALL);
      y+=22;
     }
   else
      y+=4;
   //--- exposure
   y=VtSec(c,y,"Exposure by currency","net, "+g_acct.ccy+" thousands");
   int rows=MathMin(g_eng.o_nex,6);
   if(rows==0)
     {
      c.Txt(VT_BODY_X,y,"No open positions",c.pal.dim,VTK_SMALL);
      y+=18;
     }
   double big=0;
   for(int i=0; i<rows; i++)
      big=MathMax(big,MathAbs(g_eng.ex_net[i]));
   for(int i=0; i<rows; i++)
     {
      double v=g_eng.ex_net[i];
      c.Txt(VT_BODY_X,y,g_eng.ex_name[i],c.pal.label,VTK_MONO);
      double mid=VT_BODY_X+42+(VT_BODY_R-70-VT_BODY_X-42)/2.0,half=(VT_BODY_R-70-VT_BODY_X-42)/2.0;
      c.VLine(mid,y,y+15,c.pal.edge);
      double bw=(big>0 ? MathAbs(v)/big*half : 0);
      if(v<0)
         c.Fill(mid-bw,y+3,mid,y+12,c.pal.neg,190);
      else
         c.Fill(mid,y+3,mid+bw,y+12,c.pal.pos,190);
      c.Txt(VT_BODY_R,y,VtSgn(v/1000.0,1)+"k",VtSignClr(v/1000.0,1),VTK_MONO,1);
      y+=17;
     }
   return(y);
  }

//--- HISTORY ----------------------------------------------------------------------------------------------------------
string VtRowLabel(const VtRow &r,const long today)
  {
   int y,m,d;
   if(r.kind==0)
     {
      VtCivil(r.day,y,m,d);
      if(r.day==today)
         return("Today "+ShortToString(0x00B7)+" "+VtWd3(r.day)+" "+IntegerToString(d));
      if(r.day==today-1)
         return("Yesterday "+ShortToString(0x00B7)+" "+VtWd3(r.day)+" "+IntegerToString(d));
      return(VtWd3(r.day)+" "+IntegerToString(d));
     }
   VtCivil(today,y,m,d);
   if(r.kind==1)
      return("Week");
   if(r.kind==2)
      return(VtMonFull(m));
   return(IntegerToString(y));
  }

void VtHistRow(CVtCard &c,const double y,const VtRow &r,const long today)
  {
   c.Txt(VT_BODY_X,y,VtRowLabel(r,today),c.pal.label,VTK_SANS);
   string wl=IntegerToString(r.w)+"/"+IntegerToString(r.l);
   c.Txt(194,y,r.n>0 ? wl : "",c.pal.dim,VTK_MONOS,1);
   int ww=(r.n>0 ? c.TextW(wl,VTK_MONOS)+5 : 0);
   c.Txt(194-ww,y,IntegerToString(r.n),c.pal.ink,VTK_MONO,1);
   c.Txt(262,y,VtSgn(r.net),VtSignClr(r.net),VTK_MONO,1);
   c.Txt(326,y,r.gain_ok ? VtSgn(r.gain)+"%" : "-",r.gain_ok ? VtSignClr(r.gain) : c.pal.dim,VTK_MONO,1);
   if(r.dd_ok)
     {
      bool zero=(StringToDouble(DoubleToString(MathAbs(r.dd_pct),2))==0);
      string t=(r.dd_approx ? "~" : "")+(zero ? "0.00%" : VtSgn(r.dd_pct)+"%");
      color col=(r.dd_approx || zero ? c.pal.dim : c.pal.neg);
      c.Txt(390,y,t,col,VTK_MONO,1);
     }
   else
      c.Txt(390,y,"-",c.pal.dim,VTK_MONO,1);
   c.Txt(VT_BODY_R,y,DoubleToString(r.lots,2),c.pal.ink,VTK_MONO,1);
  }

double VtDrawHistory(CVtCard &c)
  {
   double y=VT_BODY_TOP;
   long today=g_server_now/86400;
   string h[6]={"PERIOD","TRADES W/L","NET","GAIN","WORST DD","LOTS"};
   c.Txt(VT_BODY_X,y,h[0],c.pal.label,VTK_SEC);
   double hx[6]={0,194,262,326,390,VT_BODY_R};
   for(int i=1; i<6; i++)
      c.Txt(hx[i],y,h[i],c.pal.label,VTK_SEC,1);
   y+=15;
   c.HLine(VT_BODY_X,VT_BODY_R,y,c.pal.rule);
   y+=4;
   int nday=0;
   for(int i=0; i<g_eng.nrows; i++)
      if(g_eng.rows[i].kind==0)
         nday++;
   for(int i=0; i<g_eng.nrows; i++)
     {
      if(g_eng.rows[i].kind!=0 && g_eng.rows[i].kind==1)
        { y+=2; c.HLine(VT_BODY_X,VT_BODY_R,y,c.pal.edge); y+=4; }
      VtHistRow(c,y,g_eng.rows[i],today);
      y+=18;
     }
   y+=4;
   y=VtSec(c,y,"Averages");
   VtKV(c,VT_BODY_X,206,y,"Per trading day",g_eng.avg_day_ok ? VtSgn(g_eng.avg_day)+"%" : "-",g_eng.avg_day_ok ? VtSignClr(g_eng.avg_day) : c.pal.dim);
   VtKV(c,242,VT_BODY_R,y,"Per month",g_eng.avg_month_ok ? VtSgn(g_eng.avg_month)+"%" : "-",g_eng.avg_month_ok ? VtSignClr(g_eng.avg_month) : c.pal.dim);
   y+=22;
   c.Txt(VT_BODY_X,y,"Net includes commission, swap and fees. Worst DD is the day's deepest",c.pal.dim,VTK_SMALL);
   c.Txt(VT_BODY_X,y+13,"floating drawdown from the journal; ~ marks days before the journal,",c.pal.dim,VTK_SMALL);
   c.Txt(VT_BODY_X,y+26,"taken from closed trades. Week, month and year show their worst day.",c.pal.dim,VTK_SMALL);
   return(y+42);
  }

//--- STATS ------------------------------------------------------------------------------------------------------------
void VtStatCell(CVtCard &c,const double x,const double y,const string k,const string v,const string sub,const color vc)
  {
   string u=k;
   StringToUpper(u);
   c.Txt(x,y,u,c.pal.label,VTK_SEC);
   c.Txt(x,y+13,v,vc,VTK_MONO);
   c.Txt(x,y+30,sub,c.pal.dim,VTK_MONOS);
  }

double VtDrawStats(CVtCard &c)
  {
   double y=VT_BODY_TOP;
   VtStats s=g_eng.st;
   string right="";
   if(s.n>0)
      right="since "+VtDMY(s.first_day)+" "+ShortToString(0x00B7)+" "+DoubleToString(s.lots,2)+" lots";
   y=VtSec(c,y,"Account statistics",right);
   double col[3]={VT_BODY_X,166,320};
   int i=0;
   string m=VtMinus();
   bool any=(s.n>0);
   //--- row 1
   VtStatCell(c,col[0],y,"Win rate",any ? DoubleToString(s.winrate,1)+"%" : "-",any ? IntegerToString(s.w)+" of "+IntegerToString(s.n) : "",c.pal.ink);
   VtStatCell(c,col[1],y,"Profit factor",s.pf_ok ? DoubleToString(s.pf,2) : (any && s.gp>0 ? "no losses" : "-"),"",c.pal.ink);
   VtStatCell(c,col[2],y,"Expectancy",any ? VtSgn(s.expct) : "-",any ? "per trade" : "",any ? VtSignClr(s.expct) : c.pal.dim);
   y+=48;
   VtStatCell(c,col[0],y,"Avg win",s.w>0 ? VtSgn(s.avgwin) : "-","",s.w>0 ? c.pal.pos : c.pal.dim);
   VtStatCell(c,col[1],y,"Avg loss",s.l>0 ? VtSgn(s.avgloss) : "-","",s.l>0 ? c.pal.neg : c.pal.dim);
   VtStatCell(c,col[2],y,"Reward/risk",(s.w>0 && s.l>0) ? DoubleToString(s.rr,2) : "-",(s.w>0 && s.l>0) ? "avg win / avg loss" : "",c.pal.ink);
   y+=48;
   VtStatCell(c,col[0],y,"Max drawdown",s.maxdd_money>0 ? m+DoubleToString(s.maxdd_pct,2)+"%" : (any ? "0.00%" : "-"),
              s.maxdd_money>0 ? m+VtNum(s.maxdd_money)+" "+ShortToString(0x00B7)+" "+VtDM(s.maxdd_time/86400) : "",s.maxdd_money>0 ? c.pal.neg : c.pal.dim);
   VtStatCell(c,col[1],y,"Relative DD",s.rel_pct>0 ? m+DoubleToString(s.rel_pct,2)+"%" : (any ? "0.00%" : "-"),
              s.rel_pct>0 ? m+VtNum(s.rel_money)+" "+ShortToString(0x00B7)+" "+VtDM(s.rel_time/86400) : "",s.rel_pct>0 ? c.pal.neg : c.pal.dim);
   VtStatCell(c,col[2],y,"Sharpe "+ShortToString(0x00B7)+" 60 days",s.sharpe_ok ? DoubleToString(s.sharpe,2) : "-",s.sharpe_ok ? "daily returns" : "needs 2+ trading days",c.pal.ink);
   y+=48;
   VtStatCell(c,col[0],y,"Best day",s.best_ok ? VtSgn(s.best_pct)+"%" : "-",s.best_ok ? VtDM(s.best_day) : "",s.best_ok ? VtSignClr(s.best_pct) : c.pal.dim);
   VtStatCell(c,col[1],y,"Worst day",s.best_ok ? VtSgn(s.worst_pct)+"%" : "-",s.best_ok ? VtDM(s.worst_day) : "",s.best_ok ? VtSignClr(s.worst_pct) : c.pal.dim);
   double costs=s.comm+s.swap+s.fee;
   VtStatCell(c,col[2],y,"Costs",any ? VtSgn(costs) : "-","",any ? VtSignClr(costs) : c.pal.dim);
   y+=50;
   if(any)
     {
      c.Txt(VT_BODY_X,y,"commission "+VtSgn(s.comm)+"  "+ShortToString(0x00B7)+"  swap "+VtSgn(s.swap)+"  "+ShortToString(0x00B7)+"  fees "+VtSgn(s.fee),
            c.pal.dim,VTK_MONOS);
      y+=16;
     }
   else
     {
      c.Txt(VT_BODY_X,y,"No closed trades in the history yet.",c.pal.dim,VTK_SMALL);
      y+=16;
     }
   c.Txt(VT_BODY_X,y,"Max and relative drawdown: closed-trade balance curve.",c.pal.dim,VTK_SMALL);
   c.Txt(VT_BODY_X,y+13,"Sharpe: cumulative return / stdev of daily returns, last 60 days.",c.pal.dim,VTK_SMALL);
   return(y+30);
  }

#endif
//+------------------------------------------------------------------+
