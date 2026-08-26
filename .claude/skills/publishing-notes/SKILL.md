---
name: publishing-notes
description: Publish a long or structured answer as an HTML page instead of pasting it into chat — benchmarks, comparisons, plans, tables, diagrams, anything with structure. Use whenever a reply would be more than a few lines, or contains a table, a long code block, or more than one heading.
---

# Publish it, don't paste it

Chat is a bad medium for anything with structure. A benchmark table, a
migration plan, a comparison of three options — pasted into Campfire it becomes
a wall of text on a phone screen.

Write an HTML file instead and send the link:

    /srv/notes/<name>.html   ->   https://notes.<project>.appsmoothly.com/<name>.html

`<project>` is this VM's hostname. Get the full URL without thinking about it:

    echo "https://notes.$(hostname).appsmoothly.com/gin-benchmark.html"

## Doing it

    cat > /srv/notes/gin-benchmark.html <<'HTML'
    <!doctype html><meta charset=utf-8>
    <meta name=viewport content="width=device-width,initial-scale=1">
    <title>Gin benchmark</title>
    <style>
     body{font:16px/1.6 system-ui,sans-serif;max-width:46rem;margin:3rem auto;padding:0 1rem;
          background:#fbfbfa;color:#1a1a19}
     h1,h2{line-height:1.25} table{border-collapse:collapse;width:100%}
     th,td{text-align:left;padding:.4rem .6rem;border-bottom:1px solid #ddd}
     pre{background:#f2f2f0;padding:.8rem;border-radius:6px;overflow-x:auto}
     code{background:#eee;padding:.1rem .3rem;border-radius:3px}
     @media(prefers-color-scheme:dark){body{background:#191918;color:#e8e8e6}
      pre{background:#242422} code{background:#242422} th,td{border-color:#333}}
    HTML
    HTML

Then say one line in chat with the link. Not a summary of the page — the link,
and the single sentence that says whether the answer was yes or no.

## Rules

* **The page is the detail; chat is the verdict.** Do not paste the content and
  also link it.
* **Name the file after the question**, lowercase with dashes:
  `gin-benchmark.html`, `auth-options.html`. It is a permanent URL and the
  directory is browsable at `https://notes.<project>.appsmoothly.com/`.
* **Self-contained.** No CDN, no external stylesheet — this VM is not on the
  public internet from the reader's side and the page must render offline.
* **It inherits the project's exposure.** On a public project anyone past the
  login can read it. Do not put a secret on a page.
* **Overwrite freely.** Same question asked again, same filename.

Mermaid, images, small bits of JS all work — it is a real page, served by the
same Caddy that serves everything else here. Nothing needs to be configured;
`/srv/notes` and the route already exist.
