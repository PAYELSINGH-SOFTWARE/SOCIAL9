/* Runs in the first-party top-level page only. No session credentials cross
 * the JavaScript/native boundary. Keep website UI and API behaviour unchanged. */
(() => {
  'use strict';
  if (window.top !== window || !window.Social9Device) return;
  const token = __SOCIAL9_BRIDGE_TOKEN__;
  const origin = location.origin;
  const send = (type, payload = {}) => window.Social9Device.postMessage(
    JSON.stringify({ version: 1, token, origin, type, ...payload })
  );
  if (window.__social9Native) {
    window.__social9Native.ready();
    return;
  }
  const CHUNK = 48 * 1024;
  const PENDING_AUTH = 'social9_native_pending_auth';
  const payments = new Map();
  const acknowledgements = new Map();
  let pollTimer;
  let polling = false;
  let pendingAuth = null;
  const id = () => crypto.randomUUID();
  const ready = () => send('ready', { theme: document.documentElement.dataset.theme || 'dark' });

  const request = (type, payload) => new Promise((resolve, reject) => {
    const requestId = id();
    acknowledgements.set(requestId, { resolve, reject });
    send(type, { ...payload, requestId });
  });

  async function download(url, filename) {
    const downloadId = id();
    try {
      await request('downloadPreparing', { id: downloadId });
      const parsed = new URL(url, location.href);
      if (!['blob:', 'data:', 'https:'].includes(parsed.protocol)) {
        throw new Error('This download link is not supported.');
      }
      // Never attach Social9 bearer credentials to downloads or third parties.
      const response = await fetch(parsed.href, { credentials: parsed.origin === origin ? 'same-origin' : 'omit' });
      if (!response.ok) throw new Error('The export could not be downloaded. Please try again.');
      await request('downloadStart', { id: downloadId, filename: filename || 'social9-export', size: null,
        mime: response.headers.get('content-type') || 'application/octet-stream' });
      let sequence = 0, total = 0;
      const write = async bytes => {
        for (let offset = 0; offset < bytes.length; offset += CHUNK) {
          const chunk = bytes.subarray(offset, offset + CHUNK);
          let binary = '';
          for (let i = 0; i < chunk.length; i++) binary += String.fromCharCode(chunk[i]);
          await request('downloadChunk', { id: downloadId, sequence: sequence++, data: btoa(binary) });
          total += chunk.length;
        }
      };
      if (response.body?.getReader) {
        const reader = response.body.getReader();
        try {
          while (true) {
            const part = await reader.read();
            if (part.done) break;
            await write(part.value);
          }
        } finally { reader.releaseLock(); }
      } else { await write(new Uint8Array(await response.arrayBuffer())); }
      await request('downloadFinish', { id: downloadId, size: total });
    } catch (error) {
      send('downloadAbort', { id: downloadId });
      send('notice', { message: error instanceof Error ? error.message : 'Unable to export this file.' });
    }
  }

  const click = HTMLAnchorElement.prototype.click;
  const isDownload = anchor => anchor.hasAttribute('download') || /^(blob:|data:)/i.test(anchor.href);
  HTMLAnchorElement.prototype.click = function () {
    if (isDownload(this)) { void download(this.href, this.download); return; }
    return click.call(this);
  };
  document.addEventListener('click', event => {
    const anchor = event.target instanceof Element ? event.target.closest('a') : null;
    if (!anchor || !isDownload(anchor)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    void download(anchor.href, anchor.download);
  }, true);

  window.print = () => send('print', { title: document.title || 'Social9 report' });

  // The web page still creates the server-priced order and verifies the signed
  // result with Render. Only Razorpay's device checkout UI is native.
  class NativeRazorpay {
    constructor(options) { this.options = options; this.listeners = {}; this.id = id(); }
    on(event, handler) { this.listeners[event] = handler; }
    open() {
      payments.set(this.id, this);
      const { key, order_id, amount, currency, name, description, prefill, theme } = this.options;
      send('checkout', { id: this.id, options: { key, order_id, amount, currency, name, description, prefill, theme } });
    }
    close() { this.options.modal?.ondismiss?.(); payments.delete(this.id); }
  }
  window.Razorpay = NativeRazorpay;

  const fingerprint = accounts => JSON.stringify(accounts.map(account => ({
    id: account.id, provider: account.provider, status: account.status,
    expires_at: account.expires_at, updated_at: account.updated_at,
    account_name: account.account_name, username: account.username,
  })).sort((a, b) => a.id - b.id));

  async function accountState() {
    const accessToken = localStorage.getItem('social9_access_token') || sessionStorage.getItem('social9_access_token');
    if (!accessToken) return null;
    const brand = localStorage.getItem('social9_active_brand_id');
    const response = await fetch('/service/social-accounts', {
      headers: { Accept: 'application/json', Authorization: `Bearer ${accessToken}`, ...(brand ? { 'X-Brand-ID': brand } : {}) },
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) return null;
    const accounts = await response.json();
    return Array.isArray(accounts) ? fingerprint(accounts) : null;
  }
  const readAuth = () => {
    try { return JSON.parse(sessionStorage.getItem(PENDING_AUTH) || 'null'); }
    catch (_) { return null; }
  };
  function clearAuth() {
    clearTimeout(pollTimer);
    pendingAuth = null;
    sessionStorage.removeItem(PENDING_AUTH);
    send('authFinished');
  }
  async function pollAccounts() {
    if (polling || document.visibilityState === 'hidden') return;
    pendingAuth = readAuth();
    if (!pendingAuth) return;
    if (Date.now() - pendingAuth.started > 10 * 60 * 1000) { clearAuth(); return; }
    polling = true;
    try {
      const state = await accountState();
      const current = readAuth();
      if (!current) return;
      pendingAuth = current;
      if (state !== null && pendingAuth.baseline === null) {
        // A cold/offline backend may prevent the initial snapshot. Establish a
        // baseline on recovery; do not falsely report authorization complete.
        pendingAuth.baseline = state;
        sessionStorage.setItem(PENDING_AUTH, JSON.stringify(pendingAuth));
      } else if (state !== null && state !== pendingAuth.baseline) {
        clearAuth();
        location.assign('/accounts');
        return;
      }
    } catch (_) { /* The normal website UI handles network errors. */ }
    finally { polling = false; }
    pollTimer = setTimeout(() => void pollAccounts(), 3000);
  }
  async function beginAuth() {
    let baseline = null;
    try { baseline = await accountState(); } catch (_) { /* allow provider launch */ }
    pendingAuth = { started: Date.now(), baseline };
    sessionStorage.setItem(PENDING_AUTH, JSON.stringify(pendingAuth));
    send('authPending');
    void pollAccounts();
  }

  function closeOverlay() {
    if (document.fullscreenElement) { void document.exitFullscreen(); return true; }
    const dialog = [...document.querySelectorAll('dialog[open]')].pop();
    if (dialog) {
      const event = new Event('cancel', { cancelable: true });
      if (dialog.dispatchEvent(event)) dialog.close();
      return true;
    }
    const menu = document.querySelector('.dashboard-menu-toggle[aria-expanded="true"]');
    if (menu) { menu.click(); return true; }
    return false;
  }
  window.__social9Native = Object.freeze({
    ready, beginAuth, clearAuth, closeOverlay,
    acknowledge(result) {
      const pending = acknowledgements.get(result.requestId);
      if (!pending) return;
      acknowledgements.delete(result.requestId);
      if (result.error) pending.reject(new Error(result.error));
      else pending.resolve();
    },
    resume() {
      clearTimeout(pollTimer);
      const auth = readAuth();
      // Refresh the website's React account state/button after browser consent
      // or cancellation. A persisted timestamp prevents reload loops.
      if (auth && location.pathname === '/accounts' && Date.now() - (auth.lastRefresh || 0) > 3000) {
        auth.lastRefresh = Date.now();
        sessionStorage.setItem(PENDING_AUTH, JSON.stringify(auth));
        location.reload();
        return;
      }
      void pollAccounts(); ready();
    },
    paymentResult(result) {
      const payment = payments.get(result.id);
      if (!payment) return;
      payments.delete(result.id);
      if (result.status === 'success') payment.options.handler?.(result.response);
      else {
        if (result.status === 'failed') payment.listeners['payment.failed']?.({ error: { description: result.message || 'Payment was cancelled or failed.' } });
        payment.options.modal?.ondismiss?.();
      }
    },
  });
  const observer = new MutationObserver(ready);
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') window.__social9Native.resume();
    else clearTimeout(pollTimer);
  });
  if (readAuth()) { send('authPending'); void pollAccounts(); }
  if (/^\/accounts\/?$/.test(location.pathname) && new URLSearchParams(location.search).has('connected')) clearAuth();
  ready();
})();
