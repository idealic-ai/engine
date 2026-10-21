# How we write

This is the voice for everything a person or an agent will read: chat replies, tickets and comments, pull requests, reports, runbooks and docs. A skill's template decides the structure of what it produces; this page decides the prose inside it, and wins over any restated copy of these rules. Code comments follow the project's own comment rule.

The skill files you have loaded are written tersely, for agents. Write for people in this voice instead.

## The reader

Write for someone capable who has not been following your work and cannot ask what you meant. Start from what they already know: the operator knows the project, a teammate knows the domain, and a newcomer knows programming but none of our words.

## How much to say

Say what the reader needs to understand or act, then stop.

- A chat reply opens with the answer, adds what the reader needs to trust it, and ends with what you need from them, or simply stops. A short question gets a short answer.
- A ticket, comment, pull request or report opens with what changed and who is asked for what.
- A docs page opens with its subject and explains it fully.

Ask early, and say whom you are asking. Bad news says what happened, what it means for the reader, and what you need. A decision request names the choice, your recommendation and what happens if nobody decides. When nothing is needed, one line is enough. Choices go in the question tool, so a reply can end without a menu.

## Talking about the work

Describe the work in the reader's terms. The skills' own working words, such as gates, checks, guards, ledgers, claims, lanes and patch-ids, stay out of text for people unless the reader asked about them. Write "the tests pass and the change is ready to merge" in place of "gate 3 green, ledger updated".

## Explaining

Start with the main idea in everyday words, then say what happens, why, and what it means for the reader. A small example with real numbers often teaches best. Write connected sentences: "because", "so" and "which means" carry the reasoning. Use a list for steps or options.

Introduce a term in a few words the first time ("a permit, the grant that lets someone spend from a budget") and keep that name. For things the code names, use the code's spelling so the reader can search for it. Describe how things are now; history lives in git.

## A calm tone

A heading names its topic, like a chapter title: "Holds", "How a post is accepted". A short plain statement suits a page readers scan for its rule.

Describe a thing by what it does. Mention what it is not only when a reader would otherwise believe it, and say why that matters. Keep bold for a word being defined or a warning the reader must see. Calm text is easier to trust.

## Honesty and numbers

Say how sure you are: "I measured this", "this comes from the ticket", "I think so, but have not looked". Real numbers are welcome; in a report each one carries its date and what it is out of. Evergreen docs that describe the system leave out counts of its parts, dates and status, which go stale on their own.

## When the reader is an agent

Be exact, because an agent reads literally and cannot ask. A clear "do not" helps here when it gives the reason and says what to do instead. Calm instructions work better than capitals.

## Examples

Chat, asked "did the migration run on staging?"
Before: three paragraphs on how migrations work, ending "so yes."
After: "Yes, it ran on staging at 14:02 and the new column is filled. Nothing needs you."

Chat, with bad news.
Before: "Build failed: TS2345 in claim-linker.ts."
After: "The build on dev failed, so nothing new reached staging and what is there still works. It is a type mismatch in `claim-linker.ts`; I am fixing it and will tell you when it passes."

A ticket comment.
Before: "Gate 3 green, 2 open claims in the ledger, lane C stalled."
After: "The retry fix is running on staging. One question needs Dana, who owns uploads: should a failed upload retry three times or five? Until she decides, uploads keep today's single retry."

A docs page opening.
Before: "Money is held when a job is posted, not when it runs. This page explains holds, for developers new to the market."
After: "Money is set aside when a job is posted. When you post work, its money is set aside at once, much as a hotel holds an amount on your card when you check in. Nothing has run yet, but that money is now spoken for."
