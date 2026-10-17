# Interview bank

Ask group by group, one group per message and at most three questions in it, each with
your recommended answer and the reason. If a group still has more than three questions after
skips, split it over two messages.
Skip a question when the data or the files already answer it, and say what answered it.
Record every answer, and every skip, in the design doc.

## Decisions

1. **Who decides, and how often?** One person in long stretches, or several in short
   bursts? (This sets whether "one kind of work at a time" and view-only access matter.)
2. **What makes a record good enough to publish?** Get the rubric in their words: on topic,
   which fields must be filled, what disqualifies. The agents' verdicts are written against
   it.
3. **What must never change without a human?** For example publish/hide flags, featured
   slots, prices, anything legal. These become protected fields.
4. **What can't be undone?** For example sending an email, deleting a record, notifying a
   partner. Each one either stays a draft or needs its own confirm.

## Sources

5. **Which sources did the files miss?** Show the source table and ask what's absent. Name
   the discovery row explicitly: "Do new items ever appear that nobody sends you?"
6. **Who expects a reply, and in whose voice?** Ask for two or three past replies as
   samples. Replies stay drafts.

## Running it

7. **Where can a page be hosted, and how do people sign in?** This decides the port
   ([porting.md](porting.md)). Ask before proposing a lighter surface.
8. **Where do the agents run, and what may they cost?** A laptop on a schedule, CI, or a
   cloud routine; a monthly token budget.
9. **Who else needs to see it, read-only?**

## Knowing it worked

10. **What would make this worth it in two weeks?** Agree one number against the baseline
    from step 1: the waiting count, time from arrival to decision, or decisions per week.
