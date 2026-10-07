# Initial migration

Generated with:

```bash
npx prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script \
  > migration.sql
```

then hand-extended at the bottom of `migration.sql` with the Persian search support —
`normalize_fa()`, the generated `search_text` columns, and the trigram indexes. Prisma cannot
express any of those, and it only reads `migration.sql`, so they live in the same file rather than a
sibling one.

**If you regenerate this migration, re-append that section** or Persian search stops working with
no error — queries simply return nothing.
