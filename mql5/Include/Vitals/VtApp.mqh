//+------------------------------------------------------------------+
//|                                                        VtApp.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| The program: inputs, events, the 1 s timer, the card chrome.     |
//| Read-only: no order is ever placed, changed or closed.           |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef VTAPP_MQH
#define VTAPP_MQH
#include "VtViews.mqh"

#define VT_NAME "Vitals"

input group "Filters (trades, positions, risk and exposure; account figures are never filtered)"
input bool   InpThisSymbol = false;              // Only the chart's symbol
input long   InpMagic      = -1;                 // Only this magic number (-1 = all)
input string InpComment    = "";                 // Only comments containing
input string InpStartDate  = "";                 // Ignore trades closed before (YYYY.MM.DD)
input group "Display"
input ENUM_VT_THEME InpTheme = VT_THEME_AUTO;    // Theme
input double InpScale      = 1.0;                // UI scale (multiplies the screen DPI scale)

const string VT_PREFIX="VITALS_CARD_";
const string VT_TAB_NAMES[3]={"Overview","History","Stats"};

CVtHistory g_hist;
bool       g_tester=false;
long       g_filter_start=0;
bool       g_hist_dirty=true;
int        g_report_ver=0;
string     g_last_sig="";
ulong      g_last_theme_ms=0;
double     g_h_tab[3];
bool       g_scroll_orig=true,g_mouse_orig=false;
ulong      g_perf_rebuild_us=0,g_perf_timer_us=0;
int        g_perf_timer_n=0;
long       g_tester_tick=0;
long       g_jr_login=0;               // the account the journal belongs to
ulong      g_last_tick_ms=0;

int VtTabCount() { return(3); }

//--- filter text for the footer
string VtFilterText()
  {
   string p[];
   int n=0;
   ArrayResize(p,4);
   p[n++]=(InpThisSymbol ? _Symbol : "All symbols");
   p[n++]=(InpMagic>=0 ? "magic "+IntegerToString(InpMagic) : "all magics");
   if(InpComment!="")
      p[n++]="comment \""+InpComment+"\"";
   p[n++]=(g_filter_start>0 ? "from "+InpStartDate : "all history");
   string o="";
   for(int i=0; i<n; i++)
      o+=(i>0 ? " "+ShortToString(0x00B7)+" " : "")+p[i];
   return(o);
  }

void VtApplyFilter()
  {
   g_filter_start=0;
   if(InpStartDate!="")
     {
      datetime t=StringToTime(InpStartDate);
      if(t>0)
         g_filter_start=(long)t;
     }
   g_eng.Filter(InpThisSymbol ? _Symbol : "",InpMagic,InpComment,g_filter_start);
   g_filter_text=VtFilterText();
  }

//--- one refresh of everything the card shows -----------------------------------------------------------------------
void VtRefresh()
  {
   VtReadAccount(g_acct);
   g_server_now=(long)TimeTradeServer();
   if(g_acct.login!=g_jr_login && g_jr_login!=0)      // another account logged in: its own journal and caches
     {
      g_jr.Flush(true,GetTickCount());
      g_jr.Init("Vitals\\FDD_"+IntegerToString(g_acct.login)+".csv",GetTickCount());
      g_jr_login=g_acct.login;
      g_hist_dirty=true;
     }
   bool rebuilt=false;
   ulong t0=GetMicrosecondCount();
   if(g_hist.Refresh(g_eng,rebuilt))
      g_hist_dirty=true;
   if(rebuilt)
      g_perf_rebuild_us=GetMicrosecondCount()-t0;
   g_npos=VtReadPositions(g_pos,g_acct.ccy);
  }

void VtRecompute()
  {
   VtSummarize(g_eng,g_pos,g_npos,g_acct.balance);
   g_eng.Report(g_server_now,g_acct.balance,g_jr.d,g_jr.m,g_jr.p,g_jr.n);
   g_report_ver++;
   g_hist_dirty=false;
  }

//--- journal sample with the time of today's new low
void VtSample()
  {
   long today=g_server_now/86400;
   double before=0;
   if(g_jr.n>0 && g_jr.d[g_jr.n-1]==today)
      before=g_jr.m[g_jr.n-1];
   int n0=g_jr.n;
   g_jr.Sample(g_server_now,g_acct.equity-g_acct.credit,g_acct.balance,GetTickCount());
   double after=0;
   if(g_jr.n>0 && g_jr.d[g_jr.n-1]==today)
      after=g_jr.m[g_jr.n-1];
   if(after<before || g_jr.n!=n0)
     {
      if(after<before)
         g_today_low_time=g_server_now;
      g_hist_dirty=true;
     }
  }

//--- drawing --------------------------------------------------------------------------------------------------------------
string VtAcctText()
  {
   string s=VtMaskLogin(g_acct.login)+" "+ShortToString(0x00B7)+" "+g_acct.server+" "+ShortToString(0x00B7)+" "+g_acct.ccy+
            " "+ShortToString(0x00B7)+" 1:"+IntegerToString(g_acct.leverage)+" "+ShortToString(0x00B7)+" "+g_acct.mode;
   return(s);
  }

void VtChromeTop(CVtCard &c)
  {
   //--- header: brand, account, fold button
   c.Txt(10,7,"VITALS",c.pal.ink,VTK_BRAND);
   int bw=c.TextW("VITALS",VTK_BRAND);
   double ax=10+bw+8;
   string t=VtAcctText();
   double room=VT_CARD_W-34-ax;
   while(StringLen(t)>4 && c.TextW(t,VTK_SMALL)>room)
      t=StringSubstr(t,0,StringLen(t)-2);
   if(t!=VtAcctText())
      t+=ShortToString(0x2026);
   c.Txt(ax,8,t,c.pal.label,VTK_SMALL);
   c.Zone(0,0,VT_CARD_W,28,VTZ_HEAD);
   c.Box(VT_CARD_W-28,5,VT_CARD_W-8,23,c.pal.edge);
   c.Txt(VT_CARD_W-18,6,c.folded ? "+" : ShortToString(0x2013),c.pal.label,VTK_MONO,2);
   c.Zone(VT_CARD_W-30,3,VT_CARD_W-6,25,VTZ_FOLD);
  }

void VtChromeTabs(CVtCard &c)
  {
   double x=0;
   int n=VtTabCount();
   for(int i=0; i<n; i++)
     {
      double w=c.TextW(VT_TAB_NAMES[i],VTK_SANS)+18;
      bool on=(i==c.tab);
      c.Txt(x+w/2.0,36,VT_TAB_NAMES[i],on ? c.pal.ink : c.pal.label,VTK_SANS,2);
      if(on)
         c.Fill(x,52,x+w,54,c.pal.acc);
      c.Zone(x,28,x+w,55,VTZ_TAB,i);
      x+=w;
     }
   c.HLine(0,VT_CARD_W,54,c.pal.edge);
   // drawn after the active underline so the rule stays under it
   if(c.tab<n)
     {
      double xs=0;
      for(int i=0; i<c.tab; i++)
         xs+=c.TextW(VT_TAB_NAMES[i],VTK_SANS)+18;
      c.Fill(xs,52,xs+c.TextW(VT_TAB_NAMES[c.tab],VTK_SANS)+18,54,c.pal.acc);
     }
  }

double VtChromeFoot(CVtCard &c,const double y)
  {
   c.HLine(10,VT_CARD_W-10,y,c.pal.rule);
   string left=g_filter_text;
   while(StringLen(left)>4 && c.TextW(left,VTK_SMALL)>VT_CARD_W-24-100)
      left=StringSubstr(left,0,StringLen(left)-2);
   c.Txt(12,y+5,left,c.pal.dim,VTK_SMALL);
   c.Txt(VT_CARD_W-12,y+5,"Allan Ni"+ShortToString(0x00F1)+"al",c.pal.dim,VTK_SMALL,1);
   double end=y+24;
   return(end);
  }

double VtDrawBody(CVtCard &c)
  {
   switch(c.tab)
     {
      case 0: return(VtDrawOverview(c));
      case 1: return(VtDrawHistory(c));
      case 2: return(VtDrawStats(c));
     }
   return(VT_BODY_TOP+10);
  }

void VtPaint(const double total)
  {
   g_card.ZoneReset();
   g_card.Frame(g_card.folded ? 29 : total);
   VtChromeTop(g_card);
  }

void VtRedraw()
  {
   if(!g_card.ok)
      return;
   if(g_card.folded)
     {
      g_card.Resize(29);
      VtPaint(29);
      g_card.Update();
      return;
     }
   double guess=(g_h_tab[g_card.tab]>0 ? g_h_tab[g_card.tab] : 360);
   for(int pass=0; pass<2; pass++)
     {
      g_card.Resize(guess);
      VtPaint(guess);
      VtChromeTabs(g_card);
      double y=VtDrawBody(g_card);
      double total=VtChromeFoot(g_card,y+4);
      total+=4;
      if(MathAbs(total-guess)<0.5)
        { g_h_tab[g_card.tab]=total; break; }
      guess=total;
      g_h_tab[g_card.tab]=total;
      if(pass==1)
        { g_card.Resize(guess); VtPaint(guess); VtChromeTabs(g_card); y=VtDrawBody(g_card); VtChromeFoot(g_card,y+4); }
     }
   g_card.Clamp();
   g_card.Update();
  }

string VtSignature()
  {
   VtAcct a=g_acct;
   return(StringFormat("%.2f|%.2f|%.2f|%.2f|%.2f|%d|%.2f|%d|%d|%d|%d|%I64d",a.equity,a.balance,a.margin,a.free,a.level,g_npos,
                       g_eng.o_pl[2],g_card.tab,g_card.folded,g_report_ver,g_card.light,g_server_now/86400));
  }

void VtTick(const bool force)
  {
   ulong t0=GetMicrosecondCount();
   g_last_tick_ms=GetTickCount();
   VtRefresh();
   VtSample();
   if(g_hist_dirty)
      VtRecompute();
   else
      VtSummarize(g_eng,g_pos,g_npos,g_acct.balance);
   if(g_card.ok)
     {
      if(GetTickCount()-g_last_theme_ms>3000)
        {
         g_last_theme_ms=GetTickCount();
         bool was=g_card.light;
         g_card.SetTheme(InpTheme);
         if(was!=g_card.light)
            g_last_sig="";
        }
      string sig=VtSignature();
      if(force || sig!=g_last_sig)
        {
         g_last_sig=sig;
         VtRedraw();
        }
     }
   g_perf_timer_us+=GetMicrosecondCount()-t0;
   g_perf_timer_n++;
   if(g_tester && (g_perf_timer_n==1 || g_perf_timer_n%1500==0))      // proof of life in the tester log
      PrintFormat("Vitals: tester tick %d at %s: balance %.2f equity %.2f, %d deals read, %d trades, %d journal days, report %d",
                  g_perf_timer_n,TimeToString((datetime)g_server_now),g_acct.balance,g_acct.equity,g_hist.ndeals,g_eng.ntr,g_jr.n,g_report_ver);
  }

//--- OnCalculate: keep the journal fed on every tick
void VtCalc()
  {
   VtReadAccount(g_acct);
   g_server_now=(long)TimeTradeServer();
   VtSample();
   if(g_tester && g_server_now-g_tester_tick>=60)     // the tester does not deliver OnTimer to an indicator
     {
      g_tester_tick=g_server_now;
      VtTick(false);
     }
   if(!g_tester && g_card.ok && GetTickCount()-g_last_tick_ms>=2500)   // the timer normally keeps this fresh
      VtTick(false);
  }

//--- clicks ---------------------------------------------------------------------------------------------------------------
void VtClick(const int id,const int arg)
  {
   switch(id)
     {
      case VTZ_FOLD:
         g_card.folded=!g_card.folded;
         g_card.Save();
         break;
      case VTZ_TAB:
         if(arg>=0 && arg<VtTabCount())
           { g_card.tab=arg; g_card.Save(); }
         break;
     }
   g_last_sig="";
   VtRedraw();
  }

void VtMouse(const int mx,const int my,const int flags)
  {
   if(!g_card.ok)
      return;
   bool down=((flags&1)!=0);
   if(down && !g_card.m_down)                      // press
     {
      g_card.m_down=true;
      g_card.m_press_x=mx; g_card.m_press_y=my;
      g_card.m_hit_card=g_card.Inside(mx,my);
      g_card.m_drag=false;
      if(g_card.m_hit_card)
        {
         g_card.m_scroll_saved=true;
         ChartSetInteger(g_card.chart,CHART_MOUSE_SCROLL,false);
         int id,arg;
         if(g_card.ZoneAt(mx-g_card.px,my-g_card.py,id,arg) && id==VTZ_HEAD)
           { g_card.m_drag=true; g_card.m_off_x=mx-g_card.px; g_card.m_off_y=my-g_card.py; }
        }
     }
   else
      if(down && g_card.m_down)                    // move with the button down
        {
         if(g_card.m_drag)
           {
            g_card.MoveTo(mx-g_card.m_off_x,my-g_card.m_off_y);
            g_card.Clamp();
            ChartRedraw(g_card.chart);
           }
        }
      else
         if(!down && g_card.m_down)                // release
           {
            g_card.m_down=false;
            if(g_card.m_scroll_saved)
              {
               ChartSetInteger(g_card.chart,CHART_MOUSE_SCROLL,g_scroll_orig);
               g_card.m_scroll_saved=false;
              }
            bool moved=(MathAbs(mx-g_card.m_press_x)>4 || MathAbs(my-g_card.m_press_y)>4);
            if(g_card.m_drag && moved)
               g_card.Save();
            else
               if(g_card.m_hit_card && !moved)
                 {
                  int id,arg;
                  if(g_card.ZoneAt(mx-g_card.px,my-g_card.py,id,arg) && id!=VTZ_HEAD)
                     VtClick(id,arg);
                 }
            g_card.m_drag=false;
           }
  }

//--- start-up and shut-down -----------------------------------------------------------------------------------------------
int VtInit()
  {
   g_tester=(bool)MQLInfoInteger(MQL_TESTER);
   for(int i=0; i<3; i++)
      g_h_tab[i]=0;
   VtApplyFilter();
   VtReadAccount(g_acct);
   g_server_now=(long)TimeTradeServer();
   g_jr.Init("Vitals\\FDD_"+IntegerToString(g_acct.login)+".csv",GetTickCount());
   g_jr_login=g_acct.login;
   if(!g_tester)
     {
      g_scroll_orig=(bool)ChartGetInteger(0,CHART_MOUSE_SCROLL);
      g_mouse_orig=(bool)ChartGetInteger(0,CHART_EVENT_MOUSE_MOVE);
      ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
      g_card.scale=CVtCard::ScaleFor(InpScale);
      if(g_card.Create(VT_PREFIX+VT_NAME+"_"+IntegerToString(ChartID()),VT_CARD_W,360))
        {
         g_card.Load(12,22);
         g_card.SetTheme(InpTheme);
         if(g_card.tab<0 || g_card.tab>=VtTabCount())
            g_card.tab=0;
         g_card.MoveTo(g_card.px,g_card.py);
        }
     }
   VtRefresh();
   VtSample();
   VtRecompute();
   bool tm=EventSetTimer(1);
   VtTick(true);
   return(INIT_SUCCEEDED);
  }

void VtDeinit(const int reason)
  {
   EventKillTimer();
   g_jr.Flush(true,GetTickCount());
   if(!g_tester)
     {
      ChartSetInteger(0,CHART_MOUSE_SCROLL,g_scroll_orig);
      ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,g_mouse_orig);
     }
   if(g_perf_timer_n>0)
      PrintFormat("Vitals: tab %d, history rebuild %.1f ms; timer cost %.0f us average over %d ticks",g_card.tab,g_perf_rebuild_us/1000.0,
                  (double)g_perf_timer_us/g_perf_timer_n,g_perf_timer_n);
   if(g_card.ok)
     {
      g_card.Save();
      g_card.Destroy();
     }
  }

void VtTimer()
  {
   VtTick(false);
  }

void VtEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_MOUSE_MOVE)
      VtMouse((int)lparam,(int)dparam,(int)StringToInteger(sparam));
   else
      if(id==CHARTEVENT_CHART_CHANGE && g_card.ok)
        {
         g_card.Clamp();
         g_last_theme_ms=0;
        }
  }

#endif
//+------------------------------------------------------------------+
