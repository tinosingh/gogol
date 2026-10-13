/// <reference lib="webworker" />
import sqlite3InitModule, {
  type OpfsSAHPoolDatabase,
  type SAHPoolUtil,
} from '@sqlite.org/sqlite-wasm';
import { DB_FILE } from '../config.ts';

// Spike only (ADR 1 gate). Replaced by the real worker in Phase 1.
interface Request {
  op: string;
  wasmUrl?: string;
}
interface Opened {
  pool: SAHPoolUtil;
  db: OpfsSAHPoolDatabase;
}
let opened: Promise<Opened> | undefined;

// The published type takes no argument, but the runtime reads locateFile (needed in a blob worker,
// where the default location of sqlite3.wasm cannot be resolved).
type InitWithLocate = (moduleArg?: {
  locateFile: () => string;
}) => ReturnType<typeof sqlite3InitModule>;

async function openDatabase(wasmUrl: string | undefined): Promise<Opened> {
  const init: InitWithLocate = sqlite3InitModule;
  const sqlite3 = await (wasmUrl === undefined
    ? init()
    : init({ locateFile: () => wasmUrl }));
  const pool = await sqlite3.installOpfsSAHPoolVfs({});
  const db = new pool.OpfsSAHPoolDb(DB_FILE);
  db.exec(
    'PRAGMA foreign_keys = ON; PRAGMA defensive = ON; PRAGMA trusted_schema = OFF;',
  );
  db.exec(
    'CREATE TABLE IF NOT EXISTS spike (id INTEGER PRIMARY KEY, note TEXT NOT NULL) STRICT;',
  );
  return { pool, db };
}

function ensureOpen(wasmUrl: string | undefined): Promise<Opened> {
  opened ??= openDatabase(wasmUrl).catch((error: unknown) => {
    opened = undefined;
    throw error;
  });
  return opened;
}

function cspInherited(): boolean {
  try {
    // eval is blocked only where the page CSP applies (no 'unsafe-eval' in script-src).
    (0, eval)('1');
    return false;
  } catch {
    return true;
  }
}

self.onmessage = (event: MessageEvent<Request>) => {
  const { op, wasmUrl } = event.data;
  void (async () => {
    try {
      if (op === 'pause') {
        const { pool, db } = await ensureOpen(wasmUrl);
        db.close();
        pool.pauseVfs();
        opened = undefined;
        self.postMessage({ op, paused: true });
        return;
      }
      const { db } = await ensureOpen(wasmUrl);
      db.exec({ sql: 'INSERT INTO spike (note) VALUES (?)', bind: ['load'] });
      const count = db.selectValue('SELECT count(*) FROM spike');
      self.postMessage({ op, count, cspInherited: cspInherited() });
    } catch (error) {
      self.postMessage({
        op,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  })();
};
