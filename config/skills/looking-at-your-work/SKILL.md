---
name: looking-at-your-work
description: Look at a page or app with a real browser before claiming it works - take a screenshot at phone size, or record a video of a flow and show it to the owner. Use after building or changing any screen, before saying it looks right, when a layout might break on a phone, or when showing off what you just made. Triggers on - check how it looks, is it broken on mobile, show them the new page, record what happens, verify the UI.
---

# Looking at your work

The box has Chrome. You do not have to describe a screen you have never seen, or
ask the owner to be your eyes.

```
~/appsmoothly/bin/screenshot <url> [out.png] [width,height]   # one frame, fast
~/appsmoothly/bin/record     <url> [out.mp4] [seconds] [WxH]  # a video
```

Both default to a phone-sized viewport (390×844), because that is what they are
holding. Read the PNG back with your own file tools — you can see it.

## Use it on

- Their app: `http://localhost:3100` (the TRY IT address).
- Anything you published: `http://localhost:3000/ui/<name>.html`.
- A pop-up you are about to send them, before you send it.

## Screenshots

```bash
~/appsmoothly/bin/screenshot http://localhost:3100 tmp/home.png
~/appsmoothly/bin/screenshot http://localhost:3100 tmp/wide.png 1280,800
```

Then read `tmp/home.png`. Look for the things a person notices first: text
running off the edge, a button below the fold, a form that needs two hands, an
empty state that looks like a bug.

## Videos

`bin/record` writes into `~/public` by default and prints the `/ui/` address it
is published at, so you can hand it straight to `show_page` — an mp4 there plays
and seeks properly on an iPhone.

```bash
~/appsmoothly/bin/record http://localhost:3100 ~/public/tour.mp4 12
```

While it records, the page is live on an X display whose name it prints, so you
can drive a whole flow and capture it:

```bash
DISPLAY=:96 xdotool mousemove 195 420 click 1     # tap
DISPLAY=:96 xdotool type "hello@example.com"      # type
```

Start the recording in the background, drive the page, and let it finish.

To show it to them, write a page with a `<video>` tag and call `show_page`:

```html
<video src="/ui/tour.mp4" controls autoplay muted playsinline
       style="width:100%;border-radius:10px"></video>
```

`muted` and `playsinline` are what let it start on its own on a phone.

## When

Screenshot after you build or change a screen, and before you tell them it
works. Record when the thing worth showing *moves* — a flow through a form, a
before-and-after, a feature tour. A ten second video costs you one command and
saves them reading three paragraphs.

Don't send a video where a sentence would do.
