domain:agent asked these two questions at its terminal (an AskUserQuestion), and manager:domain relays them here as /coordinate §5b says.

## ¶ASK_RETRY: Choose one: How many times should a failed upload retry?
domain:agent asked: "How many times should a failed upload retry? Support says users give up after the second failure, and each retry holds a worker slot for up to a minute."
Lean: THREE
- [ ] [THREE] Retry three times
  A failed upload is retried up to three times before the user sees an error.
  Cost: not stated by the asker
- [ ] [FIVE] Retry five times
  A failed upload is retried up to five times before the user sees an error.
  Cost: not stated by the asker

## ¶ASK_NOTIFY: Choose one: Should a final failure email the user?
Relayed from domain:agent; the worker gave no reason beyond the question.
Context (manager:domain's own): the mail queue is shared with billing notices.
Lean: YES
- [ ] [YES] Email the user
  A user whose upload finally fails gets an email saying so.
  Cost: not stated by the asker
- [ ] [NO] Show it in the app only
  The failure is shown on the upload page and nowhere else.
  Cost: not stated by the asker
