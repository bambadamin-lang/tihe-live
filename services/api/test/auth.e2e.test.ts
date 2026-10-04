import { generateKeyPairSync, randomBytes } from 'node:crypto';
import type { AddressInfo } from 'node:net';

import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import {
  ACCESS_TOKEN_AUDIENCE,
  ACCESS_TOKEN_ISSUER,
  accessTokenClaimsSchema,
  authSessionSchema,
  deviceLimitDetailsSchema,
  directoryCourseSchema,
  directoryProfileSchema,
  directoryUserCoursesSchema,
  errorResponseSchema,
  type AuthSession,
  type DeviceIdentity,
  type DeviceLimitDetails,
} from '@tihe/contracts';
import { PasswordHasher } from '@tihe/crypto';
import { newId, PrismaClient } from '@tihe/db';
import { jwtVerify } from 'jose';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

/**
 * Phone + password sign-in, devices signed in at once, the admin endpoints and the internal
 * directory, over HTTP against a real Postgres (ADR-0013, ADR-0014).
 *
 * Needs DATABASE_URL with migrations applied; skipped without it, like the other database tests.
 */
const hasDatabase = Boolean(process.env.DATABASE_URL);

const JWT_SECRET = randomBytes(48).toString('base64');
const PEPPER = randomBytes(32).toString('base64');
const INTERNAL_TOKEN = randomBytes(48).toString('base64');

if (hasDatabase) {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  Object.assign(process.env, {
    NODE_ENV: 'test',
    KEK_BASE64: randomBytes(32).toString('base64'),
    LICENSE_PRIVATE_KEY_BASE64: privateKey
      .export({ type: 'pkcs8', format: 'der' })
      .toString('base64'),
    LICENSE_PUBLIC_KEY_BASE64: publicKey.export({ type: 'spki', format: 'der' }).toString('base64'),
    JWT_SECRET,
    PASSWORD_PEPPER: PEPPER,
    INTERNAL_API_TOKEN: INTERNAL_TOKEN,
    S3_ENDPOINT: process.env.S3_ENDPOINT ?? 'http://localhost:9000',
    S3_ACCESS_KEY: process.env.S3_ACCESS_KEY ?? 'tihe_minio',
    S3_SECRET_KEY: process.env.S3_SECRET_KEY ?? 'tihe_minio_dev_password',
    // Small per-number limit to test it quickly; a large per-address one, because every test
    // here signs in from 127.0.0.1.
    LOGIN_MAX_FAILURES_PER_PHONE: '3',
    LOGIN_MAX_FAILURES_PER_IP: '1000',
    DEFAULT_MAX_DEVICES: '2',
    LIVEKIT_WEBHOOK_ALLOW_UNSIGNED: 'false',
  });
}

const prisma = hasDatabase ? new PrismaClient() : null;
let app: INestApplication;
let base = '';

const PASSWORD = 'correct-horse-battery';
const run = randomBytes(3).readUIntBE(0, 3).toString().padStart(7, '0');
/** A phone number unique to this run, so repeated runs on one database never collide. */
const phone = (n: number) => `0912${String((Number(run) + n) % 10_000_000).padStart(7, '0')}`;

let admin: { id: string; phone: string };
let student: { id: string; phone: string };
let courseId: string;

function device(name: string): DeviceIdentity {
  return {
    fingerprint: `fp-${name}-${run}-${'x'.repeat(16)}`,
    platform: 'windows',
    name,
    publicKey: randomBytes(32).toString('base64'),
  };
}

async function call(
  method: string,
  path: string,
  opts: { token?: string; body?: unknown; headers?: Record<string, string> } = {},
): Promise<{ status: number; body: any }> {
  const res = await fetch(`${base}/v1${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(opts.token ? { authorization: `Bearer ${opts.token}` } : {}),
      ...opts.headers,
    },
    ...(opts.body !== undefined ? { body: JSON.stringify(opts.body) } : {}),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

async function login(phoneLocal: string, password: string, dev: DeviceIdentity) {
  return call('POST', '/auth/login', { body: { phone: phoneLocal, password, device: dev } });
}

async function signIn(phoneLocal: string, dev: DeviceIdentity): Promise<AuthSession> {
  const res = await login(phoneLocal, PASSWORD, dev);
  expect(res.status, JSON.stringify(res.body)).toBe(200);
  return authSessionSchema.parse(res.body);
}

function errorCode(res: { body: any }): string {
  return errorResponseSchema.parse(res.body).error.code;
}

async function makeUser(n: number, role: 'student' | 'admin', extra: object = {}) {
  const hash = await new PasswordHasher(PEPPER).hash(PASSWORD);
  const local = phone(n);
  return prisma!.user.create({
    data: {
      id: newId('user'),
      phone: `+98${local.slice(1)}`,
      displayName: `${role} ${n}`,
      role,
      passwordHash: hash,
      ...extra,
    },
  });
}

describe.skipIf(!hasDatabase)('sign-in, device limit, admin and directory', () => {
  let adminToken = '';

  beforeAll(async () => {
    const { AppModule } = await import('../src/app.module.js');
    const { ErrorFilter } = await import('../src/common/error.filter.js');
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication({ logger: false });
    app.setGlobalPrefix('v1');
    app.useGlobalFilters(new ErrorFilter());
    await app.listen(0, '127.0.0.1');
    base = `http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}`;

    // The institute default starts at the environment's value.
    await prisma!.setting.deleteMany({ where: { key: 'default_max_devices' } });

    const a = await makeUser(1, 'admin');
    admin = { id: a.id, phone: phone(1) };
    const s = await makeUser(2, 'student');
    student = { id: s.id, phone: phone(2) };

    courseId = newId('course');
    await prisma!.course.create({
      data: { id: courseId, title: 'درس آزمایشی', slug: `test-${run}`, status: 'published' },
    });
    await prisma!.enrollment.create({
      data: { id: newId('enrollment'), userId: student.id, courseId },
    });

    adminToken = (await signIn(admin.phone, device('admin-pc'))).tokens.accessToken;
  });

  afterAll(async () => {
    await prisma?.setting.deleteMany({ where: { key: 'default_max_devices' } });
    await app?.close();
    await prisma?.$disconnect();
  });

  describe('sign-in', () => {
    it('signs in with the right password, in any form of the number', async () => {
      const persian = student.phone.replace(/\d/g, (d) => String.fromCharCode(0x06f0 + Number(d)));
      const session = await signIn(persian, device('phone-form'));
      expect(session.user.id).toBe(student.id);
      expect(session.user.phoneMasked).toMatch(/^0912•••\d{4}$/);
      expect(session.device.signedIn).toBe(true);
      await call('POST', '/auth/logout', { token: session.tokens.accessToken });
    });

    it('answers a wrong password and an unknown number identically', async () => {
      const wrong = await login(student.phone, 'not-the-password', device('w'));
      const unknown = await login(phone(9_000_001), 'not-the-password', device('w'));
      expect(wrong.status).toBe(401);
      expect(unknown.status).toBe(401);
      expect(errorCode(wrong)).toBe('INVALID_CREDENTIALS');
      expect(errorCode(unknown)).toBe('INVALID_CREDENTIALS');
      expect(wrong.body.error.messageFa).toBe(unknown.body.error.messageFa);
    });

    it('issues access tokens services/live accepts', async () => {
      const session = await signIn(student.phone, device('live-check'));
      // Exactly what services/live's Hs256AccessTokenVerifier does with the shared secret.
      const { payload } = await jwtVerify(
        session.tokens.accessToken,
        new TextEncoder().encode(JWT_SECRET),
        { algorithms: ['HS256'], issuer: ACCESS_TOKEN_ISSUER, audience: ACCESS_TOKEN_AUDIENCE },
      );
      const claims = accessTokenClaimsSchema.parse(payload);
      expect(claims.sub).toBe(student.id);
      expect(claims.role).toBe('student');
      expect(claims.did).toBe(session.device.id);
      await call('POST', '/auth/logout', { token: session.tokens.accessToken });
    });

    it('rate-limits failures per number and says how long to wait', async () => {
      const victim = await makeUser(3, 'student');
      const local = phone(3);
      for (let i = 0; i < 3; i++) {
        expect((await login(local, `wrong-${i}`, device('rl'))).status).toBe(401);
      }
      // Even the right password is refused while the number is locked.
      const locked = await login(local, PASSWORD, device('rl'));
      expect(locked.status).toBe(429);
      expect(errorCode(locked)).toBe('LOGIN_RATE_LIMITED');
      expect(locked.body.error.details.retryAfterSeconds).toBeGreaterThan(800);
      expect(victim.id).toMatch(/^usr_/);
    });

    it('refuses a suspended account with its own message', async () => {
      await makeUser(4, 'student', { status: 'suspended' });
      const res = await login(phone(4), PASSWORD, device('susp'));
      expect(res.status).toBe(403);
      expect(errorCode(res)).toBe('ACCOUNT_SUSPENDED');
    });
  });

  describe('devices signed in at once', () => {
    it('refuses one over the limit, lists the others, and lets the student sign one out', async () => {
      const user = await makeUser(10, 'student');
      const local = phone(10);
      const a = await signIn(local, device('A'));
      const b = await signIn(local, device('B'));

      const refused = await login(local, PASSWORD, device('C'));
      expect(refused.status).toBe(409);
      expect(errorCode(refused)).toBe('DEVICE_LIMIT_REACHED');
      const details: DeviceLimitDetails = deviceLimitDetailsSchema.parse(
        refused.body.error.details,
      );
      expect(details.limit).toBe(2);
      expect(details.devices.map((d) => d.id).sort()).toEqual([a.device.id, b.device.id].sort());

      const replaced = await call('POST', '/auth/login/replace', {
        body: { ticket: details.ticket, signOutDeviceId: a.device.id, device: device('C') },
      });
      expect(replaced.status, JSON.stringify(replaced.body)).toBe(200);
      const c = authSessionSchema.parse(replaced.body);
      expect(c.user.id).toBe(user.id);

      // A's tokens stop working at once, not when they expire.
      const me = await call('GET', '/auth/me', { token: a.tokens.accessToken });
      expect(me.status).toBe(401);
      expect(errorCode(me)).toBe('DEVICE_SIGNED_OUT');
      const refresh = await call('POST', '/auth/refresh', {
        body: { refreshToken: a.tokens.refreshToken },
      });
      expect(refresh.status).toBe(401);
      expect(errorCode(refresh)).toBe('DEVICE_SIGNED_OUT');

      // B was never touched.
      expect((await call('GET', '/auth/me', { token: b.tokens.accessToken })).status).toBe(200);
    });

    it('lets a signed-in device sign in again without a free slot', async () => {
      const local = phone(11);
      await makeUser(11, 'student');
      await signIn(local, device('A'));
      await signIn(local, device('B'));
      // B again: replaces its own session, does not need a third slot.
      const again = await signIn(local, device('B'));
      expect(again.device.signedIn).toBe(true);
    });

    it('frees the slot on sign-out', async () => {
      const local = phone(12);
      await makeUser(12, 'student');
      const a = await signIn(local, device('A'));
      await signIn(local, device('B'));
      expect((await login(local, PASSWORD, device('C'))).status).toBe(409);

      expect((await call('POST', '/auth/logout', { token: a.tokens.accessToken })).status).toBe(
        204,
      );
      await signIn(local, device('C'));
    });

    it('binds the ticket to the device that asked', async () => {
      const local = phone(13);
      await makeUser(13, 'student');
      const a = await signIn(local, device('A'));
      await signIn(local, device('B'));
      const refused = await login(local, PASSWORD, device('C'));
      const { ticket } = deviceLimitDetailsSchema.parse(refused.body.error.details);

      const stolen = await call('POST', '/auth/login/replace', {
        body: { ticket, signOutDeviceId: a.device.id, device: device('D') },
      });
      expect(stolen.status).toBe(401);
      expect((await call('GET', '/auth/me', { token: a.tokens.accessToken })).status).toBe(200);
    });

    it('lets only one of two devices take the last slot at the same moment', async () => {
      const local = phone(14);
      const user = await makeUser(14, 'student', { maxDevices: 1 });
      const results = await Promise.all([
        login(local, PASSWORD, device('race-1')),
        login(local, PASSWORD, device('race-2')),
      ]);
      expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
      const signedIn = await prisma!.device.count({
        where: { userId: user.id, sessionId: { not: null } },
      });
      expect(signedIn).toBe(1);
    });

    it('signs a device out when its refresh token is replayed', async () => {
      const local = phone(15);
      await makeUser(15, 'student');
      const a = await signIn(local, device('A'));
      const first = await call('POST', '/auth/refresh', {
        body: { refreshToken: a.tokens.refreshToken },
      });
      expect(first.status).toBe(200);
      const replay = await call('POST', '/auth/refresh', {
        body: { refreshToken: a.tokens.refreshToken },
      });
      expect(replay.status).toBe(401);
      // The new pair dies with it: the device is signed out.
      const me = await call('GET', '/auth/me', { token: first.body.accessToken });
      expect(errorCode(me)).toBe('DEVICE_SIGNED_OUT');
    });

    it('lets a student sign out one of their devices from another', async () => {
      const local = phone(16);
      await makeUser(16, 'student');
      const a = await signIn(local, device('A'));
      const b = await signIn(local, device('B'));
      const list = await call('GET', '/devices', { token: b.tokens.accessToken });
      expect(list.body.items).toHaveLength(2);
      expect(list.body.items.find((d: any) => d.isCurrent).id).toBe(b.device.id);

      const out = await call('DELETE', `/devices/${a.device.id}`, { token: b.tokens.accessToken });
      expect(out.status).toBe(204);
      expect(errorCode(await call('GET', '/auth/me', { token: a.tokens.accessToken }))).toBe(
        'DEVICE_SIGNED_OUT',
      );
    });
  });

  describe('admin', () => {
    it('is closed to students', async () => {
      const s = await signIn(student.phone, device('not-admin'));
      const res = await call('GET', '/admin/settings', { token: s.tokens.accessToken });
      expect(res.status).toBe(403);
      expect(errorCode(res)).toBe('FORBIDDEN');
      await call('POST', '/auth/logout', { token: s.tokens.accessToken });
    });

    it('sets the institute default, which applies to the next sign-in', async () => {
      const local = phone(20);
      await makeUser(20, 'student');
      await signIn(local, device('A'));

      const set = await call('PATCH', '/admin/settings', {
        token: adminToken,
        body: { defaultMaxDevices: 1 },
      });
      expect(set.body).toEqual({ defaultMaxDevices: 1 });

      const refused = await login(local, PASSWORD, device('B'));
      expect(errorCode(refused)).toBe('DEVICE_LIMIT_REACHED');
      expect(refused.body.error.details.limit).toBe(1);

      await call('PATCH', '/admin/settings', { token: adminToken, body: { defaultMaxDevices: 2 } });
    });

    it("sets one account's own limit, which wins over the default", async () => {
      const local = phone(21);
      const user = await makeUser(21, 'student');
      const patched = await call('PATCH', `/admin/users/${user.id}`, {
        token: adminToken,
        body: { maxDevices: 3 },
      });
      expect(patched.body.maxDevices).toBe(3);
      expect(patched.body.effectiveMaxDevices).toBe(3);

      await signIn(local, device('A'));
      await signIn(local, device('B'));
      await signIn(local, device('C'));
      expect(errorCode(await login(local, PASSWORD, device('D')))).toBe('DEVICE_LIMIT_REACHED');

      const back = await call('PATCH', `/admin/users/${user.id}`, {
        token: adminToken,
        body: { maxDevices: null },
      });
      expect(back.body.effectiveMaxDevices).toBe(2);
      // Lowering the limit signs nobody out.
      expect(back.body.signedInDevices).toBe(3);
    });

    it('creates an account that must choose its own password first', async () => {
      const local = phone(22);
      const created = await call('POST', '/admin/users', {
        token: adminToken,
        body: { phone: local, displayName: 'دانشجوی تازه', password: 'temporary-1405' },
      });
      expect(created.status, JSON.stringify(created.body)).toBe(201);
      expect(created.body.mustChangePassword).toBe(true);
      expect(created.body.phoneMasked).not.toContain(local.slice(4, 7));

      const session = authSessionSchema.parse(
        (await login(local, 'temporary-1405', device('new'))).body,
      );
      expect(session.user.mustChangePassword).toBe(true);
      const blocked = await call('GET', '/devices', { token: session.tokens.accessToken });
      expect(errorCode(blocked)).toBe('PASSWORD_CHANGE_REQUIRED');

      const weak = await call('POST', '/auth/password', {
        token: session.tokens.accessToken,
        body: { currentPassword: 'temporary-1405', newPassword: local },
      });
      expect(errorCode(weak)).toBe('PASSWORD_TOO_WEAK');

      const changed = await call('POST', '/auth/password', {
        token: session.tokens.accessToken,
        body: { currentPassword: 'temporary-1405', newPassword: 'my-own-password' },
      });
      expect(changed.status).toBe(204);
      expect((await call('GET', '/devices', { token: session.tokens.accessToken })).status).toBe(
        200,
      );
      expect((await login(local, 'my-own-password', device('new'))).status).toBe(200);
    });

    it('refuses a phone number twice', async () => {
      const res = await call('POST', '/admin/users', {
        token: adminToken,
        body: { phone: student.phone, displayName: 'تکراری', password: 'another-password' },
      });
      expect(res.status).toBe(409);
      expect(errorCode(res)).toBe('PHONE_TAKEN');
    });

    it('finds users by name or by number in any form', async () => {
      const byNumber = await call(
        'GET',
        `/admin/users?query=${encodeURIComponent(student.phone)}`,
        {
          token: adminToken,
        },
      );
      expect(byNumber.body.items.map((u: any) => u.id)).toContain(student.id);
      const byName = await call('GET', `/admin/users?query=${encodeURIComponent('student 2')}`, {
        token: adminToken,
      });
      expect(byName.body.items.map((u: any) => u.id)).toContain(student.id);
    });

    it('suspending an account signs it out everywhere', async () => {
      const local = phone(23);
      const user = await makeUser(23, 'student');
      const a = await signIn(local, device('A'));
      await call('PATCH', `/admin/users/${user.id}`, {
        token: adminToken,
        body: { status: 'suspended' },
      });
      expect((await call('GET', '/auth/me', { token: a.tokens.accessToken })).status).toBe(401);
      const epoch = await prisma!.user.findUniqueOrThrow({ where: { id: user.id } });
      expect(epoch.revocationEpoch).toBe(1);
    });

    it('cannot remove its own admin access', async () => {
      const res = await call('PATCH', `/admin/users/${admin.id}`, {
        token: adminToken,
        body: { role: 'student' },
      });
      expect(res.status).toBe(403);
    });

    it('enrolls and removes', async () => {
      const user = await makeUser(24, 'student');
      const enrolled = await call('POST', `/admin/users/${user.id}/enrollments`, {
        token: adminToken,
        body: { courseId },
      });
      expect(enrolled.body.enrollments.map((e: any) => e.courseId)).toEqual([courseId]);
      const removed = await call('DELETE', `/admin/users/${user.id}/enrollments/${courseId}`, {
        token: adminToken,
      });
      expect(removed.body.enrollments).toEqual([]);
    });
  });

  describe('internal directory for services/live', () => {
    const internal = (path: string, token = INTERNAL_TOKEN) =>
      call('GET', `/internal${path}`, { headers: { 'x-internal-token': token } });

    it('refuses without the internal token', async () => {
      expect((await internal(`/courses/${courseId}`, 'wrong')).status).toBe(401);
      expect((await call('GET', `/internal/courses/${courseId}`)).status).toBe(401);
    });

    it('answers in the shapes services/live parses', async () => {
      const course = await internal(`/courses/${courseId}`);
      expect(directoryCourseSchema.parse(course.body).id).toBe(courseId);

      const profile = await internal(`/users/${student.id}/profile`);
      expect(directoryProfileSchema.parse(profile.body).phoneMasked).toMatch(/•••/);

      const yes = await internal(`/enrollments/check?userId=${student.id}&courseId=${courseId}`);
      expect(yes.body).toEqual({ enrolled: true });
      const no = await internal(`/enrollments/check?userId=${admin.id}&courseId=${courseId}`);
      expect(no.body).toEqual({ enrolled: false });

      const courses = await internal(`/users/${student.id}/courses`);
      expect(directoryUserCoursesSchema.parse(courses.body).courseIds).toEqual([courseId]);
      expect((await internal(`/users/${admin.id}/courses`)).body).toEqual({ courseIds: [] });
    });

    it('answers 404 for what does not exist', async () => {
      expect((await internal(`/courses/${newId('course')}`)).status).toBe(404);
      expect((await internal(`/users/${newId('user')}/profile`)).status).toBe(404);
    });
  });
});
