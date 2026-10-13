# ADR 1: Hosting, origin and OPFS VFS

- **Status:** Proposed. Decides the VFS and the tab model. Does not decide D3 (deployment host and domain), which stays open in [PRD §8](../prd.md).
- **Requirements:** NFR-5, NFR-2, NFR-3, SEC-5, DAT-1, DAT-4, D3.
- **Related:** [ADR 2](adr-02-encryption-vfs.md) (persistence path), [ADR 4](adr-04-durability.md) (durability).

## Context

gogol is static files with no backend (NFR-5). The database runs in a dedicated worker and persists to OPFS through a SQLite VFS. Three constraints matter:

1. **Headers.** The `opfs` VFS and its Web Locks variant `opfs-wl` (SQLite 3.53+) need `SharedArrayBuffer`, which needs cross-origin isolation (COOP and COEP headers). GitHub Pages cannot send custom headers, and a `<meta>` tag cannot set COOP or COEP. The `opfs-sahpool` VFS needs neither (PROMPT.md, hard problem 1).
2. **Connections.** `opfs-sahpool` allows one connection. A second tab cannot open the database until the first releases it with `pauseVfs()` (SQLite 3.50+).
3. **Origin.** OPFS data, Web Locks and passkey scope (RP ID) belong to the origin. All GitHub Pages project sites of one account share `<user>.github.io`, so every other project site of that account can read the same OPFS storage. A later origin change strands the data and the passkeys (PROMPT.md, hard problem 1).

## Options considered

**VFS**

| Option                                                                | Headers                | Tabs                       | Notes                                                                                                                                       |
| --------------------------------------------------------------------- | ---------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `opfs`                                                                | COOP and COEP required | Multiple connections       | Not deployable on GitHub Pages without a workaround.                                                                                        |
| `opfs-wl` (SQLite 3.53+)                                              | COOP and COEP required | Web Locks serialize access | Same header problem.                                                                                                                        |
| `opfs-sahpool`                                                        | None                   | One connection             | Works on any static host. Single-tab rule needs an explicit design.                                                                         |
| Service-worker header injection (e.g. a coi-serviceworker-style shim) | Simulated              | As `opfs`                  | Adds a third-party script to the supply chain and a second caching layer that can serve stale code. Rejected (SEC standards, supply chain). |

**Origin**

| Option                                                           | Verdict                                                                                                                                                                                                             |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `<user>.github.io/gogol` (project site)                          | Rejected. OPFS and passkeys are shared with every other site of the same account.                                                                                                                                   |
| Custom domain on GitHub Pages, own origin, no header control     | Preferred. Origin isolated; CSP by `<meta>` (see [security.md](../security.md)). Needs a domain the project keeps paying for.                                                                                       |
| Static host with header control (e.g. Cloudflare Pages, Netlify) | Viable: could send COOP/COEP and a real CSP. Still needs the custom domain. Vendor-specific header configuration would make the build less portable. Kept as the fallback if the `<meta>` approach fails the spike. |

**Tab model (single database connection)**

- _Refuse the second tab with a message._ Simple, but a user who reloads from a crashed tab is stuck until the old tab is gone.
- _Owner tab with a takeover._ The owner holds a Web Lock named for the database (`navigator.locks.request`). A second tab sees the lock is held, shows a read-only "open in another tab" state with a "use this tab" action, and requests the lock when the user chooses. The owner closes its connection on `pagehide` and releases the lock. **Chosen.**
- _Second connection over `opfs`._ Rejected with the VFS above.

## Decision

1. **VFS: `opfs-sahpool`** in the official `@sqlite.org/sqlite-wasm` build (or the cipher build from ADR 2, if its spike passes on this VFS). No COOP or COEP headers are needed, so the app does not depend on `SharedArrayBuffer`.
2. **One connection per origin, enforced by a Web Lock** named by config (never a literal in code). The owner tab opens the database. Another tab shows the read-only state and can take over on user request. Takeover closes the owner's connection first, so the lock is never held by two tabs at once.
3. **Origin:** the app is served from an origin of its own. Recommended: a custom domain the owner controls, on GitHub Pages or on a header-capable host. **D3 is not decided here.** The owner chooses the domain and the host. **Prefer a header-capable host** (e.g. Cloudflare Pages, Netlify): it can set `Content-Security-Policy: frame-ancestors 'none'` and `X-Frame-Options: DENY` as HTTP headers. `<meta>` CSP cannot set `frame-ancestors`, so the app is frameable on a header-incapable host. With File System Access (Chromium), a framed app exposes the backup flow to multi-step clickjacking. If the chosen host cannot send headers, document this residual in security.md and add a UI prompt requiring an explicit user gesture before `showSaveFilePicker`.
4. **Domain change path:** a full backup (DAT-1) must restore into a new origin. Passkey slots are re-enrolled on the new origin (ADR 2). The UI shows the domain-change path in the backup screen. The ADR records that a change of domain strands OPFS data and passkeys, so it is a costly change.
5. **Spike (Phase 0, gate):** prove `opfs-sahpool` with the migration runner, `pauseVfs()` takeover between two tabs, and persistence after reload, in Chromium (Playwright, NFR-3).

## Consequences

- No header dependency: the app deploys to any static host and passes NFR-5 with `<meta>`-delivered CSP.
- The single-connection rule limits the app to one tab for writes. This matches the PRD constraint "one user works on an entity's books at a time" (PRD §6).
- Takeover depends on the owner releasing the lock. A crashed tab releases its lock when it dies, so this does not block the user.
- Domain cost and lock-in: the custom domain becomes part of the security model (origin isolation, passkey RP ID). Changing it later costs a backup-and-restore cycle for each user.
- Open risk: the spike must show that `pauseVfs()` and re-open work in all three engines. If it fails in one engine, that engine gets a read-only mode and the matrix in [architecture.md](../architecture.md) is updated.

## Spike results (Phase 0, Chromium, 2026-10-13)

- **Persistence through reload: passed.** `opfs-sahpool` in the official build wrote a row, the page reloaded, and the row was still there (`e2e/spike.spec.ts`). The database opened with `foreign_keys`, `defensive` and `trusted_schema` set.
- **Worker CSP: failed for a same-origin worker.** A worker loaded from the app's own file did not inherit the page's CSP: `eval` ran inside it. security.md §5 therefore still needs the blob-URL worker or a header-capable host. This spike does not yet test the blob-URL option.
- **Not yet tested:** `pauseVfs()` takeover between two tabs, and Firefox/Safari (out of scope, PRD NFR-3).

### Results 2 (Chromium, 2026-10-13)

- **Single connection across tabs: passed.** A second tab cannot open the sahpool database while the first holds it. After the first tab calls `pauseVfs()` and closes its connection, the second tab opens the same database and writes (`e2e/spike.spec.ts`).
- **Blob worker CSP: passed for a probe.** A worker created from a blob URL inherits the page CSP: `eval` is blocked. This is measured with a probe worker only. The database worker itself has not run from a blob URL, because `sqlite3InitModule()` takes no argument to locate `sqlite3.wasm`. That is the next spike.

### Results 3 (Chromium, 2026-10-13)

- **Database worker from a blob URL: passed.** The bundled worker source was fetched, wrapped in a blob, and run as a module worker. It opened the `opfs-sahpool` database, wrote a row, and reported that its eval probe was blocked, so it inherits the page CSP (`e2e/spike.spec.ts`).
- **How it works:** the published `sqlite3InitModule()` type takes no argument, but the runtime accepts `locateFile`. The worker passes the absolute WASM URL from the page. This relies on an undocumented runtime option, so it needs a re-check on every SQLite-WASM upgrade.
