import initSqlJs, { type Database } from "sql.js";
import { applySchema } from "../schema.js";

/**
 * Create an in-memory Database with schema applied and FKs enabled.
 * Use in beforeEach() for RPC handler tests.
 */
export async function createTestDb(): Promise<Database> {
  const SQL = await initSqlJs();
  const db = new SQL.Database();
  db.run("PRAGMA foreign_keys = ON");
  applySchema(db);
  return db;
}

/** Helper to query a single row as an object */
export function queryRow(db: Database, sql: string, params: unknown[] = []): Record<string, unknown> | null {
  const result = db.exec(sql, params as (string | number | null)[]);
  if (result.length === 0 || result[0].values.length === 0) return null;
  const { columns, values } = result[0];
  const obj: Record<string, unknown> = {};
  for (let i = 0; i < columns.length; i++) {
    obj[columns[i]] = values[0][i];
  }
  return obj;
}

/** Helper to query multiple rows as objects */
export function queryRows(db: Database, sql: string, params: unknown[] = []): Record<string, unknown>[] {
  const result = db.exec(sql, params as (string | number | null)[]);
  if (result.length === 0) return [];
  const { columns, values } = result[0];
  return values.map((row) => {
    const obj: Record<string, unknown> = {};
    for (let i = 0; i < columns.length; i++) {
      obj[columns[i]] = row[i];
    }
    return obj;
  });
}

/** Helper to count rows */
export function queryCount(db: Database, sql: string, params: unknown[] = []): number {
  const result = db.exec(sql, params as (string | number | null)[]);
  if (result.length === 0) return 0;
  return result[0].values[0][0] as number;
}
