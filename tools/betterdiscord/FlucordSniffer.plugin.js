/**
 * @name Flucord Sniffer
 * @author nevermore
 * @description Logs voice and stream WebSocket frames (ops, DAVE MLS flow) to the DevTools console. Start it, join voice or go live, then run __flucordDump() in the console and paste the result.
 * @version 1.0.0
 * @source https://github.com/redstone-md/flucord
 */

module.exports = (() => {
  const PREFIX = '[flucord-sniff]';
  const MAX_STRING = 96;

  const state = {
    log: [],
    t0: 0,
    origWebSocket: null,
    origSend: null,
    sockets: new WeakSet(),
  };

  function elapsed() {
    return ((performance.now() - state.t0) / 1000).toFixed(3).padStart(9);
  }

  function record(line) {
    state.log.push(`${elapsed()} ${line}`);
    if (state.log.length > 5000) state.log.shift();
    console.log(PREFIX, line);
  }

  function summarize(value, depth = 0) {
    if (value === null) return 'null';
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    if (typeof value === 'string') {
      return value.length > MAX_STRING
        ? `${value.slice(0, 48)}…(+${value.length - 48})`
        : value;
    }
    if (Array.isArray(value)) {
      if (depth > 1) return `[${value.length}]`;
      return `[${value.map((item) => summarize(item, depth + 1)).join(', ')}]`;
    }
    if (typeof value === 'object') {
      if (depth > 1) return '{…}';
      const entries = Object.entries(value).map(([key, inner]) => {
        if (key === 'token') return 'token: …';
        return `${key}: ${summarize(inner, depth + 1)}`;
      });
      return `{${entries.join(', ')}}`;
    }
    return String(value);
  }

  function onTextFrame(direction, data, url) {
    let parsed;
    try {
      parsed = JSON.parse(data);
    } catch {
      record(`${direction} ${url} text ${data.length}b (not json)`);
      return;
    }
    const kind = url.includes('discord.media') ? 'voice' : 'gateway';
    const op = parsed.op;
    const seq = parsed.seq !== undefined ? ` seq=${parsed.seq}` : '';
    const summary = parsed.d !== undefined ? ` ${summarize(parsed.d, 0)}` : '';
    record(`${direction} ${kind} op=${op}${seq}${summary}`);
  }

  function onBinaryFrame(direction, data, url) {
    let bytes = null;
    if (data instanceof ArrayBuffer) bytes = new Uint8Array(data);
    else if (ArrayBuffer.isView(data)) bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    else if (data instanceof Blob) {
      record(`${direction} voice bin blob ${data.size}b`);
      return;
    }
    if (!bytes || bytes.length < 3) {
      record(`${direction} voice bin ${bytes ? bytes.length : '?'}b (short)`);
      return;
    }
    const seq = (bytes[0] << 8) | bytes[1];
    const op = bytes[2];
    const transition = bytes.length >= 5 ? (bytes[3] << 8) | bytes[4] : null;
    const head = Array.from(bytes.slice(3, 19))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
    record(
      `${direction} voice bin op=${op} seq=${seq} len=${bytes.length}` +
        (transition !== null ? ` trans=${transition}` : '') +
        ` head=${head}`
    );
  }

  function hookSocket(ws, url) {
    if (!url || !/discord\.(com|gg|media)/.test(url)) return;
    if (state.sockets.has(ws)) return;
    state.sockets.add(ws);
    const short = url.includes('discord.media')
      ? `media:${new URL(url).host.split('.')[0]}`
      : 'gateway';
    record(`open ${short} ${url}`);

    ws.addEventListener('message', (event) => {
      try {
        if (typeof event.data === 'string') onTextFrame('recv', event.data, url);
        else onBinaryFrame('recv', event.data, url);
      } catch (error) {
        record(`recv ${short} handler error ${error}`);
      }
    });
    ws.addEventListener('close', (event) => {
      record(`close ${short} code=${event.code}`);
    });
  }

  function patchSend(ws) {
    const socket = ws;
    if (socket.__flucordPatched || typeof socket.send !== 'function') return;
    const origSend = socket.send.bind(socket);
    socket.send = (data) => {
      try {
        const url = socket.__flucordUrl || socket.url || '';
        if (typeof data === 'string') onTextFrame('send', data, url);
        else onBinaryFrame('send', data, url);
      } catch (error) {
        record(`send handler error ${error}`);
      }
      return origSend(data);
    };
    socket.__flucordPatched = true;
  }

  return {
    start() {
      state.t0 = performance.now();
      state.log = [];
      window.__flucordLog = state.log;
      window.__flucordClear = () => {
        state.log = [];
        return 'cleared';
      };
      // The dump lands in the clipboard: DevTools consoles truncate long
      // copies, and a 30-second go-live capture is thousands of lines.
      window.__flucordDump = () => {
        const text = state.log.join('\n');
        try {
          window.DiscordNative.clipboard.copy(text);
          return `copied ${state.log.length} lines to the clipboard`;
        } catch {
          return text;
        }
      };

      state.origWebSocket = window.WebSocket;
      const Orig = state.origWebSocket;
      function PatchedWebSocket(url, protocols) {
        const ws = protocols === undefined ? new Orig(url) : new Orig(url, protocols);
        try {
          ws.__flucordUrl = String(url);
          hookSocket(ws, String(url));
          patchSend(ws);
        } catch (error) {
          record(`hook error ${error}`);
        }
        return ws;
      }
      PatchedWebSocket.prototype = Orig.prototype;
      PatchedWebSocket.CONNECTING = Orig.CONNECTING;
      PatchedWebSocket.OPEN = Orig.OPEN;
      PatchedWebSocket.CLOSING = Orig.CLOSING;
      PatchedWebSocket.CLOSED = Orig.CLOSED;
      window.WebSocket = PatchedWebSocket;

      // Sockets that already exist (the main gateway opened before plugins
      // load) still get their sends captured through the prototype.
      state.origSend = WebSocket.prototype.send;
      WebSocket.prototype.send = function (data) {
        if (!this.__flucordPatched) {
          try {
            hookSocket(this, this.__flucordUrl || this.url);
            patchSend(this);
          } catch (error) {
            record(`late hook error ${error}`);
          }
        }
        if (this.__flucordPatched) return this.send(data);
        try {
          const url = this.__flucordUrl || this.url || '';
          if (typeof data === 'string') onTextFrame('send', data, url);
          else onBinaryFrame('send', data, url);
        } catch (error) {
          record(`send handler error ${error}`);
        }
        return state.origSend.call(this, data);
      };

      record('sniffer started; join voice or start a stream, then __flucordDump()');
    },
    stop() {
      if (state.origWebSocket) window.WebSocket = state.origWebSocket;
      if (state.origSend) WebSocket.prototype.send = state.origSend;
      record('sniffer stopped');
    },
  };
})();
