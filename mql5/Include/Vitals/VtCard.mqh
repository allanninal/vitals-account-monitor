//+------------------------------------------------------------------+
//|                                                       VtCard.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| The Vitals card: one CCanvas bitmap label on the chart.          |
//|   - Scale = screen DPI / 96 x the UI-scale input.                |
//|   - Theme: Auto (from the chart background), Dark or Light.      |
//|   - Drag by the header, fold to the header, click the tabs;      |
//|     chart scrolling is paused while the mouse is down on it.     |
//|   - Position, fold and tab are kept per chart in terminal global |
//|     variables.                                                   |
//| Everything is drawn in logical units (pixels at 100 % scale) and |
//| multiplied by the scale. If the chart refuses the object (the    |
//| strategy tester) the card stays silent.                          |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef VTCARD_MQH
#define VTCARD_MQH
#include <Canvas/Canvas.mqh>

enum ENUM_VT_THEME
  {
   VT_THEME_AUTO=0,    // Auto (from the chart background)
   VT_THEME_DARK=1,    // Dark
   VT_THEME_LIGHT=2    // Light
  };

#define VT_CARD_W   460          // logical width
#define VT_ZMAX     96

struct VtPalette
  {
   color bg;
   uchar bg_a;
   color edge,head,ink,label,dim,pos,neg,warn,acc,track,rule;
  };

struct VtZone
  {
   int x1,y1,x2,y2;
   int id,arg;
  };

//--- zone ids
#define VTZ_HEAD   1
#define VTZ_FOLD   2
#define VTZ_TAB    3

//--- text kinds
#define VTK_SANS   0
#define VTK_MONO   1
#define VTK_SMALL  2
#define VTK_BIG    3
#define VTK_SEC    4
#define VTK_BRAND  5
#define VTK_MONOS  6      // small mono

class CVtCard
  {
public:
   CCanvas   cv;
   string    name;
   long      chart;
   bool      ok;
   int       px,py;                  // position on the chart (pixels)
   int       pw,ph;                  // size (pixels)
   double    scale;
   bool      light;
   bool      folded;
   int       tab;
   VtPalette pal;
   VtZone    zones[VT_ZMAX];
   int       nz;
   //--- font cache
   string    m_face;
   int       m_size,m_flags;
   //--- interaction
   bool      m_down,m_drag,m_hit_card;
   int       m_press_x,m_press_y,m_off_x,m_off_y;
   bool      m_scroll_saved;
   //--- fonts (changeable for tests)
   string    face_sans,face_mono;

            CVtCard(): ok(false),px(12),py(22),pw(0),ph(0),scale(1.0),light(false),folded(false),tab(0),nz(0),
                       m_down(false),m_drag(false),m_hit_card(false),m_scroll_saved(false)
     { face_sans="Segoe UI"; face_mono="Consolas"; m_face=""; m_size=0; m_flags=0; }

   //--- scale: DPI/96 x the UI-scale input
   static double ScaleFor(const double ui)
     {
      double dpi=(double)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
      if(dpi<=0)
         dpi=96;
      return(MathMax(0.5,MathMin(4.0,dpi/96.0*ui)));
     }
   int      S(const double v) const { return((int)MathRound(v*scale)); }

   void     SetTheme(const ENUM_VT_THEME t)
     {
      bool l=false;
      if(t==VT_THEME_LIGHT)
         l=true;
      else
         if(t==VT_THEME_AUTO)
           {
            color bg=(color)ChartGetInteger(chart,CHART_COLOR_BACKGROUND);
            double lum=0.2126*(bg&0xFF)+0.7152*((bg>>8)&0xFF)+0.0722*((bg>>16)&0xFF);
            l=(lum>127.5);
           }
      light=l;
      if(!light)
        {
         pal.bg=C'21,26,30'; pal.bg_a=255; pal.edge=C'42,51,56'; pal.head=C'26,32,36'; pal.ink=C'215,222,226';
         pal.label=C'139,151,158'; pal.dim=C'91,102,108'; pal.pos=C'98,184,140'; pal.neg=C'224,123,112';
         pal.warn=C'217,166,72'; pal.acc=C'115,169,214'; pal.track=C'37,45,50'; pal.rule=C'35,43,47';
        }
      else
        {
         pal.bg=C'250,251,250'; pal.bg_a=255; pal.edge=C'214,219,221'; pal.head=C'239,242,241'; pal.ink=C'30,37,40';
         pal.label=C'95,107,113'; pal.dim=C'154,164,169'; pal.pos=C'46,134,87'; pal.neg=C'193,73,62';
         pal.warn=C'168,118,26'; pal.acc=C'47,111,166'; pal.track=C'228,232,232'; pal.rule=C'227,231,231';
        }
     }

   bool     Create(const string objname,const int w_logical,const double h_logical)
     {
      chart=ChartID();
      name=objname;
      pw=S(w_logical); ph=S(h_logical);
      ObjectDelete(chart,name);
      ok=cv.CreateBitmapLabel(chart,0,name,px,py,pw,ph,COLOR_FORMAT_ARGB_NORMALIZE);
      if(ok)
        {
         ObjectSetInteger(chart,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(chart,name,OBJPROP_HIDDEN,true);
         ObjectSetInteger(chart,name,OBJPROP_BACK,false);
         ObjectSetInteger(chart,name,OBJPROP_ZORDER,100);
         ObjectSetInteger(chart,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(chart,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
        }
      return(ok);
     }
   void     Destroy()
     {
      if(ok)
         cv.Destroy();
      ok=false;
      ObjectDelete(chart,name);
     }
   //--- change the bitmap size (logical height); the content is redrawn by the caller
   bool     Resize(const double h_logical)
     {
      int nh=S(h_logical);
      if(!ok || nh==ph)
         return(true);
      ph=nh;
      return(cv.Resize(pw,ph));
     }
   void     MoveTo(const int x,const int y)
     {
      px=x; py=y;
      if(ok)
        {
         ObjectSetInteger(chart,name,OBJPROP_XDISTANCE,px);
         ObjectSetInteger(chart,name,OBJPROP_YDISTANCE,py);
        }
     }
   void     Clamp()
     {
      int cw=(int)ChartGetInteger(chart,CHART_WIDTH_IN_PIXELS);
      int ch=(int)ChartGetInteger(chart,CHART_HEIGHT_IN_PIXELS);
      int nx=MathMax(0,MathMin(px,cw-pw));
      int ny=MathMax(0,MathMin(py,ch-MathMin(ph,S(34))));     // always keep the header reachable
      if(cw<=pw)
         nx=0;
      if(nx!=px || ny!=py)
         MoveTo(nx,ny);
     }

   //--- state kept per chart
   string   Key(const string k) const { return("VITALS_"+IntegerToString(chart)+"_"+k); }
   void     Load(const int defx,const int defy)
     {
      px=S(defx); py=S(defy);
      if(GlobalVariableCheck(Key("x")))
        { px=(int)GlobalVariableGet(Key("x")); py=(int)GlobalVariableGet(Key("y")); }
      folded=(GlobalVariableCheck(Key("fold")) && GlobalVariableGet(Key("fold"))>0.5);
      tab=(GlobalVariableCheck(Key("tab")) ? (int)GlobalVariableGet(Key("tab")) : 0);
     }
   void     Save()
     {
      GlobalVariableSet(Key("x"),px);
      GlobalVariableSet(Key("y"),py);
      GlobalVariableSet(Key("fold"),folded ? 1 : 0);
      GlobalVariableSet(Key("tab"),tab);
     }

   //--- drawing -------------------------------------------------------------------------------------------------------
   //--- the card is fully opaque: a translucent colour is pre-blended with the card background instead of letting the
   //    canvas lower the pixel alpha (candles showed through bars drawn with alpha < 255)
   uint     A(const color c,const int alpha=255) const
     {
      if(alpha>=255)
         return(ColorToARGB(c,255));
      int r=(c&0xFF),g=((c>>8)&0xFF),b=((c>>16)&0xFF);
      int br=(pal.bg&0xFF),bgg=((pal.bg>>8)&0xFF),bb=((pal.bg>>16)&0xFF);
      color m=(color)(((r*alpha+br*(255-alpha))/255) | (((g*alpha+bgg*(255-alpha))/255)<<8) | (((b*alpha+bb*(255-alpha))/255)<<16));
      return(ColorToARGB(m,255));
     }
   void     Font(const int kind)
     {
      string f=face_sans;
      int sz=16,fl=FW_NORMAL;
      switch(kind)
        {
         case VTK_MONO:  f=face_mono; sz=14; break;
         case VTK_SMALL: sz=14; break;
         case VTK_BIG:   f=face_mono; sz=23; fl=FW_NORMAL; break;
         case VTK_SEC:   sz=12; fl=FW_SEMIBOLD; break;
         case VTK_BRAND: sz=15; fl=FW_SEMIBOLD; break;
         case VTK_MONOS: f=face_mono; sz=13; break;
         default:        sz=16; break;
        }
      int px_size=S(sz);
      if(f!=m_face || px_size!=m_size || fl!=m_flags)
        {
         cv.FontSet(f,px_size,fl);
         m_face=f; m_size=px_size; m_flags=fl;
        }
     }
   //--- text at logical x,y; align: 0 left, 1 right (x = right edge), 2 centre
   void     Txt(const double x,const double y,const string s,const color clr,const int kind=VTK_SANS,const int align=0,
                const int alpha=255)
     {
      if(s=="")
         return;
      Font(kind);
      uint fl=(align==1 ? TA_RIGHT : (align==2 ? TA_CENTER : TA_LEFT))|TA_TOP;
      cv.TextOut(S(x),S(y),s,A(clr,alpha),fl);
     }
   int      TextW(const string s,const int kind)
     {
      Font(kind);
      int w,h;
      cv.TextSize(s,w,h);
      return((int)MathRound(w/scale));
     }
   void     Fill(const double x1,const double y1,const double x2,const double y2,const color clr,const int alpha=255)
     {
      cv.FillRectangle(S(x1),S(y1),MathMax(S(x1),S(x2)-1),MathMax(S(y1),S(y2)-1),A(clr,alpha));
     }
   void     Box(const double x1,const double y1,const double x2,const double y2,const color clr,const int alpha=255)
     {
      cv.Rectangle(S(x1),S(y1),MathMax(S(x1),S(x2)-1),MathMax(S(y1),S(y2)-1),A(clr,alpha));
     }
   void     HLine(const double x1,const double x2,const double y,const color clr,const int alpha=255)
     {
      int yy=S(y);
      cv.FillRectangle(S(x1),yy,MathMax(S(x1),S(x2)-1),yy,A(clr,alpha));
     }
   void     VLine(const double x,const double y1,const double y2,const color clr,const int alpha=255)
     {
      int xx=S(x);
      cv.FillRectangle(xx,S(y1),xx,MathMax(S(y1),S(y2)-1),A(clr,alpha));
     }
   //--- hit zones
   void     ZoneReset() { nz=0; }
   void     Zone(const double x1,const double y1,const double x2,const double y2,const int id,const int arg=0)
     {
      if(nz>=VT_ZMAX)
         return;
      zones[nz].x1=S(x1); zones[nz].y1=S(y1); zones[nz].x2=S(x2); zones[nz].y2=S(y2);
      zones[nz].id=id; zones[nz].arg=arg;
      nz++;
     }
   bool     ZoneAt(const int x,const int y,int &id,int &arg) const     // x,y relative to the card
     {
      for(int i=nz-1; i>=0; i--)
         if(x>=zones[i].x1 && x<zones[i].x2 && y>=zones[i].y1 && y<zones[i].y2)
           { id=zones[i].id; arg=zones[i].arg; return(true); }
      return(false);
     }
   bool     Inside(const int x,const int y) const { return(ok && x>=px && x<px+pw && y>=py && y<py+ph); }

   //--- the frame: background, border, header; returns the y (logical) where the tabs start
   void     Frame(const double h_logical)
     {
      cv.Erase(0);
      Fill(0,0,VT_CARD_W,h_logical,pal.bg,pal.bg_a);
      Fill(0,0,VT_CARD_W,28,pal.head);
      HLine(0,VT_CARD_W,28,pal.edge);
      Box(0,0,VT_CARD_W,h_logical,pal.edge);
     }
   void     Update() { if(ok) cv.Update(true); }
  };

#endif
//+------------------------------------------------------------------+
