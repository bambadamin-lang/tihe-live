import swc from 'unplugin-swc';
import { defineConfig } from 'vitest/config';

// Nest's dependency injection reads decorator metadata, which esbuild does not emit. SWC does.
export default defineConfig({
  plugins: [swc.vite({ module: { type: 'es6' } })],
  test: {
    include: ['src/**/*.test.ts', 'test/**/*.test.ts'],
    testTimeout: 15000,
  },
});
