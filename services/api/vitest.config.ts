import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    // Decorator metadata is not needed for the unit tests here, which target pure logic
    // (OTP policy, licence validity, watermark derivation) rather than wired-up Nest modules.
    globals: true,
  },
});
