//+------------------------------------------------------------------+
//|                          VitalsDump.mq5                          |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test tool (read-only). Mode 0: runs VtCore/VtExposure on the     |
//| synthetic cases tests/check_core.py wrote to the common files    |
//| folder (vttest\deals_<k>.csv, meta_<k>.csv, jr_<k>.csv,          |
//| pos_<k>.csv) and writes every number the card shows to           |
//| out_<k>.txt, plus the pip check (out_pip.txt). Mode 1: the       |
//| journal test (see VtJournal.mqh) on the scripted equity paths.   |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// Required Notice: Copyright 2026 Allan Niñal (https://www.allanninal.dev/mql5)
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property link      "https://www.allanninal.dev/mql5"
#property version   "1.00"
#property script_show_inputs
#include <Vitals/VtCore.mqh>
#include <Vitals/VtExposure.mqh>
#include <Vitals/VtJournal.mqh>
#include <VitalsCheck/VtDump.mqh>

input int    InpMode  = 0;            // 0 core cases, 1 journal paths
input int    InpCases = 8;            // cases 0 .. n-1
input bool   InpCloseWhenDone = false;

bool ReadLines(const string name,string &lines[])
  {
   ArrayResize(lines,0);
   int f=FileOpen(name,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(f==INVALID_HANDLE)
      return(false);
   FileReadString(f);                              // header
   int n=0;
   while(!FileIsEnding(f))
     {
      string s=FileReadString(f);
      if(StringLen(s)==0)
         continue;
      ArrayResize(lines,n+1,1024);
      lines[n++]=s;
     }
   FileClose(f);
   return(true);
  }

void RunCase(const int k)
  {
   string L[],v[];
   // meta
   long   now=0,f_start=0,f_magic=-1;
   double bal=0;
   string f_symbol="",f_comment="";
   if(!ReadLines(StringFormat("vttest\\meta_%d.csv",k),L))
     { PrintFormat("VitalsDump: meta_%d.csv missing",k); return; }
   for(int i=0; i<ArraySize(L); i++)
     {
      if(StringSplit(L[i],',',v)<2)
         continue;
      if(v[0]=="now") now=StringToInteger(v[1]);
      else if(v[0]=="balance") bal=StringToDouble(v[1]);
      else if(v[0]=="f_symbol") f_symbol=v[1];
      else if(v[0]=="f_magic") f_magic=StringToInteger(v[1]);
      else if(v[0]=="f_comment") f_comment=v[1];
      else if(v[0]=="f_start") f_start=StringToInteger(v[1]);
     }
   CVtEngine e;
   e.Filter(f_symbol,f_magic,f_comment,f_start);
   // deals
   if(!ReadLines(StringFormat("vttest\\deals_%d.csv",k),L))
     { PrintFormat("VitalsDump: deals_%d.csv missing",k); return; }
   int nd=ArraySize(L);
   for(int i=0; i<nd; i++)
     {
      if(StringSplit(L[i],',',v)<12)
         continue;
      VtDeal d;
      d.time=StringToInteger(v[0]); d.pos=StringToInteger(v[1]); d.magic=StringToInteger(v[2]);
      d.type=TypeOf(v[3]); d.entry=EntryOf(v[4]);
      d.volume=StringToDouble(v[5]); d.profit=StringToDouble(v[6]);
      d.swap=StringToDouble(v[7]); d.commission=StringToDouble(v[8]); d.fee=StringToDouble(v[9]);
      d.symbol=v[10]; d.comment=v[11];
      e.Add(d);
     }
   // journal
   long   jd[];
   double jm[],jp[];
   int    jn=0;
   if(ReadLines(StringFormat("vttest\\jr_%d.csv",k),L))
     {
      jn=ArraySize(L);
      ArrayResize(jd,jn); ArrayResize(jm,jn); ArrayResize(jp,jn);
      for(int i=0; i<jn; i++)
        {
         StringSplit(L[i],',',v);
         jd[i]=StringToInteger(v[0]); jm[i]=StringToDouble(v[1]); jp[i]=StringToDouble(v[2]);
        }
     }
   g_out=FileOpen(StringFormat("vttest\\out_%d.txt",k),FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(g_out==INVALID_HANDLE)
      return;
   uint t0=GetTickCount();
   DumpEngine(e,now,bal,jd,jm,jp,jn);
   // open positions
   VtPos P[];
   if(ReadLines(StringFormat("vttest\\pos_%d.csv",k),L))
     {
      int n=ArraySize(L);
      ArrayResize(P,n);
      for(int i=0; i<n; i++)
        {
         StringSplit(L[i],',',v);
         P[i].symbol=v[0]; P[i].magic=StringToInteger(v[1]); P[i].comment=v[2]; P[i].dir=(int)StringToInteger(v[3]);
         P[i].volume=StringToDouble(v[4]); P[i].profit=StringToDouble(v[5]); P[i].pips=StringToDouble(v[6]);
         P[i].sl=StringToDouble(v[7]); P[i].risk=StringToDouble(v[8]); P[i].value=StringToDouble(v[9]);
         P[i].base=v[10]; P[i].ccy=v[11];
        }
      VtSummarize(e,P,n,bal);
     }
   else
      VtSummarize(e,P,0,bal);
   DumpOpen(e);
   FileClose(g_out);
   PrintFormat("VitalsDump: case %d: %d deals, %d trades, %d ms",k,nd,e.ntr,(int)(GetTickCount()-t0));
  }

void RunPips()
  {
   string L[],v[];
   if(!ReadLines("vttest\\pip_test.csv",L))
      return;
   g_out=FileOpen("vttest\\out_pip.txt",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   for(int i=0; i<ArraySize(L); i++)
     {
      StringSplit(L[i],',',v);
      WI(StringFormat("pip.%d",i),VtPipMult(v[0],(int)StringToInteger(v[1])));
     }
   FileClose(g_out);
  }


//--- mode 1: scripted equity paths through midnight and restarts (tests/check_journal.py writes jt_paths.csv)
//    kind: S sample, R clean restart (Flush(true), then a new object reads the file), C crash restart (no flush)
void FileLines(const string path,const string tag,const int h)
  {
   FileWriteString(h,"SNAP "+tag+"\n");
   int f=FileOpen(path,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(f==INVALID_HANDLE)
      return;
   while(!FileIsEnding(f))
     {
      string s=FileReadString(f);
      if(StringLen(s)>0)
         FileWriteString(h,s+"\n");
     }
   FileClose(f);
  }

void VtJournalSelfTest()
  {
   string L[],v[],jf="Vitals\\FDD_test.csv";
   FolderCreate("Vitals");
   FileDelete(jf);
   if(FileIsExist("vttest\\jt_seed.csv",FILE_COMMON))
      { if(!FileCopy("vttest\\jt_seed.csv",FILE_COMMON,jf,FILE_REWRITE)) PrintFormat("VitalsDump: seed copy failed, error %d",GetLastError()); }
   if(!ReadLines("vttest\\jt_paths.csv",L))
     { Print("VitalsDump: jt_paths.csv missing"); return; }
   int h=FileOpen("vttest\\journal_out.txt",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   CVtJournal *j=new CVtJournal;
   j.Init(jf,0);
   int snap=0;
   for(int i=0; i<ArraySize(L); i++)
     {
      if(StringSplit(L[i],',',v)<5)
         continue;
      if(v[0]=="S")
         j.Sample(StringToInteger(v[1]),StringToDouble(v[2]),StringToDouble(v[3]),(ulong)StringToInteger(v[4]));
      else
        {
         ulong ms=(ulong)StringToInteger(v[4]);
         if(v[0]=="R")
            j.Flush(true,ms);
         delete j;
         j=new CVtJournal;
         j.Init(jf,ms);
         FileLines(jf,IntegerToString(snap++),h);
        }
     }
   j.Flush(true,(ulong)4000000000);
   FileLines(jf,"final",h);
   FileWriteString(h,"MEM\n");
   for(int i=0; i<j.n; i++)
      FileWriteString(h,StringFormat("%I64d,%.2f,%.4f\n",j.d[i],j.m[i],j.p[i]));
   FileClose(h);
   PrintFormat("VitalsDump: journal test: %d steps, %d days, %d write errors",ArraySize(L),j.n,j.errors);
   delete j;
  }

void OnStart()
  {
   if(InpMode==0)
     {
      for(int k=0; k<InpCases && !IsStopped(); k++)
         RunCase(k);
      RunPips();
     }
   else
      VtJournalSelfTest();
   int h=FileOpen("vttest\\DONE.txt",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   FileWriteString(h,"DONE\n");
   FileClose(h);
   if(InpCloseWhenDone)
      TerminalClose(0);
  }
//+------------------------------------------------------------------+
