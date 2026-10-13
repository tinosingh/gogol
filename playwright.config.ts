import { defineConfig, devices } from '@playwright/test';
import { PREVIEW_HOST, PREVIEW_PORT } from './src/config';

const baseURL = `http://${PREVIEW_HOST}:${String(PREVIEW_PORT)}`;

export default defineConfig({
  testDir: 'e2e',
  use: { baseURL },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: `npm run build && npx vite preview --strictPort --port ${String(PREVIEW_PORT)}`,
    url: baseURL,
    reuseExistingServer: false,
  },
});
