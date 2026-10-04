import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import {
  adminUserListQuerySchema,
  createUserBodySchema,
  enrollBodySchema,
  id,
  updateSettingsBodySchema,
  updateUserBodySchema,
} from '@tihe/contracts';

import { Roles } from '../auth/auth.guard.js';
import { CurrentUser, type AuthContext } from '../auth/current-user.decorator.js';
import { SettingsService } from '../settings/settings.service.js';
import { parseOrThrow } from '../../common/zod.pipe.js';
import { AdminService } from './admin.service.js';

/** Admin endpoints (ADR-0013, ADR-0014). Every route requires role admin. */
@ApiTags('admin')
@Controller('admin')
@Roles('admin')
export class AdminController {
  constructor(
    private readonly admin: AdminService,
    private readonly settings: SettingsService,
  ) {}

  @Get('settings')
  @ApiOperation({ summary: 'Institute settings, e.g. the default device limit' })
  getSettings() {
    return this.settings.get();
  }

  @Patch('settings')
  @ApiOperation({
    summary: 'Change institute settings',
    description:
      'A new default device limit applies to the next sign-in of every account without its own ' +
      'limit. Nobody already signed in is signed out.',
  })
  updateSettings(@CurrentUser() auth: AuthContext, @Body() body: unknown) {
    return this.settings.update(parseOrThrow(updateSettingsBodySchema, body), auth.userId);
  }

  @Get('users')
  @ApiOperation({ summary: 'Find accounts by name or phone number' })
  listUsers(@Query() query: unknown) {
    return this.admin.listUsers(parseOrThrow(adminUserListQuerySchema, query));
  }

  @Post('users')
  @ApiOperation({
    summary: 'Create an account',
    description:
      'With mustChangePassword (the default) the user chooses their own at first sign-in.',
  })
  createUser(@CurrentUser() auth: AuthContext, @Body() body: unknown) {
    return this.admin.createUser(parseOrThrow(createUserBodySchema, body), auth.userId);
  }

  @Get('users/:id')
  getUser(@Param('id') userId: string) {
    return this.admin.getUser(parseOrThrow(id('user'), userId));
  }

  @Patch('users/:id')
  @ApiOperation({
    summary: 'Edit an account',
    description:
      'maxDevices null returns the account to the institute default. A new password or a ' +
      'suspension signs the account out on every device.',
  })
  updateUser(@CurrentUser() auth: AuthContext, @Param('id') userId: string, @Body() body: unknown) {
    return this.admin.updateUser(
      parseOrThrow(id('user'), userId),
      parseOrThrow(updateUserBodySchema, body),
      auth.userId,
    );
  }

  @Delete('users/:id/devices/:deviceId')
  @HttpCode(204)
  @ApiOperation({ summary: "Sign one of a user's devices out" })
  async signOutDevice(
    @CurrentUser() auth: AuthContext,
    @Param('id') userId: string,
    @Param('deviceId') deviceId: string,
  ) {
    await this.admin.signOutDevice(
      parseOrThrow(id('user'), userId),
      parseOrThrow(id('device'), deviceId),
      auth.userId,
    );
  }

  @Post('users/:id/enrollments')
  @ApiOperation({ summary: 'Enroll a user in a course' })
  enroll(@CurrentUser() auth: AuthContext, @Param('id') userId: string, @Body() body: unknown) {
    return this.admin.enroll(
      parseOrThrow(id('user'), userId),
      parseOrThrow(enrollBodySchema, body),
      auth.userId,
    );
  }

  @Delete('users/:id/enrollments/:courseId')
  @ApiOperation({ summary: 'Remove a user from a course' })
  unenroll(
    @CurrentUser() auth: AuthContext,
    @Param('id') userId: string,
    @Param('courseId') courseId: string,
  ) {
    return this.admin.unenroll(
      parseOrThrow(id('user'), userId),
      parseOrThrow(id('course'), courseId),
      auth.userId,
    );
  }

  @Get('courses')
  @ApiOperation({ summary: 'Courses, to enroll users in' })
  listCourses() {
    return this.admin.listCourses();
  }
}
