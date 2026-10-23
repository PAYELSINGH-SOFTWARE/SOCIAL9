import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import vm from 'node:vm';

const source = readFileSync(new URL('../assets/mobile_bridge.js', import.meta.url), 'utf8')
  .replace('__SOCIAL9_BRIDGE_TOKEN__', JSON.stringify('per-document-test-secret'));
function setup({ childFrame = false, native = true, acknowledge = true, fetch = async () => new Response('') } = {}) {
  const messages = [], events = {}, timers = [], requests = [];
  const local = new Map(), session = new Map();
  const storage = map => ({ getItem: key => map.get(key) ?? null,
    setItem: (key, value) => map.set(key, value), removeItem: key => map.delete(key) });
  class Anchor { constructor() { this.href = ''; this.download = ''; this.attributes = new Set(); }
    hasAttribute(name) { return this.attributes.has(name); }
    click() { this.originalClicked = true; }
  }
  const document = {
    documentElement: { dataset: { theme: 'light' } }, visibilityState: 'visible', title: 'Social9',
    addEventListener: (name, handler) => { events[name] = handler; },
    querySelectorAll: () => [], querySelector: () => null,
  };
  const location = { origin: 'https://www.social9.io', href: 'https://www.social9.io/accounts',
    pathname: '/accounts', search: '', assign: value => requests.push(value), reload: () => requests.push('reload') };
  const window = { location, top: null, document };
  window.top = childFrame ? {} : window;
  if (native) window.Social9Device = { postMessage: value => {
    const message = JSON.parse(value);
    messages.push(message);
    if (acknowledge && message.requestId) queueMicrotask(() => window.__social9Native.acknowledge({requestId: message.requestId}));
  } };
  const context = vm.createContext({ window, document, location,
    localStorage: storage(local), sessionStorage: storage(session),
    HTMLAnchorElement: Anchor, Element: class {}, Event, URL, URLSearchParams,
    crypto: webcrypto, AbortSignal, Uint8Array,
    MutationObserver: class { constructor(callback) { this.callback = callback; } observe() {} },
    fetch: (...args) => { requests.push(args); return fetch(...args); },
    btoa: input => Buffer.from(input, 'binary').toString('base64'),
    setTimeout: (callback, delay) => {
      if (delay === 0) queueMicrotask(callback);
      else timers.push(callback);
      return timers.length;
    }, clearTimeout() {},
  });
  vm.runInContext(source, context);
  return { window, messages, document, events, requests, context, Anchor, local, session, timers };
}
const settle = () => new Promise(resolve => setImmediate(resolve));

test('does not expose device actions in a child frame or ordinary web browser', () => {
  for (const options of [{ childFrame: true }, { native: false }]) {
    const app = setup(options);
    assert.equal(app.messages.length, 0);
    assert.equal(app.window.__social9Native, undefined);
  }
});
test('bridge messages identify protocol, origin and the per-document secret', () => {
  const { messages } = setup();
  assert.deepEqual(messages[0], { version: 1, token: 'per-document-test-secret',
    origin: 'https://www.social9.io', type: 'ready', theme: 'light' });
});
test('re-injection is idempotent and does not duplicate event hooks', () => {
  const app = setup();
  const original = app.window.__social9Native;
  vm.runInContext(source, app.context);
  assert.equal(app.window.__social9Native, original);
  assert.equal(app.messages.filter(m => m.type === 'ready').length, 2);
});
test('normal links keep their browser behaviour', () => {
  const { Anchor } = setup();
  const anchor = new Anchor(); anchor.href = 'https://www.social9.io/templates';
  anchor.click();
  assert.equal(anchor.originalClicked, true);
});
test('blob exports transfer exact binary bytes before object-URL revocation', async () => {
  const { Anchor, messages, requests } = setup({ fetch: async () => new Response(new Uint8Array([0, 128, 255, 1])) });
  const anchor = new Anchor(); anchor.href = 'blob:https://www.social9.io/export'; anchor.download = 'report.csv';
  anchor.attributes.add('download'); anchor.click(); await settle();
  const start = messages.find(m => m.type === 'downloadStart');
  const chunks = messages.filter(m => m.type === 'downloadChunk');
  assert.equal(start.size, null); assert.equal(start.filename, 'report.csv');
  assert.deepEqual([...Buffer.from(chunks[0].data, 'base64')], [0, 128, 255, 1]);
  assert.equal(messages.at(-1).type, 'downloadFinish');
  assert.equal(requests[0][1].headers, undefined);
});
test('large exports use bounded, sequential 48 KB chunks', async () => {
  const bytes = new Uint8Array(130000).fill(123);
  const app = setup({ fetch: async () => new Response(bytes) });
  const anchor = new app.Anchor(); anchor.href = 'blob:https://www.social9.io/cover'; anchor.click(); await settle();
  const chunks = app.messages.filter(m => m.type === 'downloadChunk');
  assert.deepEqual(chunks.map(m => m.sequence), [0, 1, 2]);
  assert.ok(chunks.every(m => m.data.length <= 65536));
  assert.deepEqual(Buffer.concat(chunks.map(m => Buffer.from(m.data, 'base64'))), Buffer.from(bytes));
});
test('streams exports without the old 50 MB header cap and rejects local links', async () => {
  const app = setup({ fetch: async () => new Response('', { headers: { 'content-length': 60 * 1024 * 1024 } }) });
  const anchor = new app.Anchor(); anchor.href = 'https://www.social9.io/huge';
  anchor.attributes.add('download'); anchor.click(); await settle();
  assert.equal(app.messages.at(-1).type, 'downloadFinish');
  anchor.href = 'file:///private'; anchor.click(); await settle();
  assert.match(app.messages.at(-1).message, /not supported/);
  assert.equal(app.messages.filter(m => m.type === 'downloadStart').length, 1);
});
test('website checkout retains its success/verification callback', () => {
  const app = setup(); let verified;
  const payment = new app.window.Razorpay({ key: 'rzp_test_public', order_id: 'order_server',
    theme: {color: '#8e44ad'}, handler: value => { verified = value; } });
  payment.open();
  const request = app.messages.find(m => m.type === 'checkout');
  assert.equal(request.options.order_id, 'order_server');
  assert.equal(request.options.handler, undefined);
  assert.equal(request.options.theme.color, '#8e44ad');
  const response = { razorpay_payment_id: 'pay_signed', razorpay_signature: 'server-verifies-this' };
  app.window.__social9Native.paymentResult({ id: request.id, status: 'success', response });
  assert.equal(verified, response);
  // A duplicated native callback cannot trigger a second verification request.
  verified = undefined;
  app.window.__social9Native.paymentResult({ id: request.id, status: 'success', response });
  assert.equal(verified, undefined);
});
test('cancelled and failed payments dismiss the web busy state without activation', () => {
  const app = setup(); let dismissed = 0, failed = 0, success = 0;
  for (const status of ['cancelled', 'failed']) {
    const payment = new app.window.Razorpay({ handler: () => success++, modal: { ondismiss: () => dismissed++ } });
    payment.on('payment.failed', () => failed++); payment.open();
    app.window.__social9Native.paymentResult({ id: app.messages.at(-1).id, status });
  }
  assert.equal(dismissed, 2); assert.equal(failed, 1); assert.equal(success, 0);
});
test('OAuth polling uses the website session and never sends credentials to native', async () => {
  const app = setup({ fetch: async () => Response.json([{ id: 1, provider: 'instagram', status: 'connected' }]) });
  app.local.set('social9_access_token', 'secret-website-session');
  app.local.set('social9_active_brand_id', '42');
  await app.window.__social9Native.beginAuth(); await settle();
  const request = app.requests.find(item => Array.isArray(item));
  assert.equal(request[0], '/service/social-accounts');
  assert.equal(request[1].headers.Authorization, 'Bearer secret-website-session');
  assert.equal(request[1].headers['X-Brand-ID'], '42');
  assert.ok(!JSON.stringify(app.messages).includes('secret-website-session'));
  app.window.__social9Native.clearAuth();
  assert.equal(app.session.get('social9_native_pending_auth'), undefined);
});
test('back handling respects an open dialog cancel handler', () => {
  const app = setup(); let closed = 0;
  app.document.querySelectorAll = () => [{ dispatchEvent: () => false, close: () => closed++ }];
  assert.equal(app.window.__social9Native.closeOverlay(), true);
  assert.equal(closed, 0);
  app.document.querySelectorAll = () => [];
  assert.equal(app.window.__social9Native.closeOverlay(), false);
});
test('a failed initial OAuth snapshot cannot falsely complete authorization', async () => {
  let count = 0;
  const app = setup({ fetch: async () => {
    if (++count === 1) throw new Error('backend starting');
    return Response.json([]);
  }});
  app.local.set('social9_access_token', 'local-test-session');
  await app.window.__social9Native.beginAuth(); await settle();
  assert.equal(app.messages.some(m => m.type === 'authFinished'), false);
  assert.equal(JSON.parse(app.session.get('social9_native_pending_auth')).baseline, '[]');
});
test('returning from browser refreshes account UI without repeated reloads', async () => {
  const app = setup({ fetch: async () => Response.json([]) });
  app.local.set('social9_access_token', 'local-test-session');
  await app.window.__social9Native.beginAuth(); await settle();
  app.window.__social9Native.resume();
  app.window.__social9Native.resume();
  assert.equal(app.requests.filter(item => item === 'reload').length, 1);
});
test('printing requests the live page rather than exporting capped HTML', () => {
  const app = setup();
  app.window.print();
  assert.equal(app.messages.at(-1).type, 'print');
  assert.equal(app.messages.at(-1).title, 'Social9');
  assert.equal(app.messages.at(-1).html, undefined);
});
test('export backpressure waits for native acknowledgement before sending more bytes', async () => {
  const app = setup({ acknowledge: false, fetch: async () => new Response(new Uint8Array(60000)) });
  const anchor = new app.Anchor(); anchor.href = 'blob:https://www.social9.io/report'; anchor.click();
  assert.equal(app.messages.at(-1).type, 'downloadPreparing');
  assert.equal(app.requests.length, 0);
  const acknowledgeLast = () => app.window.__social9Native.acknowledge({requestId: app.messages.at(-1).requestId});
  acknowledgeLast(); await settle();
  assert.equal(app.messages.at(-1).type, 'downloadStart');
  assert.equal(app.messages.filter(m => m.type === 'downloadChunk').length, 0);
  acknowledgeLast(); await settle();
  assert.equal(app.messages.filter(m => m.type === 'downloadChunk').length, 1);
  acknowledgeLast(); await settle();
  assert.equal(app.messages.filter(m => m.type === 'downloadChunk').length, 2);
  acknowledgeLast(); await settle();
  assert.equal(app.messages.at(-1).type, 'downloadFinish');
  acknowledgeLast(); await settle();
});
