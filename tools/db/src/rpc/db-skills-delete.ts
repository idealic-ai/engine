/**
 * db.skills.delete — Remove a cached skill definition by project and name.
 *
 * Returns { deleted: true } if a row was removed, { deleted: false } if
 * the skill didn't exist. No error on missing — idempotent delete.
 *
 * Callers: bash cleanup scripts, skill removal workflows.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({
  projectId: z.number(),
  name: z.string(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  db.run(
    "DELETE FROM skills WHERE project_id = ? AND name = ?",
    [args.projectId, args.name]
  );
  const changes = db.getRowsModified();
  return { ok: true, data: { deleted: changes > 0 } };
}

registerCommand("db.skills.delete", { schema, handler });
