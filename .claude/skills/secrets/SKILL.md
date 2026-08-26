---
name: secrets
description: Ask the human for a credential without it going through chat, and use it afterwards — API tokens, deploy keys, anything that should not sit in the transcript. Use when you need a value you do not have, or when told "don't paste that here".
---

# Asking for a secret

Never ask someone to paste a token into chat. Campfire keeps the message, and
the transcript is the one place a credential should not live.

    ask-secret GITHUB_TOKEN "to push the project repo"

That posts a **one-time link into whichever room you were addressed in** — the
bridge passes the room through, so a request made in one room does not surface
in another. The human opens the link, pastes the value into a form, and it lands
in `~/.secrets/GITHUB_TOKEN` (`0600`, yours to read). The confirmation comes
back in the same room; the value itself never appears in chat.

Run outside chat (a shell, a timer), it falls back to the direct room.

The link works once. Asking again issues a new one.

## Using it

    secret GITHUB_TOKEN                       # print it
    secret --list                             # names only, never values
    secret --run GITHUB_TOKEN -- git push     # exported for that command only

Prefer `--run`: the value goes into one process's environment instead of your
scrollback, which keeps it out of anything you later paste back into chat.

**You can read these.** The point is keeping the value out of the transcript,
not hiding it from you. Do not print one into chat, do not commit one, and do
not echo one in a command whose output you will summarise.

## GitHub is already wired up

`GITHUB_TOKEN` is the one name with plumbing behind it. Ask for it the usual
way and git starts working — no further setup:

    ask-secret GITHUB_TOKEN "to fetch and push the project repo"

A credential helper reads `~/.secrets/GITHUB_TOKEN` for `https://github.com`
and nothing else. With no token stored it does nothing, so a VM without one
behaves exactly as before. Check it took:

    git -C projects/<repo> ls-remote origin >/dev/null && echo ok

Prefer a **fine-grained token limited to the one repo** this VM works on. A
whole-account token in here is worth avoiding: this box runs an agent with
permissions off, so the blast radius of the token is the blast radius of the
box.

## Putting it somewhere permanent

`~/.secrets/` is a landing pad, not storage. Move the value where it belongs:

    # Rails encrypted credentials
    secret --run STRIPE_KEY -- bash -c \
      'EDITOR="cat" bin/rails credentials:edit'   # inspect first
    bin/rails credentials:edit                     # then add it properly

    # a systemd unit
    printf 'STRIPE_KEY=%s\n' "$(secret STRIPE_KEY)" | sudo tee /etc/myapp/env
    sudo chmod 600 /etc/myapp/env

Once it is stored properly, delete the landing copy:

    rm ~/.secrets/STRIPE_KEY

## How it works, briefly

The form is served by the **bot bridge**, which is already running in this VM —
no separate service. Caddy routes `secret.<project>...` to it. Nothing leaves
the VM: the hypervisor is not involved, and the value is written locally.
