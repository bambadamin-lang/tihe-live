/**
 * Creates the first admin of a new server, or resets an admin's password.
 *
 *   pnpm --filter @tihe/api admin:create --phone 09121234567 --name "مدیر" [--password ...]
 *   node dist/cli/create-admin.js --phone ...          (inside the API container)
 *
 * Without --password a strong one is generated and printed once. Either way the admin chooses
 * their own at first sign-in. Everything after that happens in the app.
 */
import { randomInt } from 'node:crypto';
import { parseArgs } from 'node:util';

import { maskPhone, phoneSchema } from '@tihe/contracts';
import { checkPasswordPolicy, PasswordHasher } from '@tihe/crypto';
import { newId, PrismaClient } from '@tihe/db';

/** Easy to read aloud and type on a phone: no 0/O, 1/l/I. */
const ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';

export function generatePassword(length = 12): string {
  let out = '';
  for (let i = 0; i < length; i++) out += ALPHABET[randomInt(ALPHABET.length)];
  // Grouped in fours so it can be dictated: abcd-efgh-jkmn.
  return out.match(/.{1,4}/g)!.join('-');
}

async function main() {
  const { values } = parseArgs({
    options: {
      phone: { type: 'string' },
      name: { type: 'string' },
      password: { type: 'string' },
    },
  });

  const phone = phoneSchema.safeParse(values.phone ?? '');
  if (!phone.success) {
    console.error('usage: admin:create --phone 09121234567 --name "نام" [--password ...]');
    process.exit(2);
  }
  const pepper = process.env.PASSWORD_PEPPER;
  if (!pepper) {
    console.error('PASSWORD_PEPPER is not set (see infra/scripts/generate-secrets.sh)');
    process.exit(2);
  }

  const password = values.password ?? generatePassword();
  const problem = checkPasswordPolicy(password, phone.data);
  if (problem) {
    console.error(`password refused: ${problem}`);
    process.exit(2);
  }

  const prisma = new PrismaClient();
  try {
    const passwordHash = await new PasswordHasher(pepper).hash(password);
    const credentials = {
      passwordHash,
      passwordChangedAt: new Date(),
      mustChangePassword: true,
      role: 'admin' as const,
      status: 'active' as const,
    };
    const user = await prisma.user.upsert({
      where: { phone: phone.data },
      update: { ...credentials, ...(values.name ? { displayName: values.name } : {}) },
      create: {
        id: newId('user'),
        phone: phone.data,
        displayName: values.name ?? 'مدیر',
        ...credentials,
      },
    });

    console.log(`admin ready: ${maskPhone(user.phone)} (${user.id})`);
    if (!values.password) {
      // Printed once, to the operator's terminal only. It is temporary: the app asks for a new
      // one at first sign-in.
      console.log(`temporary password: ${password}`);
    }
  } finally {
    await prisma.$disconnect();
  }
}

// Only when run as a script, so the generator can be imported by its test.
if (process.argv[1] && /create-admin\.(ts|js)$/.test(process.argv[1])) {
  main().catch((error: unknown) => {
    console.error(error);
    process.exit(1);
  });
}
