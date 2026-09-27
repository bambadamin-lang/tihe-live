import { defineConfig } from 'vite';

// Served by services/live at /v1/live/egress-template/, so every asset path is relative.
export default defineConfig({
  base: './',
  // livekit-client is most of the bundle; Egress loads it from the same host, so size is moot.
  build: { outDir: 'dist', emptyOutDir: true, target: 'chrome110', chunkSizeWarningLimit: 2000 },
  server: { fs: { allow: ['../../..'] } },
});
