import { createDb, type DbConnection } from "../db-wrapper.js";
import { applySchema } from "../schema.js";

/**
 * Create an in-memory DbConnection with schema applied and FKs enabled.
 * Use in beforeEach() for RPC handler tests.
 */
export async function createTestDb(): Promise<DbConnection> {
  const db = await createDb(":memory:");
  await applySchema(db);
  return db;
}

/** Helper to query a single row as an object */
export async function queryRow(db: DbConnection, sql: string, params: unknown[] = []): Promise<Record<string, unknown> | null> {
  const row = await db.get(sql, params);
  return row ?? null;
}

/** Helper to query multiple rows as objects */
export async function queryRows(db: DbConnection, sql: string, params: unknown[] = []): Promise<Record<string, unknown>[]> {
  return db.all(sql, params);
}

/** Helper to count rows */
export async function queryCount(db: DbConnection, sql: string, params: unknown[] = []): Promise<number> {
  const row = await db.get<Record<string, number>>(sql, params);
  if (!row) return 0;
  return Object.values(row)[0];
}
