import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { cspPlugin } from './src/security/csp.ts';

export default defineConfig({
  plugins: [react(), cspPlugin()],
  test: {
    include: ['src/**/*.test.ts'],
  },
  build: {
    rollupOptions: {
      input: {
        main: 'index.html',
        spike: 'spike.html',
      },
    },
  },
});
