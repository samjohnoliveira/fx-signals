# Daily forex bias review (weekdays 06:50 UK)

Review this week's currency bias for NewsBiasEA (an MT5 EA trading a DEMO account) and send Sam a short morning briefing. The weekly bias is built on Sunday; keep it unless something meaningful has changed. The EA times its own entries from live prices, so never give entry prices.

1. Research with web search (fetch full pages when snippets are thin) the last 24 hours: central bank decisions and speeches, data surprises versus forecast, geopolitical developments, oil and risk sentiment, intervention warnings. Check today's high-impact calendar with exact times converted to UTC (check daylight-saving offsets).
2. Review each BIAS line:
   - KEEP is the default. Normal day-to-day noise is not a reason to change.
   - DOWNGRADE to NONE (conviction 0) on any meaningful doubt: a surprise that undercuts the reasoning, a sharp move against the bias on fresh news, new intervention or event risk.
   - Lower conviction 2 -> 1 if the case has weakened but still stands.
   - FLIP only after a major shift (unexpected central bank decision or clear guidance change, big data shock that reprices rates, serious geopolitical event). Name the event.
   - ADD a new bias only for a major event like those, conviction 1, max 3 BUY/SELL lines in total.
   - Never turn a NONE back into BUY/SELL on the same reasoning that downgraded it.
   - Keep "valid until" times unchanged.
3. Update EVENT lines: remove past events, add missing high-impact events for today and the rest of the week (UTC, YYYY.MM.DD HH:MM; currency USD EUR GBP JPY CHF AUD NZD CAD or ALL; no semicolons in descriptions).
4. If anything changed: update the scorecard comment for affected currencies; set the second header line to `# Week of <Monday> | Reviewed <YYYY-MM-DD HH:MM> UTC (daily review)`; keep all other formatting. If a BIAS line was flipped or added, append a row to history/bias-log.csv (week_start = this Monday; start_price verified today with source; three empty fields). If downgraded to NONE, append " (downgraded <date>)" to that row's start_source. Commit "Daily review <date>" and push (see common.md). If nothing changed, don't commit. Touch no other file.
5. Briefing (phone-length): headline ("No changes" or what changed); each active bias with pair, direction, conviction and KEPT/DOWNGRADED/FLIPPED/ADDED plus a one-line reason; 2-3 bullets of key news; today's high-impact events in London time (EA won't open trades within 30 min of them); sources; disclaimer line; next run time.
6. Schedule the next run (common.md).
