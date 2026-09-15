// Everything that touches the browser: the toolbar button, the context menus, the keyboard command, and the one
// awkward act of opening a `cue://` link from an extension.
//
// Chrome runs this as a service worker, which can be stopped at any moment, so nothing is kept in memory between
// events: every handler reads what it needs and finishes.

// Firefox exposes `browser`, Chrome exposes `chrome`; both answer promises under Manifest V3.
const api = globalThis.browser ?? globalThis.chrome;

// Chrome's service worker has to pull the helpers in itself. Firefox lists both files in the manifest, and there
// `importScripts` does not exist — hence the guard rather than a bare call.
if (typeof importScripts === "function" && globalThis.Cue === undefined) {
    importScripts("cue.js");
}

const DEFAULTS = {
    // Sending one tab leaves it open: it is usually the tab being read, and closing what someone is looking at is
    // rude.
    closeAfterSendingOne: false,
    // Sending every YouTube tab closes them, because that is the whole point of the gesture: the tabs were the
    // list, and Cue now holds it.
    closeAfterSendingAll: true,
};

async function settings() {
    return { ...DEFAULTS, ...(await api.storage.sync.get(DEFAULTS)) };
}

/// Hands a link to the operating system, which gives it to Cue.
///
/// An extension cannot open a `cue://` link directly, so it opens a tab at that address and closes it once the
/// handler has taken over. The tab is created in the background and removed on the next turn of the event loop
/// plus a moment: closing it immediately can cancel the navigation before the handler sees it, and leaving it
/// open leaves a blank tab behind.
async function openInCue(link) {
    const tab = await api.tabs.create({ url: link, active: false });
    await new Promise((resolve) => setTimeout(resolve, 500));
    try {
        await api.tabs.remove(tab.id);
    } catch {
        // The browser may have closed it already, which is the outcome we wanted anyway.
    }
}

/// Shows a short message on the toolbar button. There is no notification permission and none is wanted: a badge
/// says "it worked" without a system alert, and clears itself.
async function flash(text, isError = false) {
    try {
        await api.action.setBadgeBackgroundColor({ color: isError ? "#b3261e" : "#1f6f43" });
        await api.action.setBadgeText({ text });
        setTimeout(() => api.action.setBadgeText({ text: "" }), 2500);
    } catch {
        // Badges are cosmetic; a browser that refuses one must not fail the send.
    }
}

async function send(urls, { closeTabIds = [] } = {}) {
    const result = globalThis.Cue.cueLinkFor(urls);
    if (result === null) {
        await flash("—", true);
        return 0;
    }
    await openInCue(result.link);
    if (closeTabIds.length > 0) {
        try {
            await api.tabs.remove(closeTabIds);
        } catch {
            // A tab that has already gone is not a failure: the videos are in Cue either way.
        }
    }
    await flash(String(result.count));
    return result.count;
}

/// Every YouTube video tab in the current window, in the order they sit in the tab strip.
async function youTubeTabsInCurrentWindow() {
    const tabs = await api.tabs.query({ currentWindow: true });
    return tabs.filter((tab) => globalThis.Cue.videoIdFromURL(tab.url ?? "") !== null);
}

async function sendCurrentTab() {
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    if (tab === undefined) {
        return;
    }
    const { closeAfterSendingOne } = await settings();
    const sent = await send([tab.url ?? ""], { closeTabIds: closeAfterSendingOne ? [tab.id] : [] });
    if (sent === 0) {
        // Nothing was sent, so the tab stays whatever the setting says: closing it would throw away the page
        // without having done anything with it.
    }
}

async function sendAllYouTubeTabs() {
    const tabs = await youTubeTabsInCurrentWindow();
    if (tabs.length === 0) {
        await flash("0", true);
        return;
    }
    const { closeAfterSendingAll } = await settings();
    await send(
        tabs.map((tab) => tab.url ?? ""),
        { closeTabIds: closeAfterSendingAll ? tabs.map((tab) => tab.id) : [] },
    );
}

api.action.onClicked.addListener(() => {
    sendCurrentTab();
});

api.commands.onCommand.addListener((command) => {
    if (command === "send-all-youtube-tabs") {
        sendAllYouTubeTabs();
    } else if (command === "send-current-tab") {
        sendCurrentTab();
    }
});

// Menus are registered on install rather than on every start: a service worker starts often, and creating a menu
// that already exists is an error.
api.runtime.onInstalled.addListener(() => {
    api.contextMenus.removeAll(() => {
        api.contextMenus.create({
            id: "send-link",
            title: "Add this video to Cue",
            contexts: ["link"],
        });
        api.contextMenus.create({
            id: "send-page",
            title: "Add this video to Cue",
            contexts: ["page"],
            documentUrlPatterns: ["*://*.youtube.com/*", "*://youtu.be/*"],
        });
        api.contextMenus.create({
            id: "send-all",
            title: "Send all YouTube tabs to Cue",
            contexts: ["action"],
        });
    });
});

api.contextMenus.onClicked.addListener((info, tab) => {
    if (info.menuItemId === "send-link") {
        send([info.linkUrl ?? ""]);
    } else if (info.menuItemId === "send-page") {
        send([info.pageUrl ?? tab?.url ?? ""]);
    } else if (info.menuItemId === "send-all") {
        sendAllYouTubeTabs();
    }
});
