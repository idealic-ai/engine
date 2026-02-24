/**
 * db namespace override — merges DbConnection (raw SQL) with the auto-derived namespace.
 *
 * ctx.db — DbConnection + NamespaceOf<"db"> (typed proxy).
 * All other namespaces are derived automatically from Registered via AllNamespaces.
 */
import type { DbConnection } from "../db-wrapper.js";
import type { NamespaceOf } from "engine-shared/rpc-types";

declare module "engine-shared/rpc-types" {
  interface NamespaceOverrides {
    db: DbConnection & NamespaceOf<"db">;
  }
}
