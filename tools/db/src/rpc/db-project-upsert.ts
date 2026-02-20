/**
 * db.project.upsert — Create or update an engine project.
 *
 * Projects are the root entity: one per codebase (keyed by absolute path).
 * A shared daemon serves multiple projects — this table tracks them.
 *
 * Idempotent: ON CONFLICT updates name only if a new value is provided
 * (COALESCE preserves existing data on null).
 *
 * Lifecycle position: Called first during `engine effort start` compound flow.
 * The project must exist before tasks, skills, or efforts can reference it.
 *
 * Callers: bash `engine effort start` → db.task.upsert depends on project_id.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getProjectByPath, getLastInsertId } from "./row-helpers.js";

const schema = z.object({
  path: z.string(),
  name: z.string().optional(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  db.exec("BEGIN");
  try {
    db.run(
      `INSERT INTO projects (path, name)
       VALUES (?, ?)
       ON CONFLICT(path) DO UPDATE SET
         name = COALESCE(excluded.name, projects.name)`,
      [args.path, args.name ?? null]
    );

    const project = getProjectByPath(db, args.path);
    db.exec("COMMIT");
    return { ok: true, data: { project } };
  } catch (err: unknown) {
    db.exec("ROLLBACK");
    throw err;
  }
}

registerCommand("db.project.upsert", { schema, handler });
