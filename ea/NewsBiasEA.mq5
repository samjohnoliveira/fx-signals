//+------------------------------------------------------------------+
//|  NewsBiasEA.mq5                                                  |
//|  Trades only in the direction of a macro/news bias published in  |
//|  a web file, timing entries from live prices:                    |
//|   - trend filter: higher-timeframe close vs its EMA agrees       |
//|   - entry: pullback bar on the entry timeframe that tags the     |
//|     EMA and closes back in the bias direction                    |
//|   - stop beyond the recent swing (bounded by ATR), target at a   |
//|     fixed reward/risk, stop to breakeven at 1R                   |
//|   - no entries around high-impact news for the pair's currencies |
//|  Works on the MetaQuotes built-in VPS (WebRequest only, no DLLs).|
//|                                                                  |
//|  Bias file (plain text, ; separated, # = comment):               |
//|    BIAS;USDJPY;BUY;2;2026.10.16 20:00                            |
//|        symbol; BUY/SELL/NONE; conviction 1-2; valid until (UTC)  |
//|    EVENT;2026.10.13 12:30;USD;US CPI                             |
//|        time (UTC); currency (or ALL); description                |
//+------------------------------------------------------------------+
#property copyright "Generated for personal use"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input string          InpBiasUrl          = "https://raw.githubusercontent.com/samjohnoliveira/fx-signals/main/bias.txt"; // Bias file address
input int             InpPollSeconds      = 300;        // How often to re-read the bias file (seconds)
input ENUM_TIMEFRAMES InpEntryTF          = PERIOD_H1;  // Entry timeframe
input ENUM_TIMEFRAMES InpTrendTF          = PERIOD_H4;  // Trend-filter timeframe
input int             InpEntryEMA         = 20;         // Entry EMA period (pullback line)
input int             InpTrendEMA         = 50;         // Trend EMA period
input int             InpATRPeriod        = 14;         // ATR period (entry timeframe)
input int             InpSwingBars        = 10;         // Bars back to find the swing for the stop
input double          InpStopBufferATR    = 0.2;        // Extra room beyond the swing, x ATR
input double          InpMinStopATR       = 1.0;        // Minimum stop distance, x ATR
input double          InpMaxStopATR       = 3.0;        // Skip trade if stop would be wider than this, x ATR
input double          InpRewardRisk       = 2.0;        // Target as a multiple of risk
input double          InpBreakevenAtR     = 1.0;        // Move stop to entry after this many R in profit (0 = off)
input double          InpRiskPercent      = 1.0;        // Risk per trade, % of balance
input int             InpMaxOpenTrades    = 3;          // Max open positions from this EA
input double          InpDailyLossCapPct  = 3.0;        // No new trades after losing this % in a day
input int             InpMaxSpreadPts     = 25;         // Skip entry if spread is wider (points)
input int             InpNewsBlackoutMins = 30;         // No entries this many minutes either side of listed events
input int             InpStartHourUTC     = 7;          // First hour (UTC) new trades are allowed
input int             InpEndHourUTC       = 19;         // No new trades from this hour (UTC)
input bool            InpCloseOnFlip      = true;       // Close a position if its bias flips to the opposite side
input bool            InpFlatFriday       = true;       // Close all positions late Friday (avoid weekend gaps)
input int             InpFridayCloseHourUTC = 20;       // Friday close hour (UTC)
input int             InpFridayLastEntryUTC = 16;       // No new trades on Friday from this hour (UTC)
input string          InpSymbolSuffix     = ".r";       // Broker symbol suffix
input string          InpTestBias         = "";         // Strategy Tester only, e.g. USDJPY:BUY,EURUSD:SELL
input long            InpMagic            = 20261012;   // Magic number identifying this EA's trades

struct BiasRec  { string sym; int dir; int conv; datetime until; };
struct EventRec { datetime t; string ccy; string name; };

CTrade   trade;
BiasRec  biases[];
EventRec events[];
string   lastBody    = "";
datetime lastPoll    = 0;
bool     isTester    = false;

// per-symbol caches
string   cSym[];
int      cEmaE[], cEmaT[], cAtr[];
datetime cLastBar[];

//+------------------------------------------------------------------+
int OnInit()
  {
   isTester = (bool)MQLInfoInteger(MQL_TESTER);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);

   if(isTester)
     {
      if(!LoadTestBias())
        {
         Print("NewsBiasEA: in the Strategy Tester set InpTestBias, e.g. USDJPY:BUY");
         return(INIT_PARAMETERS_INCORRECT);
        }
     }
   else if(InpBiasUrl == "")
     {
      Print("NewsBiasEA: set InpBiasUrl.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   EventSetTimer(30);
   Print("NewsBiasEA started", isTester ? " (tester mode)" : "");
   OnTimer();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = ArraySize(cSym) - 1; i >= 0; i--)
     {
      if(cEmaE[i] != INVALID_HANDLE) IndicatorRelease(cEmaE[i]);
      if(cEmaT[i] != INVALID_HANDLE) IndicatorRelease(cEmaT[i]);
      if(cAtr[i]  != INVALID_HANDLE) IndicatorRelease(cAtr[i]);
     }
  }

void OnTick()
  {
   if(isTester) Work();          // tester: drive from ticks as well as the timer
  }

void OnTimer()
  {
   if(!isTester && TimeGMT() - lastPoll >= InpPollSeconds)
     {
      lastPoll = TimeGMT();
      FetchBias();
     }
   Work();
  }

//+------------------------------------------------------------------+
void Work()
  {
   ManagePositions();
   for(int i = 0; i < ArraySize(biases); i++)
     {
      if(biases[i].dir == 0 || biases[i].until <= TimeGMT())
         continue;
      TryEntry(biases[i].sym, biases[i].dir);
     }
  }

//+------------------------------------------------------------------+
//| Bias file                                                        |
//+------------------------------------------------------------------+
void FetchBias()
  {
   char   post[], result[];
   string hdr;
   string url = InpBiasUrl + (StringFind(InpBiasUrl, "?") < 0 ? "?" : "&") + "t=" + IntegerToString((long)TimeGMT());
   ResetLastError();
   int code = WebRequest("GET", url, "", 10000, post, result, hdr);
   if(code == -1)
     {
      Print("NewsBiasEA: WebRequest failed, error ", GetLastError(),
            ". Add https://raw.githubusercontent.com under Tools > Options > Expert Advisors.");
      return;
     }
   if(code != 200)
     {
      Print("NewsBiasEA: bias file returned HTTP ", code, " - keeping previous biases");
      return;
     }
   string body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   if(body == lastBody)
      return;
   lastBody = body;
   ParseBias(body);
  }

void ParseBias(string body)
  {
   BiasRec  nb[];
   EventRec ne[];
   StringReplace(body, "\r", "");
   string lines[];
   int n = StringSplit(body, '\n', lines);
   for(int i = 0; i < n; i++)
     {
      string line = lines[i];
      StringTrimLeft(line);
      StringTrimRight(line);
      if(line == "" || StringGetCharacter(line, 0) == '#')
         continue;
      string f[];
      int k = StringSplit(line, ';', f);
      for(int j = 0; j < k; j++) { StringTrimLeft(f[j]); StringTrimRight(f[j]); }
      string kind = (k > 0 ? f[0] : "");
      StringToUpper(kind);

      if(kind == "BIAS" && k >= 5)
        {
         string d = f[2];
         StringToUpper(d);
         int dir = (d == "BUY" ? 1 : (d == "SELL" ? -1 : 0));
         if(d != "BUY" && d != "SELL" && d != "NONE")
           { Print("NewsBiasEA: bad direction in: ", line); continue; }
         BiasRec b;
         b.sym   = f[1];
         StringToUpper(b.sym);
         b.dir   = dir;
         b.conv  = (int)StringToInteger(f[3]);
         b.until = StringToTime(f[4]);
         int m = ArraySize(nb);
         ArrayResize(nb, m + 1);
         nb[m] = b;
        }
      else if(kind == "EVENT" && k >= 3)
        {
         EventRec e;
         e.t    = StringToTime(f[1]);
         e.ccy  = f[2];
         StringToUpper(e.ccy);
         e.name = (k >= 4 ? f[3] : "");
         int m = ArraySize(ne);
         ArrayResize(ne, m + 1);
         ne[m] = e;
        }
      else
         Print("NewsBiasEA: skipping unrecognised line: ", line);
     }

   ArrayResize(biases, ArraySize(nb));
   for(int i = 0; i < ArraySize(nb); i++) biases[i] = nb[i];
   ArrayResize(events, ArraySize(ne));
   for(int i = 0; i < ArraySize(ne); i++) events[i] = ne[i];

   string summary = "";
   for(int i = 0; i < ArraySize(biases); i++)
      summary += biases[i].sym + ":" + (biases[i].dir > 0 ? "BUY" : biases[i].dir < 0 ? "SELL" : "NONE") + " ";
   Print("NewsBiasEA: loaded ", ArraySize(biases), " biases, ", ArraySize(events), " events. ", summary);
  }

bool LoadTestBias()
  {
   string parts[];
   int n = StringSplit(InpTestBias, ',', parts);
   ArrayResize(biases, 0);
   for(int i = 0; i < n; i++)
     {
      string kv[];
      StringTrimLeft(parts[i]); StringTrimRight(parts[i]);
      if(StringSplit(parts[i], ':', kv) != 2) continue;
      StringToUpper(kv[0]); StringToUpper(kv[1]);
      int dir = (kv[1] == "BUY" ? 1 : (kv[1] == "SELL" ? -1 : 0));
      if(dir == 0) continue;
      BiasRec b;
      b.sym = kv[0]; b.dir = dir; b.conv = 2; b.until = D'2099.01.01';
      int m = ArraySize(biases);
      ArrayResize(biases, m + 1);
      biases[m] = b;
     }
   return(ArraySize(biases) > 0);
  }

int BiasFor(string baseSym)
  {
   for(int i = 0; i < ArraySize(biases); i++)
      if(biases[i].sym == baseSym && biases[i].until > TimeGMT())
         return(biases[i].dir);
   return(0);
  }

//+------------------------------------------------------------------+
//| Entry logic                                                      |
//+------------------------------------------------------------------+
void TryEntry(string baseSym, int dir)
  {
   string s = baseSym + InpSymbolSuffix;
   if(!SymbolSelect(s, true))
      return;
   int c = Cache(s);
   if(c < 0)
      return;

   // Evaluate once per closed bar on the entry timeframe.
   datetime barTime = iTime(s, InpEntryTF, 1);
   if(barTime == 0 || cLastBar[c] == barTime)
      return;

   // Market data (if not ready yet, try again on the next timer)
   double emaE[1], emaT[1], atr[1];
   if(CopyBuffer(cEmaE[c], 0, 1, 1, emaE) != 1) return;
   if(CopyBuffer(cEmaT[c], 0, 1, 1, emaT) != 1) return;
   if(CopyBuffer(cAtr[c],  0, 1, 1, atr)  != 1) return;
   double o1 = iOpen(s, InpEntryTF, 1), h1 = iHigh(s, InpEntryTF, 1);
   double l1 = iLow(s, InpEntryTF, 1),  c1 = iClose(s, InpEntryTF, 1);
   double trendClose = iClose(s, InpTrendTF, 1);
   if(o1 <= 0 || c1 <= 0 || trendClose <= 0 || atr[0] <= 0) return;

   cLastBar[c] = barTime;   // this bar has now been evaluated

   // --- Filters that don't depend on the setup
   if(!TradingWindowOpen())                          return;
   if(HasPosition(s))                                return;
   if(TradedToday(s))                                return;
   if(CountOpen() >= InpMaxOpenTrades)               return;
   if(DailyLossHit())                                { Print("NewsBiasEA: daily loss cap reached, no new trades"); return; }
   if(!isTester && InBlackout(baseSym))              { Print("NewsBiasEA: ", baseSym, " skipped, high-impact news window"); return; }
   if(SymbolInfoInteger(s, SYMBOL_SPREAD) > InpMaxSpreadPts) { Print("NewsBiasEA: ", baseSym, " skipped, spread too wide"); return; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      Print("NewsBiasEA: Algo Trading is switched off");
      cLastBar[c] = 0;      // re-check this bar once trading is enabled
      return;
     }

   // --- Trend filter: higher timeframe agrees with the bias
   if(dir > 0 && !(trendClose > emaT[0])) return;
   if(dir < 0 && !(trendClose < emaT[0])) return;

   // --- Pullback trigger: last bar tagged the EMA and closed back in the bias direction
   bool trigger = (dir > 0) ? (l1 <= emaE[0] && c1 > emaE[0] && c1 > o1)
                            : (h1 >= emaE[0] && c1 < emaE[0] && c1 < o1);
   if(!trigger) return;

   // --- Stop, target, size
   MqlTick tick;
   if(!SymbolInfoTick(s, tick) || tick.ask <= 0) { cLastBar[c] = 0; return; }
   int    digits = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(s, SYMBOL_POINT);
   double price  = (dir > 0) ? tick.ask : tick.bid;

   double sl;
   if(dir > 0)
     {
      int idx = iLowest(s, InpEntryTF, MODE_LOW, InpSwingBars, 1);
      if(idx < 0) return;
      sl = iLow(s, InpEntryTF, idx) - InpStopBufferATR * atr[0];
      if(price - sl < InpMinStopATR * atr[0]) sl = price - InpMinStopATR * atr[0];
     }
   else
     {
      int idx = iHighest(s, InpEntryTF, MODE_HIGH, InpSwingBars, 1);
      if(idx < 0) return;
      sl = iHigh(s, InpEntryTF, idx) + InpStopBufferATR * atr[0];
      if(sl - price < InpMinStopATR * atr[0]) sl = price + InpMinStopATR * atr[0];
     }
   double risk = MathAbs(price - sl);
   if(risk > InpMaxStopATR * atr[0])
     {
      Print("NewsBiasEA: ", baseSym, " setup skipped, stop wider than ", DoubleToString(InpMaxStopATR, 1), " ATR");
      return;
     }
   double tp = (dir > 0) ? price + InpRewardRisk * risk : price - InpRewardRisk * risk;
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double minDist = (double)SymbolInfoInteger(s, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(risk < minDist) { Print("NewsBiasEA: ", baseSym, " stop inside broker minimum distance"); return; }

   double lots = CalcLots(s, dir > 0, price, sl);
   if(lots <= 0) { Print("NewsBiasEA: ", baseSym, " stop too wide for the risk setting at minimum lot"); return; }

   string comment = "Bias " + baseSym;
   trade.SetTypeFillingBySymbol(s);
   bool ok = (dir > 0) ? trade.Buy(lots, s, 0, sl, tp, comment)
                       : trade.Sell(lots, s, 0, sl, tp, comment);
   uint rc = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED))
      Print("NewsBiasEA: opened ", (dir > 0 ? "BUY " : "SELL "), s, " ", DoubleToString(lots, 2),
            " lots, sl ", DoubleToString(sl, digits), " tp ", DoubleToString(tp, digits));
   else
     {
      Print("NewsBiasEA: ", s, " order refused - ", trade.ResultRetcodeDescription());
      if(IsTemporary(rc))
         cLastBar[c] = 0;   // retry on the next timer while this bar is still current
     }
  }

bool IsTemporary(uint rc)
  {
   return(rc == TRADE_RETCODE_CLIENT_DISABLES_AT || rc == TRADE_RETCODE_SERVER_DISABLES_AT ||
          rc == TRADE_RETCODE_MARKET_CLOSED      || rc == TRADE_RETCODE_CONNECTION ||
          rc == TRADE_RETCODE_TIMEOUT            || rc == TRADE_RETCODE_REQUOTE ||
          rc == TRADE_RETCODE_PRICE_OFF          || rc == TRADE_RETCODE_PRICE_CHANGED ||
          rc == TRADE_RETCODE_TOO_MANY_REQUESTS  || rc == TRADE_RETCODE_TRADE_DISABLED);
  }

bool TradingWindowOpen()
  {
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   if(t.day_of_week == 0 || t.day_of_week == 6) return(false);
   if(t.hour < InpStartHourUTC || t.hour >= InpEndHourUTC) return(false);
   if(t.day_of_week == 5 && t.hour >= InpFridayLastEntryUTC) return(false);
   return(true);
  }

bool InBlackout(string baseSym)
  {
   datetime now = TimeGMT();
   for(int i = 0; i < ArraySize(events); i++)
     {
      long gap = (long)events[i].t - (long)now;
      if(gap < 0) gap = -gap;
      if(gap > (long)InpNewsBlackoutMins * 60)
         continue;
      if(events[i].ccy == "ALL" || StringFind(baseSym, events[i].ccy) >= 0)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Open position management                                         |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   bool fridayClose = InpFlatFriday && t.day_of_week == 5 && t.hour >= InpFridayCloseHourUTC;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      string s      = PositionGetString(POSITION_SYMBOL);
      string base   = StringSubstr(s, 0, 6);
      long   type   = PositionGetInteger(POSITION_TYPE);
      int    posDir = (type == POSITION_TYPE_BUY) ? 1 : -1;
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);

      if(fridayClose)
        {
         if(trade.PositionClose(ticket)) Print("NewsBiasEA: closed ", s, " ahead of the weekend");
         continue;
        }
      if(!isTester && InpCloseOnFlip && BiasFor(base) == -posDir)
        {
         if(trade.PositionClose(ticket)) Print("NewsBiasEA: closed ", s, ", bias flipped");
         continue;
        }

      // Breakeven: initial risk recovered from the target (target = RR x risk).
      if(InpBreakevenAtR > 0 && tp > 0 && InpRewardRisk > 0)
        {
         double risk = MathAbs(tp - open) / InpRewardRisk;
         MqlTick tick;
         if(!SymbolInfoTick(s, tick)) continue;
         double cur = (posDir > 0) ? tick.bid : tick.ask;
         bool   inProfitEnough = (posDir > 0) ? (cur - open >= InpBreakevenAtR * risk)
                                              : (open - cur >= InpBreakevenAtR * risk);
         bool   notYetMoved = (posDir > 0) ? (sl < open) : (sl > open || sl == 0);
         if(inProfitEnough && notYetMoved)
           {
            int digits = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
            if(trade.PositionModify(ticket, NormalizeDouble(open, digits), tp))
               Print("NewsBiasEA: ", s, " stop moved to breakeven");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int Cache(string s)
  {
   for(int i = 0; i < ArraySize(cSym); i++)
      if(cSym[i] == s)
         return(i);
   int n = ArraySize(cSym);
   ArrayResize(cSym, n + 1); ArrayResize(cEmaE, n + 1); ArrayResize(cEmaT, n + 1);
   ArrayResize(cAtr, n + 1); ArrayResize(cLastBar, n + 1);
   cSym[n]     = s;
   cEmaE[n]    = iMA(s, InpEntryTF, InpEntryEMA, 0, MODE_EMA, PRICE_CLOSE);
   cEmaT[n]    = iMA(s, InpTrendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   cAtr[n]     = iATR(s, InpEntryTF, InpATRPeriod);
   cLastBar[n] = 0;
   if(cEmaE[n] == INVALID_HANDLE || cEmaT[n] == INVALID_HANDLE || cAtr[n] == INVALID_HANDLE)
     {
      Print("NewsBiasEA: could not create indicators for ", s);
      return(-1);
     }
   return(n);
  }

double CalcLots(string symbol, bool isBuy, double entry, double sl)
  {
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double profit = 0;
   if(!OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, symbol, 1.0, entry, sl, profit))
      return(0);
   double lossPerLot = MathAbs(profit);
   if(lossPerLot <= 0) return(0);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minV = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lots = MathFloor(riskMoney / lossPerLot / step) * step;
   if(lots < minV) return(0);
   return(MathMin(lots, maxV));
  }

bool HasPosition(string s)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == s)
         return(true);
     }
   return(false);
  }

int CountOpen()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic) n++;
     }
   return(n);
  }

datetime ServerDayStart()
  {
   MqlDateTime d;
   TimeToStruct(TimeTradeServer(), d);
   d.hour = 0; d.min = 0; d.sec = 0;
   return(StructToTime(d));
  }

bool TradedToday(string s)
  {
   if(!HistorySelect(ServerDayStart(), TimeTradeServer() + 60)) return(false);
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t > 0 && HistoryDealGetInteger(t, DEAL_MAGIC) == InpMagic &&
         HistoryDealGetString(t, DEAL_SYMBOL) == s &&
         HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN)
         return(true);
     }
   return(false);
  }

bool DailyLossHit()
  {
   double pnl = 0;
   if(HistorySelect(ServerDayStart(), TimeTradeServer() + 60))
     {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0 || HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
         pnl += HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP)
                + HistoryDealGetDouble(t, DEAL_COMMISSION);
        }
     }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return(pnl <= -AccountInfoDouble(ACCOUNT_BALANCE) * InpDailyLossCapPct / 100.0);
  }
//+------------------------------------------------------------------+
