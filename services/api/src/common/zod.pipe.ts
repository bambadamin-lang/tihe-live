import { type ArgumentMetadata, Injectable, type PipeTransform } from '@nestjs/common';
import type { ZodSchema } from 'zod';

/**
 * Validates a payload against a schema from @tihe/contracts.
 *
 * Deliberately not `class-validator`: the schemas are already the shared contract, and duplicating
 * them as decorated DTO classes is how an API and its client drift apart.
 *
 * ZodError is translated by the global error filter, so throwing raw is correct here.
 */
@Injectable()
export class ZodValidationPipe implements PipeTransform {
  constructor(private readonly schema: ZodSchema) {}

  transform(value: unknown, _metadata: ArgumentMetadata) {
    return this.schema.parse(value);
  }
}
