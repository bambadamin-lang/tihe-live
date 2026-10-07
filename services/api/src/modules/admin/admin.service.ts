import { Injectable, Logger } from '@nestjs/common';
import {
  maskPhone,
  phoneSchema,
  type AdminCourse,
  type AdminUser,
  type AdminUserDetail,
  type AdminUserList,
  type AdminUserListQuery,
  type CreateUserBody,
  type EnrollBody,
  type UpdateUserBody,
} from '@tihe/contracts';
import { newId, Prisma, type User } from '@tihe/db';

import { AppError } from '../../common/app-error.js';
import { PrismaService } from '../../common/prisma.service.js';
import { checkPasswordPolicy, PasswordHasher } from '@tihe/crypto';
import { DevicesService } from '../devices/devices.service.js';
import { effectiveDeviceLimit } from '../devices/sessions.js';
import { SettingsService } from '../settings/settings.service.js';

/**
 * Accounts, the device limit and enrollments, for admins (ADR-0013, ADR-0014).
 *
 * Phone numbers come in from the admin and go out masked, as everywhere: an admin finds a student
 * by typing their number, not by reading a list of numbers.
 */
@Injectable()
export class AdminService {
  private readonly logger = new Logger(AdminService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly devices: DevicesService,
    private readonly settings: SettingsService,
    private readonly hasher: PasswordHasher,
  ) {}

  async listUsers(query: AdminUserListQuery): Promise<AdminUserList> {
    const where: Prisma.UserWhereInput = {};
    if (query.role) where.role = query.role;

    const text = query.query?.trim();
    if (text) {
      const phone = phoneSchema.safeParse(text);
      const digits = foldDigits(text).replace(/\D/g, '');
      where.OR = [
        { displayName: { contains: text, mode: 'insensitive' } },
        // A full number in any form, or the digits of part of one (09125, 912 555).
        ...(phone.success ? [{ phone: phone.data }] : []),
        ...(digits.length >= 4 ? [{ phone: { contains: digits.replace(/^0/, '') } }] : []),
      ];
    }

    const rows = await this.prisma.user.findMany({
      where,
      orderBy: { id: 'desc' },
      take: query.limit + 1,
      ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
    });

    const page = rows.slice(0, query.limit);
    return {
      items: await this.toAdminUsers(page),
      nextCursor: rows.length > query.limit ? (page.at(-1)?.id ?? null) : null,
    };
  }

  async getUser(userId: string): Promise<AdminUserDetail> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw AppError.notFound('user');

    const [[summary], devices, enrollments] = await Promise.all([
      this.toAdminUsers([user]),
      this.prisma.device.findMany({
        where: { userId, revokedAt: null },
        orderBy: [{ lastSeenAt: 'desc' }, { createdAt: 'desc' }],
      }),
      this.prisma.enrollment.findMany({
        where: { userId },
        include: { course: { select: { title: true } } },
        orderBy: { enrolledAt: 'desc' },
      }),
    ]);

    const now = new Date();
    const deviceDtos = await Promise.all(devices.map((d) => this.devices.toDto(d, null, now)));

    return {
      ...summary!,
      devices: deviceDtos.sort((a, b) => Number(b.signedIn) - Number(a.signedIn)),
      enrollments: enrollments.map((e) => ({
        courseId: e.courseId,
        courseTitle: e.course.title,
        status: e.status,
        enrolledAt: e.enrolledAt.toISOString(),
        expiresAt: e.expiresAt?.toISOString() ?? null,
      })),
    };
  }

  async createUser(body: CreateUserBody, adminId: string): Promise<AdminUserDetail> {
    const problem = checkPasswordPolicy(body.password, body.phone);
    if (problem) throw new AppError('PASSWORD_TOO_WEAK', problem);

    if (await this.prisma.user.findUnique({ where: { phone: body.phone }, select: { id: true } })) {
      throw new AppError('PHONE_TAKEN');
    }

    const passwordHash = await this.hasher.hash(body.password);
    try {
      const user = await this.prisma.user.create({
        data: {
          id: newId('user'),
          phone: body.phone,
          displayName: body.displayName,
          role: body.role,
          passwordHash,
          passwordChangedAt: new Date(),
          mustChangePassword: body.mustChangePassword,
          maxDevices: body.maxDevices,
        },
      });
      this.logger.log(
        `admin ${adminId} created ${user.role} ${maskPhone(user.phone)} (${user.id})`,
      );
      return this.getUser(user.id);
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new AppError('PHONE_TAKEN');
      }
      throw error;
    }
  }

  async updateUser(
    userId: string,
    body: UpdateUserBody,
    adminId: string,
  ): Promise<AdminUserDetail> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw AppError.notFound('user');

    // An admin cannot lock themselves out: someone has to be left to undo it.
    if (
      userId === adminId &&
      ((body.role && body.role !== 'admin') || body.status === 'suspended')
    ) {
      throw AppError.forbidden('you cannot remove your own admin access');
    }

    const data: Prisma.UserUpdateInput = {};
    if (body.displayName !== undefined) data.displayName = body.displayName;
    if (body.role !== undefined) data.role = body.role;
    if (body.status !== undefined) data.status = body.status;
    if (body.maxDevices !== undefined) data.maxDevices = body.maxDevices;
    if (body.mustChangePassword !== undefined) data.mustChangePassword = body.mustChangePassword;

    if (body.password !== undefined) {
      const problem = checkPasswordPolicy(body.password, user.phone);
      if (problem) throw new AppError('PASSWORD_TOO_WEAK', problem);
      data.passwordHash = await this.hasher.hash(body.password);
      data.passwordChangedAt = new Date();
      // A password an admin chose is temporary unless they say otherwise.
      data.mustChangePassword = body.mustChangePassword ?? true;
    }

    const now = new Date();
    const suspending = body.status === 'suspended' && user.status !== 'suspended';
    if (suspending) data.revocationEpoch = { increment: 1 };

    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id: userId }, data });
      // A new password or a suspension signs the account out everywhere; a suspension also
      // revokes offline licences through the epoch.
      if (body.password !== undefined || suspending) {
        await this.devices.endAllSessions(tx, userId, now);
      }
    });

    this.logger.log(`admin ${adminId} updated user ${userId}: ${Object.keys(body).join(', ')}`);
    return this.getUser(userId);
  }

  async signOutDevice(userId: string, deviceId: string, adminId: string): Promise<void> {
    await this.devices.signOut(userId, deviceId);
    this.logger.log(`admin ${adminId} signed out device ${deviceId} of user ${userId}`);
  }

  async enroll(userId: string, body: EnrollBody, adminId: string): Promise<AdminUserDetail> {
    const [user, course] = await Promise.all([
      this.prisma.user.findUnique({ where: { id: userId }, select: { id: true } }),
      this.prisma.course.findUnique({ where: { id: body.courseId }, select: { id: true } }),
    ]);
    if (!user) throw AppError.notFound('user');
    if (!course) throw AppError.notFound('course');

    const expiresAt = body.expiresAt ? new Date(body.expiresAt) : null;
    await this.prisma.enrollment.upsert({
      where: { userId_courseId: { userId, courseId: body.courseId } },
      create: { id: newId('enrollment'), userId, courseId: body.courseId, expiresAt },
      update: { status: 'active', expiresAt },
    });
    this.logger.log(`admin ${adminId} enrolled ${userId} in ${body.courseId}`);
    return this.getUser(userId);
  }

  async unenroll(userId: string, courseId: string, adminId: string): Promise<AdminUserDetail> {
    await this.prisma.enrollment.deleteMany({ where: { userId, courseId } });
    this.logger.log(`admin ${adminId} removed ${userId} from ${courseId}`);
    return this.getUser(userId);
  }

  async listCourses(): Promise<AdminCourse[]> {
    const courses = await this.prisma.course.findMany({
      where: { status: { not: 'archived' } },
      orderBy: { title: 'asc' },
      include: { _count: { select: { enrollments: { where: { status: 'active' } } } } },
    });
    return courses.map((c) => ({
      id: c.id,
      title: c.title,
      status: c.status,
      enrolledCount: c._count.enrollments,
    }));
  }

  private async toAdminUsers(users: User[]): Promise<AdminUser[]> {
    if (users.length === 0) return [];
    const now = new Date();
    const ids = users.map((u) => u.id);

    const [defaultMax, sessions, enrollments] = await Promise.all([
      this.settings.defaultMaxDevices(),
      this.prisma.device.groupBy({
        by: ['userId'],
        where: {
          userId: { in: ids },
          revokedAt: null,
          sessionId: { not: null },
          sessionExpiresAt: { gt: now },
        },
        _count: { _all: true },
      }),
      this.prisma.enrollment.groupBy({
        by: ['userId'],
        where: { userId: { in: ids }, status: 'active' },
        _count: { _all: true },
      }),
    ]);

    const signedIn = new Map(sessions.map((s) => [s.userId, s._count._all]));
    const enrolled = new Map(enrollments.map((e) => [e.userId, e._count._all]));

    return users.map((u) => ({
      id: u.id,
      phoneMasked: maskPhone(u.phone),
      displayName: u.displayName,
      role: u.role,
      status: u.status,
      mustChangePassword: u.mustChangePassword,
      createdAt: u.createdAt.toISOString(),
      maxDevices: u.maxDevices,
      effectiveMaxDevices: effectiveDeviceLimit(u.maxDevices, defaultMax),
      signedInDevices: signedIn.get(u.id) ?? 0,
      enrolledCourses: enrolled.get(u.id) ?? 0,
    }));
  }
}

function foldDigits(value: string): string {
  return value
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660));
}
