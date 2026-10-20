# Shared steps for every scheduled run

These runs arrive as messages in Sam's long-running Claude conversation, which has push access to this repo. They are unattended: make reasonable calls, never wait for an answer.

## Before starting
1. Get the current date/time with the current-time tool (UK = Europe/London).
2. Make sure the repo is ready:
   - If `/home/claude/fx-signals/.git` exists: `git -C /home/claude/fx-signals pull --rebase origin main`.
   - If it doesn't (the container was reset): load `mcp__claude-code-remote__add_repo` with ToolSearch if needed, call it with owner `samjohnoliveira`, repo `fx-signals`, access `push`, and clone it as its result instructs to `/home/claude/fx-signals`.
   - Make sure git config user.name is `Claude` and user.email is `noreply@anthropic.com` in the clone.
3. Read `ops/` and the procedure named in the message. Read `bias.txt` and `history/bias-log.csv`.

## Pushing
- Commit messages end with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `git fetch origin main`, rebase if needed, `git push origin HEAD:main`.
- If the push fails: retry once after re-attaching the repo with add_repo. If it still fails, the message headline must say "PUSH FAILED - EA still on the old bias" and include the full replacement BIAS lines.

## Messaging Sam
- Send the briefing with SendUserMessage (load it with ToolSearch if not listed).
- Also send a short phone notification with PushNotification (load it with ToolSearch if not listed): one line with the headline.
- End every briefing with one line: general market commentary, not financial advice; the EA trades a demo account; forex trading carries a high risk of loss.
- Include a short "Sources:" list of markdown links.

## Scheduling the next run (do this LAST, every time, even if something else failed)
Use `mcp__claude-code-remote__send_later` (load with ToolSearch if needed) with `initiation: "human_schedule"`:
- After a daily review on Monday-Thursday: next weekday at 06:50 Europe/London, message: `Scheduled run: daily forex bias review. Follow ops/common.md and ops/daily-review.md in /home/claude/fx-signals.`
- After a daily review on Friday: the coming Sunday at 18:49 Europe/London, message: `Scheduled run: weekly forex bias rebuild. Follow ops/common.md and ops/weekly-rebuild.md in /home/claude/fx-signals.`
- After a weekly rebuild: the next Monday at 06:50 Europe/London, daily review message as above.
Convert the London time to UTC correctly for the `at` field (BST = UTC+1 until the last Sunday of October, then GMT = UTC+0 until the last Sunday of March).
Before scheduling, check with `mcp__claude-code-remote__list_triggers` that an equivalent future run isn't already scheduled, so runs never double up. Name it "Forex daily review" or "Forex weekly rebuild".
Finish by stating the next run's date and time (London) at the end of the briefing.
