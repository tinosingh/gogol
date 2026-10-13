import { describe, expect, it } from 'vitest';
import { CSP_POLICY, cspPlugin } from './csp.ts';

const SHELL =
  '<html><head></head><body><script type="module" src="/src/main.tsx"></script></body></html>';

type Handler = (html: string, ctx: { server?: object }) => string;
const handler = cspPlugin().transformIndexHtml as { handler: Handler };

describe('CSP injection', () => {
  it('injects the meta before any script in a build', () => {
    const out = handler.handler(SHELL, {});
    const metaAt = out.indexOf('Content-Security-Policy');
    expect(metaAt).toBeGreaterThan(-1);
    expect(metaAt).toBeLessThan(out.indexOf('<script'));
  });

  it('leaves the dev server page untouched', () => {
    expect(handler.handler(SHELL, { server: {} })).toBe(SHELL);
  });

  it('allows only wasm-unsafe-eval and no unsafe script policy', () => {
    expect(CSP_POLICY).toContain("script-src 'self' 'wasm-unsafe-eval'");
    expect(CSP_POLICY).not.toContain("'unsafe-inline'");
    expect(CSP_POLICY).not.toContain("'unsafe-eval'");
  });

  it('restricts connections to the app origin', () => {
    expect(CSP_POLICY).toContain("connect-src 'self'");
    expect(CSP_POLICY).toContain("default-src 'self'");
  });
});
