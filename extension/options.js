// Two checkboxes, stored in the browser's own synced settings. No other state exists.

const api = globalThis.browser ?? globalThis.chrome;

const DEFAULTS = {
    closeAfterSendingOne: false,
    closeAfterSendingAll: true,
};

async function load() {
    const stored = { ...DEFAULTS, ...(await api.storage.sync.get(DEFAULTS)) };
    for (const key of Object.keys(DEFAULTS)) {
        const box = document.getElementById(key);
        box.checked = stored[key] === true;
        // Written on change rather than behind a Save button: two checkboxes do not need a form to submit.
        box.addEventListener("change", () => api.storage.sync.set({ [key]: box.checked }));
    }
}

load();
