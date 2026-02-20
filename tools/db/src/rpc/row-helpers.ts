/**
 * SQL Result Marshalling — bridges sql.js wire format to plain JS objects.
 *
 * sql.js returns query results as `{ columns: string[], values: unknown[][] }` —
 * a columnar format optimized for the WASM boundary. Every RPC handler needs row
 * objects instead. These helpers do the conversion.
 *
 * Two core converters:
 *   resultToRow()  — single row (first result, first value) or null
 *   resultToRows() — all rows as object array
 *
 * Entity-specific helpers (getProjectRow, getTaskRow, etc.) are convenience
 * wrappers used across multiple RPC handlers to avoid duplicating SELECT + marshal.
 * They return full rows — callers pick the fields they need.
 */
import type { Database } from "sql.js";

/**
 * Convert a sql.js result set to a plain object.
 * Returns null if no rows found.
 */
function resultToRow(
  result: { columns: string[]; values: unknown[][] }[]
): Record<string, unknown> | null {
  if (result.length === 0 || result[0].values.length === 0) return null;
  const { columns, values } = result[0];
  const obj: Record<string, unknown> = {};
  for (let i = 0; i < columns.length; i++) {
    obj[columns[i]] = values[0][i];
  }
  return obj;
}

/**
 * Convert a sql.js result set to an array of objects.
 */
function resultToRows(
  result: { columns: string[]; values: unknown[][] }[]
): Record<string, unknown>[] {
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

// ── Entity-specific helpers ────────────────────────────

export function getProjectRow(
  db: Database,
  id: number
): Record<string, unknown> | null {
  return resultToRow(db.exec("SELECT * FROM projects WHERE id = ?", [id]));
}

export function getProjectByPath(
  db: Database,
  path: string
): Record<string, unknown> | null {
  return resultToRow(
    db.exec("SELECT * FROM projects WHERE path = ?", [path])
  );
}

export function getTaskRow(
  db: Database,
  dirPath: string
): Record<string, unknown> | null {
  return resultToRow(
    db.exec("SELECT * FROM tasks WHERE dir_path = ?", [dirPath])
  );
}

export function getEffortRow(
  db: Database,
  id: number
): Record<string, unknown> | null {
  return resultToRow(db.exec("SELECT * FROM efforts WHERE id = ?", [id]));
}

export function getSkillRow(
  db: Database,
  projectId: number,
  name: string
): Record<string, unknown> | null {
  return resultToRow(
    db.exec(
      "SELECT * FROM skills WHERE project_id = ? AND name = ?",
      [projectId, name]
    )
  );
}

export function getSessionRow(
  db: Database,
  id: number
): Record<string, unknown> | null {
  return resultToRow(db.exec("SELECT * FROM sessions WHERE id = ?", [id]));
}

export function getActiveSession(
  db: Database,
  effortId: number
): Record<string, unknown> | null {
  return resultToRow(
    db.exec(
      "SELECT * FROM sessions WHERE effort_id = ? AND ended_at IS NULL ORDER BY id DESC LIMIT 1",
      [effortId]
    )
  );
}

export function getEffortRows(
  db: Database,
  taskId: string
): Record<string, unknown>[] {
  return resultToRows(
    db.exec(
      "SELECT * FROM efforts WHERE task_id = ? ORDER BY ordinal",
      [taskId]
    )
  );
}

export function getLastInsertId(db: Database): number {
  const result = db.exec("SELECT last_insert_rowid() AS id");
  return result[0].values[0][0] as number;
}
