/**
 * Mint a development access token, as services/api would, so the classroom can be driven
 * before the API exists:
 *
 *   pnpm --filter @tihe/live dev-token usr_01J8ZB00000000000000000001 teacher
 *
 * Uses JWT_SECRET from the environment (or services/live/.env). Never for production.
 */
import { roleSchema } from '@tihe/contracts';
import { mintDevAccessToken } from '../src/auth/access-token.js';

const [userId, role = 'student'] = process.argv.slice(2);
const secret = process.env.JWT_SECRET;
if (!userId || !secret) {
  console.error('usage: dev-token <userId> [student|teacher|admin]   (JWT_SECRET must be set)');
  process.exit(1);
}
const token = await mintDevAccessToken(secret, {
  userId,
  accountRole: roleSchema.parse(role),
  deviceId: 'dev_01J8ZB0000000000000000DEV0',
});
console.log(token);
