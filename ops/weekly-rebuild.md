# Weekly forex bias rebuild (Sundays 18:49 UK)

Score last week's calls, then build next week's currency bias from scratch for NewsBiasEA (DEMO account). "Next week" = the coming Monday to Friday.

## Part A - score last week
1. For each row in history/bias-log.csv with an empty end_price, find the pair's Friday close (or latest weekly close you can verify). Fill end_price, change_pips_in_bias_direction (positive = moved the way the bias said; 1 pip = 0.0001, or 0.01 for JPY pairs) and result (WIN > +10 pips, LOSS < -10, else FLAT). Can't verify -> result "unverified", numbers blank. Never invent prices.
2. Running totals over all scored rows: calls, win rate, average pips in bias direction.

## Part B - build next week
3. Research (fetch full pages when snippets are thin): each central bank's expected path (Fed, ECB, BoE, BoJ, SNB, RBA, RBNZ, BoC) and market pricing; data momentum; risk sentiment and geopolitics (safe havens USD/JPY/CHF gain in risk-off; AUD/NZD/CAD in risk-on; oil up helps CAD, hurts JPY and oil importers; China affects AUD/NZD); weekly trend and approximate price of candidate pairs; intervention risk; next week's high-impact calendar with exact UTC times (check DST offsets for US, UK, Europe, Australia, NZ).
4. Score USD EUR GBP JPY CHF AUD NZD CAD from -2 to +2 with a one-line reason each.
5. Choose at most 3 pairs, strong vs weak with a score gap >= 2, from exactly: EURUSD GBPUSD USDJPY USDCHF AUDUSD NZDUSD USDCAD EURGBP EURJPY GBPJPY AUDJPY EURAUD GBPAUD AUDNZD EURCHF GBPCHF CADJPY. BUY = buy the first currency. Conviction 2 for gap >= 3 with the weekly trend agreeing, else 1. Avoid all three on the same side of one currency if a good alternative exists. Obvious traps (e.g. intervention risk) -> NONE, conviction 0. If nothing qualifies, publish no BUY/SELL lines.
6. Overwrite bias.txt:
```
# Weekly currency bias for NewsBiasEA (demo account only)
# Week of <Monday YYYY-MM-DD> | Generated <YYYY-MM-DD HH:MM> UTC (weekly rebuild)
# Scorecard (-2 weakest .. +2 strongest):
#   <CCY> <score>  <one-line reason>     (all 8 currencies)
#
# BIAS;symbol;BUY/SELL/NONE;conviction 1-2;valid until (UTC)
BIAS;<SYMBOL>;<BUY|SELL|NONE>;<0-2>;<Friday YYYY.MM.DD> 20:00
#
# EVENT;time (UTC);currency or ALL;description  (no entries 30 min either side)
EVENT;<YYYY.MM.DD HH:MM>;<CCY>;<description>
```
   Semicolons only as separators; UTC times; high-impact events only (rate decisions, CPI, jobs, GDP, retail sales, major central bank chair speeches); a China release that matters to AUD and NZD gets one line for each.
7. Append one row per BUY/SELL bias to history/bias-log.csv: week_start, symbol, bias, conviction, start_price (verified), start_source (site and date), three empty fields.
8. Commit "Weekly bias for week of <Monday>" and push (common.md). Touch no other files.

## Briefing (phone-length)
Last week's calls with pips and result, running totals (note 40-50 calls are needed before they mean much); next week's scorecard; chosen biases and why, plus pairs deliberately avoided; key events in London time; sources; disclaimer; next run time.

Then schedule the next run (common.md).
