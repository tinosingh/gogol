import workerUrl from './spike.worker.ts?worker&url';
// Relative path: the package exports map hides dist/sqlite3.wasm from a bare import. Spike only.
import sqliteWasmUrl from '../../node_modules/@sqlite.org/sqlite-wasm/dist/sqlite3.wasm?url';

declare global {
  interface Window {
    spike: { send: (op: string) => Promise<unknown> };
  }
}

const output = document.getElementById('result');

function show(data: unknown): void {
  if (output === null) throw new Error('Missing #result element');
  output.textContent = JSON.stringify(data);
  output.dataset.state = 'done';
}

const mode = new URLSearchParams(location.search).get('mode');
const wasmUrl = new URL(sqliteWasmUrl, location.href).href;

if (mode === 'blob') {
  // Blob worker, eval probe only: does a blob worker inherit the page CSP?
  const probe =
    "let inherited; try { (0, eval)('1'); inherited = false; } catch { inherited = true; } self.postMessage({ mode: 'blob', cspInherited: inherited });";
  const worker = new Worker(
    URL.createObjectURL(new Blob([probe], { type: 'text/javascript' })),
  );
  worker.onmessage = (event: MessageEvent<unknown>) => {
    show(event.data);
  };
} else if (mode === 'blobdb') {
  // Database worker started from a blob URL. Its bundled source is fetched and wrapped in a blob.
  const source = await (await fetch(workerUrl)).text();
  const worker = new Worker(
    URL.createObjectURL(new Blob([source], { type: 'text/javascript' })),
    {
      type: 'module',
    },
  );
  const waiting: ((data: unknown) => void)[] = [];
  worker.onmessage = (event: MessageEvent<unknown>) => {
    show(event.data);
    waiting.shift()?.(event.data);
  };
  window.spike = {
    send: (op: string) =>
      new Promise((resolve) => {
        waiting.push(resolve);
        worker.postMessage({ op, wasmUrl });
      }),
  };
  worker.postMessage({ op: 'run', wasmUrl });
} else {
  const worker = new Worker(new URL('./spike.worker.ts', import.meta.url), {
    type: 'module',
  });
  const waiting: ((data: unknown) => void)[] = [];
  worker.onmessage = (event: MessageEvent<unknown>) => {
    show(event.data);
    waiting.shift()?.(event.data);
  };
  window.spike = {
    send: (op: string) =>
      new Promise((resolve) => {
        waiting.push(resolve);
        worker.postMessage({ op });
      }),
  };
  worker.postMessage({ op: 'run' });
}
