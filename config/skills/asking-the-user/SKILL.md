---
name: asking-the-user
description: Ask the box's owner a question, or show them something, as a real screen instead of terminal text. Use whenever you need a decision, a choice between options, several facts at once, a confirmation before something irreversible, or want to show a preview, a summary or a chart. Triggers on - asking what they want, offering options, collecting details, confirming a deploy or a deletion, showing progress or results.
---

# Asking the user

The person reading your terminal is not a programmer, and is usually on a phone.
Anything more complicated than one short sentence is easier for them as a screen
they can tap than as prose they have to read and answer in a text box.

You have two tools for this:

- `ask_user` — show a page and **wait**. Returns what they filled in, as JSON.
- `show_page` — show a page and carry on. Returns immediately.

Both take a file you have already written into `~/public`.

## The loop

1. Write the HTML into `~/public/something.html`.
2. Call `ask_user` with `path: "something.html"` and a short `title`.
3. It appears over their terminal. They tap.
4. You get their answer back and keep working.

## The contract

You never write any JavaScript for this. The box injects the plumbing.

- Any `<form>` posts back when submitted. Every `name` becomes a key in what you
  get back.
- A `<button name="choice" value="deploy">` tells you which button they pressed.
- A bare `<button data-answer="yes">` outside a form works too — the shortest way
  to ask something.
- Checkboxes sharing a name come back as a list.
- If they close it without answering, you're told that, so don't wait forever on
  someone who has walked away.

## What makes it good

- **One question per page.** If you need five facts, five fields on one page is
  fine — five separate pop-ups is not.
- **Big targets.** Full-width buttons, at least 48px tall. They have thumbs.
- **Their words, not yours.** "Should the shop take card payments?" — not
  "Enable Stripe integration?". Never a file path, a flag name or a
  library in the visible text.
- **Their language.** Everything on the page is in `$APPSMOOTHLY_LANGUAGE`.
- **Say what happens next** on the button itself: "Put it live", "Delete these
  40 orders", "Not yet".
- **Recommend one.** If there's an obvious default, mark it and put it first.
- Don't ask what you can decide. This is for decisions that are genuinely theirs
  — money, data loss, what the product should do.

## Template

Copy this. It is deliberately plain: one file, no build step, no fonts to fetch,
readable on the smallest phone, and it matches the terminal it appears over.

```html
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  :root { --bg:#efe9dc; --panel:#faf6ee; --ink:#4c473c; --soft:#857d6b;
          --line:#ddd3c0; --go:#5e9c72; --stop:#c25f50; }
  * { box-sizing:border-box; }
  body { margin:0; padding:20px; background:var(--bg); color:var(--ink);
         font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }
  h1 { font-size:22px; line-height:1.25; margin:0 0 8px; }
  p  { color:var(--soft); margin:0 0 20px; }
  label { display:block; margin:0 0 16px; font-weight:500; }
  input,select,textarea { display:block; width:100%; margin-top:6px; padding:14px;
    font:inherit; background:var(--panel); color:var(--ink);
    border:1px solid var(--line); border-radius:10px; }
  button { display:block; width:100%; min-height:52px; margin:0 0 10px; padding:14px;
    font:inherit; font-weight:600; background:var(--panel); color:var(--ink);
    border:1px solid var(--line); border-radius:10px; cursor:pointer; }
  button.go   { background:var(--go);   border-color:var(--go);   color:#fff; }
  button.stop { background:var(--stop); border-color:var(--stop); color:#fff; }
  .choice { display:flex; gap:12px; align-items:flex-start; padding:14px;
    margin:0 0 10px; background:var(--panel); border:1px solid var(--line);
    border-radius:10px; font-weight:400; }
  .choice input { width:auto; margin:2px 0 0; }
  .note { font-size:14px; color:var(--soft); font-weight:400; }
</style></head>
<body>
  <h1>Should the shop take card payments?</h1>
  <p>You can change this later — nothing goes live until you say so.</p>

  <form>
    <label class="choice">
      <input type="radio" name="payments" value="cards" checked>
      <span><strong>Yes, cards</strong><br>
        <span class="note">Customers pay online. Takes about a day to set up.</span></span>
    </label>
    <label class="choice">
      <input type="radio" name="payments" value="cash">
      <span><strong>No, pay on collection</strong><br>
        <span class="note">Simplest. You can add cards any time.</span></span>
    </label>

    <label>What should the confirmation email say?
      <textarea name="email_note" rows="3" placeholder="Thanks for your order!"></textarea>
    </label>

    <button class="go" name="choice" value="save" type="submit">Save this</button>
    <button name="choice" value="later" type="submit">Decide later</button>
  </form>
</body></html>
```

That returns something like `{"payments":"cards","email_note":"…","choice":"save"}`.

## When not to use it

A quick yes/no in the flow of conversation is fine as a sentence in the
terminal. Use a pop-up when the answer has shape — options, several fields, or
consequences worth showing them before they commit.
