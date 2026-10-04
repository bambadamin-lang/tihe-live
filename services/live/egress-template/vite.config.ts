import { fileURLToPath } from 'node:url';

import { defineConfig } from 'vite';

// Served by services/live at /v1/live/egress-template/, so every asset path is relative.
export default defineConfig({
  base: './',
  // livekit-client is most of the bundle; Egress loads it from the same host, so size is moot.
  build: { outDir: 'dist', emptyOutDir: true, target: 'chrome110', chunkSizeWarningLimit: 2000 },
  server: { fs: { allow: ['../../..'] } },
  // The contracts package publishes CommonJS, whose `export *` Rollup cannot see through, so the
  // production build failed on names re-exported from live/gateway. Bundle its sources instead.
  resolve: {
    alias: {
      '@tihe/contracts': fileURLToPath(
        new URL('../../../packages/contracts/src/index.ts', import.meta.url),
      ),
    },
  },
});
