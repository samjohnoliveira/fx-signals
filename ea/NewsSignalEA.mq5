//+------------------------------------------------------------------+
//|  NewsSignalEA.mq5                                                |
//|  Fetches daily trade signals from a web address and places them  |
//|  with stop-loss, take-profit and fixed-percentage risk.          |
//|  Works on the MetaQuotes built-in VPS (no DLLs, WebRequest only).|
//|                                                                  |
//|  Signal file: plain text, one signal per line, fields split by ; |
//|    id;symbol;direction;entry;stop;target;expiry_utc              |
//|    20261012-1;EURUSD;BUY;1.08500;1.08100;1.09300;2026.10.12 20:00|
//|  Lines starting with # are ignored.                              |
//+------------------------------------------------------------------+
#property copyright "Generated for personal use"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input string InpSignalUrl          = "";      // Signal file web address (must be in MT5's allowed URL list)
input int    InpPollSeconds        = 300;     // How often to check for signals (seconds)
input double InpRiskPercent        = 1.0;     // Risk per trade, % of balance
input int    InpMaxOpenTrades      = 3;       // Max open positions + pending orders from this EA
input double InpDailyLossCapPct    = 3.0;     // Stop opening trades after losing this % in a day
input double InpMinRiskReward      = 1.0;     // Reject signals with reward/risk below this
input int    InpMarketTolerancePts = 30;      // Enter at market if price is within this many points of entry
input string InpSymbolSuffix       = "";      // Broker symbol suffix, e.g. ".a" or "m"
input long   InpMagic              = 20261011;// Magic number identifying this EA's trades

CTrade trade;
string handledIds[];   // ids already placed or rejected in this session

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpSignalUrl == "")
     {
      Print("NewsSignalEA: set InpSignalUrl to the signal file address.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   EventSetTimer(MathMax(InpPollSeconds, 30));
   Print("NewsSignalEA started. Polling ", InpSignalUrl);
   CheckSignals();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTimer()                  { CheckSignals(); }
void OnTick()                   { }

//+------------------------------------------------------------------+
//| Download and process the signal file                             |
//+------------------------------------------------------------------+
void CheckSignals()
  {
   char   post[], result[];
   string responseHeaders;
   string url = InpSignalUrl + (StringFind(InpSignalUrl, "?") < 0 ? "?" : "&") + "t=" + IntegerToString((long)TimeGMT());

   ResetLastError();
   int code = WebRequest("GET", url, "", 10000, post, result, responseHeaders);
   if(code == -1)
     {
      Print("NewsSignalEA: WebRequest failed, error ", GetLastError(),
            ". Add the site to Tools > Options > Expert Advisors > Allow WebRequest.");
      return;
     }
   if(code != 200)
     {
      Print("NewsSignalEA: signal file returned HTTP ", code);
      return;
     }

   string body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
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
      ProcessSignal(line);
     }
  }

//+------------------------------------------------------------------+
void ProcessSignal(string line)
  {
   string f[];
   if(StringSplit(line, ';', f) < 7)
     {
      Print("NewsSignalEA: skipping malformed line: ", line);
      return;
     }
   for(int i = 0; i < 7; i++) { StringTrimLeft(f[i]); StringTrimRight(f[i]); }

   string   id     = f[0];
   string   symbol = f[1] + InpSymbolSuffix;
   string   dir    = f[2];
   StringToUpper(dir);
   double   entry  = StringToDouble(f[3]);
   double   sl     = StringToDouble(f[4]);
   double   tp     = StringToDouble(f[5]);
   datetime expiryUtc = StringToTime(f[6]);

   // Expired: remove any unfilled order and stop.
   if(expiryUtc <= TimeGMT())
     {
      CancelPending(id);
      return;
     }
   if(IsHandled(id) || AlreadyPlaced(id))
      return;

   bool isBuy = (dir == "BUY");
   if(!isBuy && dir != "SELL")                 { Reject(id, "direction must be BUY or SELL"); return; }
   if(StringLen(id) > 25)                      { Reject(id, "id longer than 25 characters"); return; }
   if(!SymbolSelect(symbol, true))             { Reject(id, "symbol not found: " + symbol); return; }
   if(entry <= 0 || sl <= 0 || tp <= 0)        { Reject(id, "bad price levels"); return; }
   if(isBuy  && !(sl < entry && entry < tp))   { Reject(id, "BUY needs stop < entry < target"); return; }
   if(!isBuy && !(tp < entry && entry < sl))   { Reject(id, "SELL needs target < entry < stop"); return; }

   double rr = MathAbs(tp - entry) / MathAbs(entry - sl);
   if(rr < InpMinRiskReward)                   { Reject(id, "risk/reward too low"); return; }

   // Account-level limits: retry later rather than reject, as these can clear.
   if(CountOpen() >= InpMaxOpenTrades)         { Print("NewsSignalEA: ", id, " waiting, max open trades reached"); return; }
   if(DailyLossHit())                          { Print("NewsSignalEA: ", id, " blocked, daily loss cap reached"); return; }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.ask <= 0) { Print("NewsSignalEA: no price yet for ", symbol); return; }

   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double price  = isBuy ? tick.ask : tick.bid;
   entry = NormalizeDouble(entry, digits);
   sl    = NormalizeDouble(sl, digits);
   tp    = NormalizeDouble(tp, digits);

   bool atMarket = (MathAbs(entry - price) <= InpMarketTolerancePts * point);
   double refPrice = atMarket ? price : entry;
   if(atMarket)
     {
      if(isBuy  && !(sl < price && price < tp)) { Reject(id, "price already beyond stop or target"); return; }
      if(!isBuy && !(tp < price && price < sl)) { Reject(id, "price already beyond stop or target"); return; }
     }

   double lots = CalcLots(symbol, isBuy, refPrice, sl);
   if(lots <= 0) { Reject(id, "stop too wide for the risk setting at minimum lot size"); return; }

   trade.SetTypeFillingBySymbol(symbol);
   bool ok;
   if(atMarket)
     {
      ok = isBuy ? trade.Buy(lots, symbol, 0, sl, tp, id)
                 : trade.Sell(lots, symbol, 0, sl, tp, id);
     }
   else
     {
      // Expiry: use the broker's own expiry if supported, otherwise the EA cancels it.
      long            expMode  = SymbolInfoInteger(symbol, SYMBOL_EXPIRATION_MODE);
      ENUM_ORDER_TYPE_TIME tt  = ORDER_TIME_GTC;
      datetime        expSrv   = 0;
      if((expMode & SYMBOL_EXPIRATION_SPECIFIED) != 0)
        {
         tt     = ORDER_TIME_SPECIFIED;
         expSrv = expiryUtc + (TimeTradeServer() - TimeGMT());
        }
      if(isBuy)
         ok = (entry < price) ? trade.BuyLimit(lots, entry, symbol, sl, tp, tt, expSrv, id)
                              : trade.BuyStop(lots, entry, symbol, sl, tp, tt, expSrv, id);
      else
         ok = (entry > price) ? trade.SellLimit(lots, entry, symbol, sl, tp, tt, expSrv, id)
                              : trade.SellStop(lots, entry, symbol, sl, tp, tt, expSrv, id);
     }

   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
     {
      Print("NewsSignalEA: placed ", id, " ", dir, " ", symbol, " ", DoubleToString(lots, 2), " lots");
      MarkHandled(id);
     }
   else
      Reject(id, "order refused: " + trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Lot size so that hitting the stop loses InpRiskPercent of balance|
//+------------------------------------------------------------------+
double CalcLots(string symbol, bool isBuy, double entry, double sl)
  {
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double profit = 0;
   if(!OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, symbol, 1.0, entry, sl, profit))
      return(0);
   double lossPerLot = MathAbs(profit);
   if(lossPerLot <= 0)
      return(0);

   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minV = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lots = MathFloor(riskMoney / lossPerLot / step) * step;
   if(lots < minV)
      return(0);               // never exceed the risk setting just to reach the minimum lot
   return(MathMin(lots, maxV));
  }

//+------------------------------------------------------------------+
int CountOpen()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         count++;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t > 0 && OrderGetInteger(ORDER_MAGIC) == InpMagic)
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| Today's closed + floating result for this EA versus the cap      |
//+------------------------------------------------------------------+
bool DailyLossHit()
  {
   MqlDateTime d;
   TimeToStruct(TimeTradeServer(), d);
   d.hour = 0; d.min = 0; d.sec = 0;
   datetime dayStart = StructToTime(d);

   double pnl = 0;
   if(HistorySelect(dayStart, TimeTradeServer() + 60))
     {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0 || HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic)
            continue;
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
//| Has this id already been sent (live order or last 14 days)?      |
//+------------------------------------------------------------------+
bool AlreadyPlaced(string id)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t > 0 && OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_COMMENT) == id)
         return(true);
     }
   if(HistorySelect(TimeTradeServer() - 14 * 86400, TimeTradeServer() + 60))
     {
      for(int i = HistoryOrdersTotal() - 1; i >= 0; i--)
        {
         ulong t = HistoryOrderGetTicket(i);
         if(t > 0 && HistoryOrderGetInteger(t, ORDER_MAGIC) == InpMagic
            && HistoryOrderGetString(t, ORDER_COMMENT) == id)
            return(true);
        }
     }
   return(false);
  }

void CancelPending(string id)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t > 0 && OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_COMMENT) == id)
        {
         if(trade.OrderDelete(t))
            Print("NewsSignalEA: cancelled expired order ", id);
        }
     }
  }

bool IsHandled(string id)
  {
   for(int i = ArraySize(handledIds) - 1; i >= 0; i--)
      if(handledIds[i] == id)
         return(true);
   return(false);
  }

void MarkHandled(string id)
  {
   int n = ArraySize(handledIds);
   ArrayResize(handledIds, n + 1);
   handledIds[n] = id;
  }

void Reject(string id, string why)
  {
   Print("NewsSignalEA: rejected ", id, " - ", why);
   MarkHandled(id);
  }
//+------------------------------------------------------------------+
