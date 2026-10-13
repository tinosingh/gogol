import type { Plugin } from 'vite';

// SEC-5: connect-src allows only the app origin. Injected at build time only, because the
// dev server's React refresh preamble is an inline script that this policy correctly blocks.
export const CSP_POLICY =
  "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; worker-src 'self' blob:; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; form-action 'self'";

export function cspPlugin(): Plugin {
  return {
    name: 'gogol-csp',
    transformIndexHtml: {
      order: 'pre',
      handler(html, ctx) {
        if (ctx.server !== undefined) return html;
        const meta = `<meta http-equiv="Content-Security-Policy" content="${CSP_POLICY}" />`;
        return html.replace('<head>', `<head>\n    ${meta}`);
      },
    },
  };
}
