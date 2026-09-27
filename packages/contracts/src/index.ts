/**
 * @tihe/contracts — the shared API contract.
 *
 * Every request and response that crosses a service boundary is defined here once, as a zod
 * schema, and inferred into a TypeScript type. The API validates against these schemas at its
 * edges; the Flutter client generates its models from the OpenAPI document derived from them.
 *
 * This package is the seam between the two developers on this project. Changes require a PR —
 * see docs/09-team-workflow.md.
 */
export * from './common.js';
export * from './errors.js';

export * from './entities/user.js';
export * from './entities/catalog.js';
export * from './entities/protection.js';

export * from './endpoints/auth.js';
export * from './endpoints/catalog.js';
export * from './endpoints/progress.js';
export * from './endpoints/playback.js';
export * from './endpoints/webhooks.js';
