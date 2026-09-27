import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts', 'test/**/*.test.ts'],
    // ffmpeg runs are slow; a real transcode in a test needs more than the 5s default.
    testTimeout: 120_000,
  },
});
