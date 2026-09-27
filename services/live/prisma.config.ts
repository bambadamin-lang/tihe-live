import { defineConfig } from 'prisma/config';

// tihe_live, not tihe: services/live owns its own database (ADR-0012).
export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: { path: 'prisma/migrations' },
  datasource: {
    url:
      process.env.LIVE_DATABASE_URL ??
      'postgresql://tihe:tihe_dev_password@localhost:5432/tihe_live?schema=public',
  },
});
