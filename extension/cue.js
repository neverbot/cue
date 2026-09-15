// Pure helpers: reading video ids out of YouTube URLs and building the link that hands them to Cue.
//
// Deliberately free of browser APIs so the rules live in one readable place. Everything that touches tabs is in
// background.js.

// The id YouTube uses: eleven characters of letters, digits, dash and underscore.
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;

// Hosts whose links carry a video. Anything else is not a YouTube video link, however much it looks like one.
const WATCH_HOSTS = new Set([
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtube-nocookie.com",
    "www.youtube-nocookie.com",
]);
const SHORT_HOSTS = new Set(["youtu.be", "www.youtube.be"]);

// The path forms that name a video directly: /shorts/<id>, /embed/<id>, /live/<id>, /v/<id>.
const PATH_PREFIXES = ["/shorts/", "/embed/", "/live/", "/v/"];

/// The video id in a URL, or null when it holds none. A playlist page, a channel, the home page and a search all
/// return null: the point of this extension is sending videos, and sending "the YouTube home page" is nothing.
function videoIdFromURL(rawURL) {
    if (typeof rawURL !== "string" || rawURL.length === 0) {
        return null;
    }
    // A bare id is accepted so the same function serves a pasted id; the app accepts one too.
    if (VIDEO_ID.test(rawURL)) {
        return rawURL;
    }

    let url;
    try {
        url = new URL(rawURL);
    } catch {
        return null;
    }
    if (url.protocol !== "https:" && url.protocol !== "http:") {
        return null;
    }

    const host = url.hostname.toLowerCase();
    if (SHORT_HOSTS.has(host)) {
        const candidate = url.pathname.slice(1);
        return VIDEO_ID.test(candidate) ? candidate : null;
    }
    if (!WATCH_HOSTS.has(host)) {
        return null;
    }
    if (url.pathname === "/watch") {
        const candidate = url.searchParams.get("v") ?? "";
        return VIDEO_ID.test(candidate) ? candidate : null;
    }
    for (const prefix of PATH_PREFIXES) {
        if (url.pathname.startsWith(prefix)) {
            const candidate = url.pathname.slice(prefix.length).split("/")[0];
            return VIDEO_ID.test(candidate) ? candidate : null;
        }
    }
    return null;
}

/// The canonical watch URL for an id. Cue accepts a bare id too, but a full URL is what the link would have held
/// anyway and it stays readable in a log or a bug report.
function watchURLFor(videoId) {
    return `https://www.youtube.com/watch?v=${videoId}`;
}

/// One `cue://add` link carrying every video, in order and without repeats.
///
/// One link rather than one per video on purpose: each link is a trip through the operating system's handler, a
/// chance for it to ask whether Cue may be opened, and a window coming to the front. Twenty tabs should cost that
/// once, not twenty times.
///
/// Returns null when nothing usable was found, so the caller can say so instead of opening a link that adds
/// nothing.
function cueLinkFor(urls) {
    const ids = [];
    const seen = new Set();
    for (const url of urls) {
        const id = videoIdFromURL(url);
        if (id === null || seen.has(id)) {
            continue;
        }
        seen.add(id);
        ids.push(id);
    }
    if (ids.length === 0) {
        return null;
    }
    const query = ids.map((id) => `url=${encodeURIComponent(watchURLFor(id))}`).join("&");
    return { link: `cue://add?${query}`, count: ids.length };
}

// Visible to background.js, which runs in the same global. No module system: both browsers load these as plain
// scripts, and avoiding a build step keeps the extension readable by whoever installs it.
globalThis.Cue = { videoIdFromURL, watchURLFor, cueLinkFor };
