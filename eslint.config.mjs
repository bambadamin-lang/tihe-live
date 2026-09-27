import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';

export default tseslint.config(
  {
    ignores: [
      '**/dist/**',
      '**/build/**',
      '**/target/**',
      '**/node_modules/**',
      '**/coverage/**',
      '**/*.generated.ts',
      'apps/player/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  prettier,
  {
    rules: {
      // Never silently swallow a key, a token or an error.
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-floating-promises': 'off',
      'no-console': 'off',
      eqeqeq: ['error', 'always'],
      'prefer-const': 'error',
    },
  },
);
