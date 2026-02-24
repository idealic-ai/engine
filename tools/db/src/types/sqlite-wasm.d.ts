declare module "@finch/sqlite-wasm/db-connection" {
  export interface WasmRunResult {
    changes: number;
    lastInsertRowid: number;
  }

  export interface WasmDbConnection {
    run(sql: string, params?: unknown[]): Promise<WasmRunResult>;
    get(sql: string, params?: unknown[]): Promise<Record<string, unknown> | undefined>;
    all(sql: string, params?: unknown[]): Promise<Record<string, unknown>[]>;
    exec(sql: string): Promise<void>;
    close(): Promise<void>;
  }

  export function createDbConnection(dbPath: string): Promise<WasmDbConnection>;
}
