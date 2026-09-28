import { z } from 'zod';
import { id, paginated, paginationQuerySchema } from '../common.js';
import {
  courseDetailSchema,
  courseSummarySchema,
  termSchema,
  videoDetailSchema,
  videoSummarySchema,
} from '../entities/catalog.js';

export const termsResponseSchema = z.object({
  items: z.array(termSchema),
});

export const coursesQuerySchema = paginationQuerySchema.extend({
  termId: id('term').optional(),
  status: z.enum(['active', 'archived', 'all']).default('active'),
});
export type CoursesQuery = z.infer<typeof coursesQuerySchema>;

export const coursesResponseSchema = paginated(courseSummarySchema);
export const courseDetailResponseSchema = courseDetailSchema;
export const videoDetailResponseSchema = videoDetailSchema;

export const searchQuerySchema = paginationQuerySchema.extend({
  q: z.string().min(2).max(120),
  /** Restrict to one course; omit to search everything the student is enrolled in. */
  courseId: id('course').optional(),
});
export type SearchQuery = z.infer<typeof searchQuerySchema>;

export const searchResultSchema = z.object({
  kind: z.enum(['course', 'video']),
  course: courseSummarySchema.optional(),
  video: videoSummarySchema.optional(),
  /** Relevance from the trigram similarity score, for ordering client-side if needed. */
  score: z.number(),
});
export type SearchResult = z.infer<typeof searchResultSchema>;

export const searchResponseSchema = paginated(searchResultSchema);
