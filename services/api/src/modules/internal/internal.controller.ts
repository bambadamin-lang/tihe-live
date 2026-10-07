import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import {
  id,
  maskPhone,
  type DirectoryCourse,
  type DirectoryProfile,
  type DirectoryUserCourses,
} from '@tihe/contracts';
import { z } from 'zod';

import { AppError } from '../../common/app-error.js';
import { PrismaService } from '../../common/prisma.service.js';
import { parseOrThrow } from '../../common/zod.pipe.js';
import { Public } from '../auth/auth.guard.js';
import { InternalTokenGuard } from './internal-token.guard.js';

const enrollmentQuerySchema = z.object({ userId: id('user'), courseId: id('course') });

/**
 * The directory services/live reads through its `CourseDirectory` (ADR-0012; contract in
 * packages/contracts/src/live/directory.ts): a course, an enrollment check, and a profile.
 * Server-to-server only. 404 means "no such thing", which services/live treats as a refusal.
 */
@ApiExcludeController()
@Controller('internal')
@Public()
@UseGuards(InternalTokenGuard)
export class InternalController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('courses/:courseId')
  async course(@Param('courseId') courseId: string): Promise<DirectoryCourse> {
    const course = await this.prisma.course.findUnique({
      where: { id: parseOrThrow(id('course'), courseId) },
      select: { id: true, title: true, teacherId: true, allowCapture: true },
    });
    if (!course) throw AppError.notFound('course');
    return course;
  }

  /** Enrolled means active and not past its end date: the same rule as the catalog. */
  @Get('enrollments/check')
  async enrollment(@Query() query: unknown): Promise<{ enrolled: boolean }> {
    const { userId, courseId } = parseOrThrow(enrollmentQuerySchema, query);
    const now = new Date();
    const count = await this.prisma.enrollment.count({
      where: {
        userId,
        courseId,
        status: 'active',
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
        user: { status: 'active' },
      },
    });
    return { enrolled: count > 0 };
  }

  /** The masked number is only ever used for this user's own watermark. */
  @Get('users/:userId/profile')
  async profile(@Param('userId') userId: string): Promise<DirectoryProfile> {
    const user = await this.prisma.user.findUnique({
      where: { id: parseOrThrow(id('user'), userId) },
      select: { id: true, displayName: true, phone: true, role: true },
    });
    if (!user) throw AppError.notFound('user');
    return {
      id: user.id,
      displayName: user.displayName,
      phoneMasked: maskPhone(user.phone),
      role: user.role,
    };
  }

  /** Courses the user attends (active, unexpired) or teaches: what "my classes" lists. */
  @Get('users/:userId/courses')
  async courses(@Param('userId') userId: string): Promise<DirectoryUserCourses> {
    const user = parseOrThrow(id('user'), userId);
    const now = new Date();
    const [enrolled, taught] = await Promise.all([
      this.prisma.enrollment.findMany({
        where: {
          userId: user,
          status: 'active',
          OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
          user: { status: 'active' },
        },
        select: { courseId: true },
      }),
      this.prisma.course.findMany({ where: { teacherId: user }, select: { id: true } }),
    ]);
    return {
      courseIds: [...new Set([...enrolled.map((e) => e.courseId), ...taught.map((c) => c.id)])],
    };
  }
}
