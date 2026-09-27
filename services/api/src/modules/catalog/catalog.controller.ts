import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { coursesQuerySchema, searchQuerySchema } from '@tihe/contracts';

import { CurrentUser, type AuthContext } from '../auth/current-user.decorator.js';
import { CatalogService } from './catalog.service.js';

@ApiTags('catalog')
@Controller('catalog')
export class CatalogController {
  constructor(private readonly catalog: CatalogService) {}

  @Get('terms')
  @ApiOperation({ summary: 'Terms the student has enrollments in' })
  async terms(@CurrentUser() auth: AuthContext) {
    return { items: await this.catalog.terms(auth.userId) };
  }

  @Get('courses')
  @ApiOperation({
    summary: 'Enrolled courses',
    description:
      'Only courses with an active enrollment. Unenrolled courses are absent rather than locked — ' +
      'the catalogue is not a discovery surface.',
  })
  async courses(@CurrentUser() auth: AuthContext, @Query() query: unknown) {
    const parsed = coursesQuerySchema.parse(query);
    return this.catalog.courses(auth.userId, {
      termId: parsed.termId,
      limit: parsed.limit,
      cursor: parsed.cursor,
    });
  }

  @Get('courses/:id')
  @ApiOperation({
    summary: 'Course with sections, videos and progress',
    description: 'Returns 404 for a course the student is not enrolled in, not 403.',
  })
  async course(@CurrentUser() auth: AuthContext, @Param('id') id: string) {
    return this.catalog.courseDetail(auth.userId, id);
  }

  @Get('videos/:id')
  @ApiOperation({ summary: 'Video detail: renditions, chapters, attachments, resume point' })
  async video(@CurrentUser() auth: AuthContext, @Param('id') id: string) {
    return this.catalog.videoDetail(auth.userId, id);
  }

  @Get('search')
  @ApiOperation({
    summary: 'Search enrolled content',
    description:
      'Persian-aware: Arabic/Persian letter variants, the zero-width non-joiner, diacritics and ' +
      'digit forms are all normalised, so كتاب finds کتاب and ۱۴۰۵ finds 1405.',
  })
  async search(@CurrentUser() auth: AuthContext, @Query() query: unknown) {
    const parsed = searchQuerySchema.parse(query);
    return this.catalog.search(auth.userId, {
      q: parsed.q,
      courseId: parsed.courseId,
      limit: parsed.limit,
    });
  }
}
