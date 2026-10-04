import swc from 'unplugin-swc';
import { defineConfig } from 'vitest/config';

// The end-to-end tests boot the whole Nest application, whose dependency injection reads decorator
// metadata. esbuild does not emit it; SWC does.
export default defineConfig({
  plugins: [swc.vite({ module: { type: 'es6' } })],
  test: {
    include: ['src/**/*.test.ts', 'test/**/*.test.ts'],
    globals: true,
    testTimeout: 30000,
    hookTimeout: 30000,
  },
});
