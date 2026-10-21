//+------------------------------------------------------------------+
//|                                                    VtJournal.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| The floating-drawdown journal. MT5 keeps no past floating        |
//| equity, so the lowest (equity - balance) of every server day is  |
//| recorded here as it happens: MQL5\Files\Vitals\FDD_<login>.csv,  |
//| one line "day,money,percent" per day (day = server seconds /     |
//| 86400; percent = of the balance at that instant).                |
//|   - Sample() is called on every timer tick and every OnCalculate;|
//|     the first sample of a day marks it as covered (0).           |
//|   - The file is rewritten when the day's low deepened and the    |
//|     last write is 10 s old, and by Flush(true) at deinit. A      |
//|     crash loses at most the last 10 s of depth, never a day.     |
//|   - Every write first merges with what the file holds (another   |
//|     chart of the same account), keeping the deeper low per day.  |
//| Money is kept to 2 decimals and percent to 4, so memory and file |
//| always agree.                                                    |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef VTJOURNAL_MQH
#define VTJOURNAL_MQH

#define VT_JMAX      4000            // days kept
#define VT_JFLUSH_MS 10000

class CVtJournal
  {
public:
   long     d[];                    // sorted ascending, unique
   double   m[],p[];                // lowest floating (<= 0) and its percent
   int      n;
   string   file;
   bool     dirty;
   ulong    last_ms;
   int      errors;
            CVtJournal(): n(0),dirty(false),last_ms(0),errors(0) {}
   void     Init(const string path,const ulong now_ms)
     {
      file=path; n=0; dirty=false; errors=0; last_ms=now_ms;
      ArrayResize(d,0,512); ArrayResize(m,0,512); ArrayResize(p,0,512);
      long fd[]; double fm[],fp[]; int fn=ReadFile(fd,fm,fp);
      for(int i=0; i<fn; i++)
         Put(fd[i],fm[i],fp[i]);
      dirty=false;
     }
   //--- insert or deepen a day; true when something changed
   bool     Put(const long day,const double money,const double pct)
     {
      int lo=0,hi=n;
      while(lo<hi)
        {
         int mid=(lo+hi)/2;
         if(d[mid]<day)
            lo=mid+1;
         else
            hi=mid;
        }
      if(lo<n && d[lo]==day)
        {
         if(money<m[lo])
           { m[lo]=money; p[lo]=pct; return(true); }
         return(false);
        }
      ArrayResize(d,n+1,512); ArrayResize(m,n+1,512); ArrayResize(p,n+1,512);
      for(int i=n; i>lo; i--)
        { d[i]=d[i-1]; m[i]=m[i-1]; p[i]=p[i-1]; }
      d[lo]=day; m[lo]=money; p[lo]=pct; n++;
      return(true);
     }
   void     Sample(const long server_now,const double equity,const double balance,const ulong now_ms)
     {
      long day=server_now/86400;
      double money=NormalizeDouble(MathMin(equity-balance,0.0),2);
      double pct=NormalizeDouble(balance>0 ? money/balance*100.0 : 0.0,4);
      if(Put(day,money,pct))
         dirty=true;
      if(dirty && now_ms-last_ms>=VT_JFLUSH_MS)
         Flush(false,now_ms);
     }
   int      ReadFile(long &fd[],double &fm[],double &fp[])
     {
      ArrayResize(fd,0); ArrayResize(fm,0); ArrayResize(fp,0);
      int f=FileOpen(file,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(f==INVALID_HANDLE)
         return(0);
      int k=0;
      while(!FileIsEnding(f))
        {
         string s=FileReadString(f);
         string v[];
         if(StringSplit(s,',',v)<3)
            continue;
         long day=StringToInteger(v[0]);
         if(day<=0)
            continue;
         ArrayResize(fd,k+1,512); ArrayResize(fm,k+1,512); ArrayResize(fp,k+1,512);
         fd[k]=day; fm[k]=MathMin(StringToDouble(v[1]),0.0); fp[k]=MathMin(StringToDouble(v[2]),0.0);
         k++;
        }
      FileClose(f);
      return(k);
     }
   //--- merge with the file, then rewrite it; keeps the data dirty when the file could not be written
   bool     Flush(const bool force,const ulong now_ms)
     {
      if(!dirty)
         return(true);
      if(!force && now_ms-last_ms<VT_JFLUSH_MS)
         return(true);
      last_ms=now_ms;
      long fd[]; double fm[],fp[]; int fn=ReadFile(fd,fm,fp);
      for(int i=0; i<fn; i++)
         Put(fd[i],fm[i],fp[i]);
      int skip=MathMax(0,n-VT_JMAX);
      int f=FileOpen(file,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(f==INVALID_HANDLE)
        {
         errors++;
         return(false);
        }
      for(int i=skip; i<n; i++)
         FileWriteString(f,StringFormat("%I64d,%.2f,%.4f\n",d[i],m[i],p[i]));
      FileClose(f);
      dirty=false;
      return(true);
     }
  };

#endif
//+------------------------------------------------------------------+
