# Cue's browser extension

Sends YouTube videos to Cue instead of leaving tabs open for weeks. One video, one link, or every YouTube tab in
the window at once — after which the tabs can close, because Cue is holding the list now.

It works with Firefox and Chrome from the same sources: only the manifest differs.

## What it does

| Gesture | Does |
|---|---|
| Click the toolbar button | Adds the video in the current tab |
| ⌘⇧U (Ctrl+Shift+U elsewhere) | The same, without reaching for the mouse |
| ⌘⇧Y (Ctrl+Shift+Y elsewhere) | Sends every YouTube tab in the window, then closes them |
| Right-click a link ▸ Add this video to Cue | Adds a video without opening it first |
| Right-click the toolbar button ▸ Send all YouTube tabs | The batch, for anyone who prefers menus |

A short badge on the toolbar button says how many videos went across; a dash means the page was not a YouTube
video, which is the honest answer for a playlist, a channel or a search.

Two settings, in the extension's own options: whether to close a single tab after sending it (off — it is usually
the tab you are reading) and whether to close the tabs after sending all of them (on — that is the point of the
gesture).

## What it does not do

- **It never injects anything into a page.** There are no content scripts and no host permissions. It reads the
  address of a tab, which is what the `tabs` permission is for, and nothing else about it.
- **It talks to nothing but Cue on your own Mac.** The link it opens is `cue://add?url=…`, which macOS hands to
  the app. No server of ours exists, and the extension has no network permission at all.
- **It does not read your history, your cookies or the page contents.**

## Installing it

Build the two directories first:

```sh
scripts/make-extension.sh
```

- **Chrome** — `chrome://extensions`, turn on Developer mode, Load unpacked, choose `dist/extension/chrome`.
- **Firefox** — `about:debugging#/runtime/this-firefox`, Load Temporary Add-on, choose
  `dist/extension/firefox/manifest.json`.

Firefox forgets a temporary add-on when it restarts. Installing one permanently means a signed build, which needs
an account on addons.mozilla.org; that is the one step here that cannot be done from this repository.

Cue itself must be installed, and macOS has to know which app answers `cue://` links. Building the app once
(`scripts/make-app.sh`) and opening it is enough for Launch Services to register the scheme.

## The bookmarklet

If an extension is more than you want, a bookmark does the single-tab case with no install at all. The easiest way
to add it is from the app: **Cue ▸ Browser Integration…** opens a page with a button to drag onto the bookmarks
bar, and the steps for Chrome, Firefox and Safari. The same buttons are in Settings ▸ Browser Integration.

To do it by hand instead, make a new bookmark whose address is this line:

```
javascript:(function(){var a=document.createElement('a');a.href='cue://add?url='+encodeURIComponent(location.href);document.body.appendChild(a);a.click();a.remove();})()
```

It clicks a synthetic link instead of assigning `location.href`, so you stay on the page, and it returns nothing —
a `javascript:` URL that produces a value makes the browser replace the page with it.

Clicking it on a YouTube page adds that video to Cue. It cannot do the batch — a bookmarklet only ever sees the
page it runs on — and some browsers refuse to run `javascript:` bookmarks typed into the address bar, so it has to
be clicked from the bookmarks bar.

## Why one link for many videos

Handing over twenty tabs opens **one** `cue://add` link carrying twenty `url` parameters, not twenty links. Each
link is a trip through Launch Services, a chance for macOS to ask whether Cue may be opened, and a window coming
to the front; twenty of those for one gesture would be unusable. Cue's own parser accepts the repeated parameter
and adds every video it can read, ignoring the ones it cannot — so one dead tab in a batch of twenty does not stop
the other nineteen.

## The files

| File | Responsibility |
|---|---|
| `cue.js` | Pure rules: which URLs name a video, and how the `cue://add` link is built. No browser APIs |
| `background.js` | Everything that touches the browser: button, menus, commands, opening the link |
| `options.html`, `options.js` | The two settings |
| `manifest.chrome.json` | Chrome: background as a service worker |
| `manifest.firefox.json` | Firefox: background as scripts, plus the add-on id |

There is no build step and no dependency: it is plain JavaScript, so what you install is what is written here.
