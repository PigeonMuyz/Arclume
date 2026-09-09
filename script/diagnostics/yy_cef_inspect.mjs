// Explicit, read-only CEF diagnostics. Never print URLs, page text, headers or credentials.
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export function listenerPorts(output) {
  const ports = new Set();
  for (const line of output.trim().split('\n').filter(Boolean)) {
    if (!line.startsWith('n')) continue;
    const match = /^n127\.0\.0\.1:(392\d\d|393[01]\d|3932[0-7])$/.exec(line);
    if (!match) throw new Error('Non-loopback inspection listener; close test YY immediately.');
    ports.add(Number(match[1]));
  }
  return [...ports];
}

const domSummary = `(() => {
  const tags = ['BUTTON', 'CANVAS', 'IFRAME', 'INPUT', 'VIDEO'];
  const center = document.elementFromPoint(innerWidth / 2, innerHeight / 2);
  const style = center ? getComputedStyle(center) : null;
  return { ready: document.readyState, visibility: document.visibilityState,
    width: innerWidth, height: innerHeight, elements: document.querySelectorAll('*').length,
    counts: Object.fromEntries(tags.map(t => [t, document.querySelectorAll(t).length])),
    centerTag: center ? (tags.includes(center.tagName) ? center.tagName : 'other') : 'none',
    centerReceivesPointer: style ? style.pointerEvents !== 'none' : false,
    centerVisible: style ? style.visibility === 'visible' && style.display !== 'none' : false,
    frames: [...document.querySelectorAll('iframe')].slice(0, 20).map(f => {
      const r = f.getBoundingClientRect(), s = getComputedStyle(f);
      let ready = 'cross-origin'; try { ready = f.contentDocument?.readyState || 'unavailable'; } catch {}
      return { width: r.width, height: r.height, x: r.x, y: r.y, visible: s.visibility === 'visible' && s.display !== 'none',
        pointer: s.pointerEvents !== 'none', zIndex: /^-?[0-9]+$/.test(s.zIndex) ? Number(s.zIndex) : 'auto', ready };
    }) };
})()`;

async function inspectTarget(target, port, index) {
  const address = new URL(target.webSocketDebuggerUrl);
  if (!['localhost', '127.0.0.1'].includes(address.hostname) || Number(address.port) !== port || address.protocol !== 'ws:')
    throw new Error('Unexpected WebSocket address.');
  address.hostname = '127.0.0.1';
  const ws = new WebSocket(address);
  const pending = new Map();
  const stats = { errors: {}, logLevels: {}, logKinds: {}, network: { started: 0, finished: 0, failed: 0, status: {}, failures: {} } };
  const requests = new Set();
  let nextId = 0;
  const increment = (obj, key) => { obj[key] = (obj[key] || 0) + 1; };
  ws.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id) { pending.get(message.id)?.(message); return; }
    const p = message.params || {};
    if (message.method === 'Runtime.exceptionThrown') {
      const kind = p.exceptionDetails?.exception?.className;
      increment(stats.errors, ['TypeError', 'ReferenceError', 'SyntaxError', 'RangeError', 'Error'].includes(kind) ? kind : 'other');
    } else if (message.method === 'Log.entryAdded') {
      const level = p.entry?.level;
      increment(stats.logLevels, ['verbose', 'info', 'warning', 'error'].includes(level) ? level : 'other');
      const raw = p.entry?.text || '';
      const kind = ['ERR_', 'WebSocket', 'CORS', 'Content Security Policy', 'Mixed Content', 'Permission', 'WebGL', 'deprecated', 'Failed to load resource']
        .find(token => raw.includes(token)) || 'other';
      increment(stats.logKinds, kind);
    } else if (message.method === 'Network.requestWillBeSent') {
      stats.network.started++; requests.add(p.requestId);
    } else if (message.method === 'Network.responseReceived') {
      const status = p.response?.status;
      if (Number.isInteger(status)) increment(stats.network.status, status);
    } else if (message.method === 'Network.loadingFinished') {
      stats.network.finished++; requests.delete(p.requestId);
    } else if (message.method === 'Network.loadingFailed') {
      stats.network.failed++; requests.delete(p.requestId);
      increment(stats.network.failures, /^net::ERR_[A-Z_]+$/.test(p.errorText || '') ? p.errorText : 'other');
    }
  });
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('connect-timeout')), 3000);
      ws.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
      ws.addEventListener('error', () => { clearTimeout(timer); reject(new Error('connect-error')); }, { once: true });
    });
    const send = (method, params = {}) => new Promise(resolve => {
      const id = ++nextId;
      const timer = setTimeout(() => { pending.delete(id); resolve({ timeout: true }); }, 5000);
      pending.set(id, result => { clearTimeout(timer); pending.delete(id); resolve(result); });
      ws.send(JSON.stringify({ id, method, params }));
    });
    const enabled = await Promise.all(['Runtime.enable', 'Log.enable', 'Network.enable'].map(method => send(method)));
    const summary = await send('Runtime.evaluate', { expression: domSummary, returnByValue: true, timeout: 3000 });
    console.log(JSON.stringify({ port, target: index, enabled: enabled.map(x => !x.error && !x.timeout),
      evaluation: summary.timeout ? 'timeout' : summary.error || summary.result?.exceptionDetails ? 'error' : 'ok',
      dom: summary.result?.result?.value }));
    if (process.argv.includes('--capture-channel') && summary.result?.result?.value?.width >= 800) {
      const shot = await send('Page.captureScreenshot', { format: 'png' });
      if (shot.result?.data) {
        const folder = mkdtempSync(join(tmpdir(), 'arclume-yy-cef-paint.'));
        const path = join(folder, 'channel.png');
        writeFileSync(path, Buffer.from(shot.result.data, 'base64'), { mode: 0o600 });
        console.log(JSON.stringify({ port, target: index, screenshot: path }));
      } else console.log(JSON.stringify({ port, target: index, screenshot: shot.timeout ? 'timeout' : 'failed' }));
    }
    await new Promise(resolve => setTimeout(resolve, 10000));
    console.log(JSON.stringify({ port, target: index, ...stats, pendingSinceAttach: requests.size }));
  } finally { ws.close(); }
}

async function main() {
  let output;
  try { output = execFileSync('/usr/sbin/lsof', ['-nP', '-iTCP:39200-39327', '-sTCP:LISTEN', '-Fn'], { encoding: 'utf8' }); }
  catch (error) { if (error.status === 1 && !error.stdout?.length) { console.log('No inspection listener.'); return; } throw error; }
  const ports = listenerPorts(output);
  for (const port of ports) {
    const response = await fetch(`http://127.0.0.1:${port}/json/list`, { signal: AbortSignal.timeout(3000) });
    const targets = await response.json();
    const pages = targets.filter(t => t.type === 'page' && t.webSocketDebuggerUrl).slice(0, 16);
    console.log(JSON.stringify({ port, pages: pages.length }));
    await Promise.all(pages.map((target, index) => inspectTarget(target, port, index)));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => { console.error('Inspection failed; raw error suppressed to protect page data.'); process.exitCode = 1; });
}
