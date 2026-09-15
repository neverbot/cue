import Foundation

/// The bookmarklet, and the page that installs it.
///
/// No browser lets an outside app create a bookmark: there is no API for it, and the alternative — writing
/// Chrome's bookmarks file or Firefox's `places.sqlite` behind their backs — means touching another app's private
/// store, with that app closed, risking the user's own bookmarks. Cue does not do that. What it can do is reduce
/// the job to one drag, which is what this page is for.
///
/// The page is a single self-contained file opened from disk: no server, no network, no fonts or scripts fetched
/// from anywhere. It has to work in Chrome, Firefox and Safari alike, so the thing that matters — the draggable
/// link — is plain HTML that needs no JavaScript at all. The copy button is an extra that degrades quietly where
/// the clipboard API is unavailable, which `file://` pages sometimes are.
public enum BrowserIntegration {
    /// The bookmarklet itself. Sends whatever page it runs on to Cue.
    ///
    /// Deliberately one short line: a bookmarklet is read by the person installing it, and something they cannot
    /// read is something they are trusting blindly. `encodeURIComponent` is what keeps a URL with its own query
    /// (`?v=…&t=…`) from being cut in half when it becomes the value of `url`.
    public static let bookmarklet =
        "javascript:location.href='cue://add?url='+encodeURIComponent(location.href)"

    /// The file the app writes and opens. Named for what it is, since it appears in a browser's title bar and in
    /// the temporary directory.
    public static let pageFileName = "cue-browser-integration.html"

    /// Said next to the copy button once the bookmarklet is on the clipboard.
    public static let copiedMessage = "Bookmarklet copied. Paste it as the address of a new bookmark."

    /// The whole page, ready to be written to disk.
    public static func page() -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Add to Cue — bookmarklet</title>
        <style>
        :root { color-scheme: light dark; }
        body {
          font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
          margin: 0 auto; padding: 40px 24px 64px; max-width: 46rem;
        }
        h1 { font-size: 22px; margin: 0 0 4px; }
        .lede { margin: 0 0 32px; opacity: 0.75; }
        .drag {
          display: inline-block; padding: 10px 18px; border-radius: 8px;
          border: 1px solid currentColor; text-decoration: none; font-weight: 600;
          cursor: grab;
        }
        .drag:active { cursor: grabbing; }
        .step { margin: 28px 0 0; }
        h2 { font-size: 15px; margin: 32px 0 8px; }
        ol { margin: 0; padding-left: 1.3rem; }
        li { margin: 4px 0; }
        .fallback { margin-top: 40px; }
        input[type=text] {
          width: 100%; box-sizing: border-box; padding: 8px 10px; font-family: ui-monospace, monospace;
          font-size: 12px; border-radius: 6px; border: 1px solid rgba(128,128,128,0.5); background: transparent;
          color: inherit;
        }
        button {
          margin-top: 8px; padding: 7px 14px; border-radius: 6px; font: inherit; font-size: 13px;
          border: 1px solid rgba(128,128,128,0.5); background: transparent; color: inherit; cursor: pointer;
        }
        footer { margin-top: 48px; opacity: 0.7; font-size: 13px; }
        </style>
        </head>
        <body>

        <h1>Add to Cue</h1>
        <p class="lede">Drag this button onto your bookmarks bar. Clicking it on a YouTube page adds that video to
        Cue's queue.</p>

        <p><a class="drag" href="\(bookmarklet)">Add to Cue</a></p>

        <div class="step">
        <h2>Chrome</h2>
        <ol>
          <li>Show the bookmarks bar if it is hidden: <strong>⌘⇧B</strong>.</li>
          <li>Drag the button above onto it.</li>
        </ol>

        <h2>Firefox</h2>
        <ol>
          <li>Show the bookmarks toolbar: right-click an empty part of the tab strip and tick
          <strong>Bookmarks Toolbar</strong>.</li>
          <li>Drag the button above onto it.</li>
        </ol>

        <h2>Safari</h2>
        <ol>
          <li>Show the favourites bar: <strong>⌘⇧B</strong>.</li>
          <li>Drag the button above onto it. Safari may ask for a name; any name will do.</li>
        </ol>
        </div>

        <div class="fallback">
        <h2>If dragging does not work</h2>
        <p>Create a new bookmark by hand and paste this as its address:</p>
        <input type="text" id="code" readonly value="\(bookmarklet)">
        <button id="copy" type="button">Copy</button>
        </div>

        <footer>
        This page came from Cue on this Mac and is a plain file on disk. It loads nothing from the network, and the
        bookmarklet sends nothing anywhere: it hands the address of the page you are on to Cue, on this machine.
        </footer>

        <script>
        // An extra, not the mechanism: the drag above needs no JavaScript. A file:// page does not always get the
        // clipboard API, so every failure falls back to selecting the text for the reader to copy themselves.
        (function () {
          var field = document.getElementById("code");
          var button = document.getElementById("copy");
          function select() { field.focus(); field.setSelectionRange(0, field.value.length); }
          field.addEventListener("click", select);
          button.addEventListener("click", function () {
            select();
            var done = function () { button.textContent = "Copied"; };
            try {
              if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(field.value).then(done, function () {});
                return;
              }
              if (document.execCommand("copy")) { done(); }
            } catch (error) {
              // Nothing to do: the text is selected, which is as far as this page can help.
            }
          });
        })();
        </script>

        </body>
        </html>
        """
    }
}
