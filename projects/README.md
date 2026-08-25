# projects/

Per-VM working directory. **Contents are gitignored** — nothing in here is
pushed to this repo.

Each project VM checks out what it needs locally:

    projects/once-campfire/    the chat app itself, if you want to modify it
    projects/<app>/            this project's application source

They are separate git repositories with their own remotes. Keeping them out of
this repo means a VM never receives another project's code, and this public
repo never carries application source.
