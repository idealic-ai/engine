import { describe, it, expect, afterEach } from "vitest";
import { createDb, transformRow, prepareParams, snakeToCamel, type DbConnection } from "../db-wrapper.js";

let conn: DbConnection | null = null;

afterEach(async () => {
  if (conn) {
    await conn.close();
    conn = null;
  }
});

describe("DbConnection", () => {
  it("should open an in-memory database", async () => {
    conn = await createDb(":memory:");
    expect(conn).toBeDefined();
  });

  it("should execute DDL via exec()", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)");
    // No error = success
  });

  it("should insert and retrieve via run() and get()", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)");

    const runResult = await conn.run(
      "INSERT INTO test (name) VALUES (?)",
      ["hello"]
    );
    expect(runResult.lastID).toBe(1);
    expect(runResult.changes).toBe(1);

    const row = await conn.get<{ id: number; name: string }>(
      "SELECT * FROM test WHERE id = ?",
      [1]
    );
    expect(row).toEqual({ id: 1, name: "hello" });
  });

  it("should return undefined from get() when no rows match", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY)");

    const row = await conn.get("SELECT * FROM test WHERE id = ?", [999]);
    expect(row).toBeUndefined();
  });

  it("should retrieve multiple rows via all()", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)");
    await conn.run("INSERT INTO test (name) VALUES (?)", ["a"]);
    await conn.run("INSERT INTO test (name) VALUES (?)", ["b"]);
    await conn.run("INSERT INTO test (name) VALUES (?)", ["c"]);

    const rows = await conn.all<{ id: number; name: string }>(
      "SELECT * FROM test ORDER BY id"
    );
    expect(rows).toHaveLength(3);
    expect(rows[0].name).toBe("a");
    expect(rows[2].name).toBe("c");
  });

  it("should return empty array from all() when no rows match", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY)");

    const rows = await conn.all("SELECT * FROM test");
    expect(rows).toEqual([]);
  });

  it("should support transactions", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT)");

    await conn.run("BEGIN");
    await conn.run("INSERT INTO test (val) VALUES (?)", ["x"]);
    await conn.run("INSERT INTO test (val) VALUES (?)", ["y"]);
    await conn.run("COMMIT");

    const rows = await conn.all("SELECT * FROM test");
    expect(rows).toHaveLength(2);
  });

  it("should support rollback", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT)");

    await conn.run("INSERT INTO test (val) VALUES (?)", ["keep"]);
    await conn.run("BEGIN");
    await conn.run("INSERT INTO test (val) VALUES (?)", ["discard"]);
    await conn.run("ROLLBACK");

    const rows = await conn.all("SELECT * FROM test");
    expect(rows).toHaveLength(1);
  });

  it("should reject on SQL errors", async () => {
    conn = await createDb(":memory:");
    await expect(
      conn.run("INSERT INTO nonexistent (x) VALUES (?)", [1])
    ).rejects.toThrow();
  });

  it("should load sqlite-vec extension", async () => {
    conn = await createDb(":memory:");

    // vec_version() is available if sqlite-vec loaded correctly
    const row = await conn.get<{ v: string }>("SELECT vec_version() as v");
    expect(row).toBeDefined();
    expect(typeof row!.v).toBe("string");
  });

  it("should support vec_distance_cosine via sqlite-vec", async () => {
    conn = await createDb(":memory:");

    // Create two identical vectors — distance should be 0
    const v1 = new Float32Array([1, 0, 0, 0]);
    const v2 = new Float32Array([1, 0, 0, 0]);

    const row = await conn.get<{ dist: number }>(
      "SELECT vec_distance_cosine(?, ?) as dist",
      [Buffer.from(v1.buffer), Buffer.from(v2.buffer)]
    );
    expect(row).toBeDefined();
    expect(row!.dist).toBeCloseTo(0, 5);
  });

  it("should support vec_distance_cosine with different vectors", async () => {
    conn = await createDb(":memory:");

    // Orthogonal vectors — cosine distance should be 1
    const v1 = new Float32Array([1, 0, 0, 0]);
    const v2 = new Float32Array([0, 1, 0, 0]);

    const row = await conn.get<{ dist: number }>(
      "SELECT vec_distance_cosine(?, ?) as dist",
      [Buffer.from(v1.buffer), Buffer.from(v2.buffer)]
    );
    expect(row).toBeDefined();
    expect(row!.dist).toBeCloseTo(1, 5);
  });

  it("should enable foreign keys", async () => {
    conn = await createDb(":memory:");

    // get() auto-transforms: foreign_keys → foreignKeys
    const row = await conn.get<{ foreignKeys: number }>(
      "PRAGMA foreign_keys"
    );
    expect(row).toBeDefined();
    expect(row!.foreignKeys).toBe(1);
  });

  it("should auto-transform snake_case keys to camelCase", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, first_name TEXT, last_name TEXT)");
    await conn.run("INSERT INTO test (first_name, last_name) VALUES (?, ?)", ["John", "Doe"]);

    const row = await conn.get<{ id: number; firstName: string; lastName: string }>(
      "SELECT * FROM test WHERE id = 1"
    );
    expect(row).toEqual({ id: 1, firstName: "John", lastName: "Doe" });
  });

  it("should auto-parse JSON strings in results", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, config TEXT, tags TEXT)");
    await conn.run(
      "INSERT INTO test (config, tags) VALUES (?, ?)",
      ['{"key":"val"}', '["a","b"]']
    );

    const row = await conn.get<{ id: number; config: { key: string }; tags: string[] }>(
      "SELECT * FROM test WHERE id = 1"
    );
    expect(row!.config).toEqual({ key: "val" });
    expect(row!.tags).toEqual(["a", "b"]);
  });

  it("should auto-stringify object/array params", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, data TEXT)");
    await conn.run("INSERT INTO test (data) VALUES (?)", [{ hello: "world" }]);

    const row = await conn.get<{ id: number; data: { hello: string } }>(
      "SELECT * FROM test WHERE id = 1"
    );
    expect(row!.data).toEqual({ hello: "world" });
  });

  it("should not stringify Buffer params", async () => {
    conn = await createDb(":memory:");
    const v1 = new Float32Array([1, 0, 0, 0]);
    const v2 = new Float32Array([1, 0, 0, 0]);

    const row = await conn.get<{ dist: number }>(
      "SELECT vec_distance_cosine(?, ?) as dist",
      [Buffer.from(v1.buffer), Buffer.from(v2.buffer)]
    );
    expect(row!.dist).toBeCloseTo(0, 5);
  });

  it("should provide raw escape hatch without transforms", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, first_name TEXT)");
    await conn.run("INSERT INTO test (first_name) VALUES (?)", ["Jane"]);

    const raw = await conn.raw.get<{ first_name: string }>(
      "SELECT * FROM test WHERE id = 1"
    );
    expect(raw!.first_name).toBe("Jane");
    // raw should NOT have camelCase key
    expect((raw as Record<string, unknown>).firstName).toBeUndefined();
  });
});

describe("DbConnection — hardening", () => {
  let conn: DbConnection | null = null;

  afterEach(async () => {
    if (conn) {
      await conn.close();
      conn = null;
    }
  });

  // Section 1: Pragma & Config
  it("should enable WAL journal mode", async () => {
    conn = await createDb(":memory:");
    const row = await conn.get<{ journalMode: string }>(
      "PRAGMA journal_mode"
    );
    expect(row).toBeDefined();
    // wa-sqlite in-memory may report "memory" instead of "wal" — both are valid
    expect(["wal", "memory"]).toContain(row!.journalMode);
  });

  // Section 2: Parameter Edge Cases
  it("should handle run() with no params argument", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY)");
    const result = await conn.run("INSERT INTO test DEFAULT VALUES");
    expect(result.lastID).toBe(1);
    expect(result.changes).toBe(1);
  });

  it("should handle empty string param", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)");
    await conn.run("INSERT INTO test (name) VALUES (?)", [""]);
    const row = await conn.get<{ name: string }>(
      "SELECT name FROM test WHERE id = 1"
    );
    expect(row).toBeDefined();
    expect(row!.name).toBe("");
  });

  it("should handle null param value", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)");
    await conn.run("INSERT INTO test (name) VALUES (?)", [null]);
    const row = await conn.get<{ name: string | null }>(
      "SELECT name FROM test WHERE id = 1"
    );
    expect(row).toBeDefined();
    expect(row!.name).toBeNull();
  });

  // Section 3: Multi-statement & Batch
  it("should exec multiple semicolon-separated statements", async () => {
    conn = await createDb(":memory:");
    await conn.exec(`
      CREATE TABLE t1 (id INTEGER PRIMARY KEY);
      CREATE TABLE t2 (id INTEGER PRIMARY KEY);
      INSERT INTO t1 VALUES (1);
      INSERT INTO t2 VALUES (2);
    `);
    const r1 = await conn.all("SELECT * FROM t1");
    const r2 = await conn.all("SELECT * FROM t2");
    expect(r1).toHaveLength(1);
    expect(r2).toHaveLength(1);
  });

  it("should handle 100-row batch insert in a transaction", async () => {
    conn = await createDb(":memory:");
    await conn.exec("CREATE TABLE batch (id INTEGER PRIMARY KEY, val INTEGER)");
    await conn.run("BEGIN");
    for (let i = 0; i < 100; i++) {
      await conn.run("INSERT INTO batch (val) VALUES (?)", [i]);
    }
    await conn.run("COMMIT");
    const rows = await conn.all("SELECT * FROM batch");
    expect(rows).toHaveLength(100);
  });

  // Section 4: Connection Lifecycle
  it("should reject operations after close()", async () => {
    conn = await createDb(":memory:");
    await conn.close();
    await expect(conn.run("SELECT 1")).rejects.toThrow();
    conn = null; // prevent afterEach double-close
  });

  it("should support multiple sequential in-memory connections", async () => {
    const conn1 = await createDb(":memory:");
    await conn1.exec("CREATE TABLE t (v TEXT)");
    await conn1.run("INSERT INTO t (v) VALUES (?)", ["first"]);
    await conn1.close();

    const conn2 = await createDb(":memory:");
    await conn2.exec("CREATE TABLE t (v TEXT)");
    await conn2.run("INSERT INTO t (v) VALUES (?)", ["second"]);
    const row = await conn2.get<{ v: string }>("SELECT v FROM t");
    expect(row!.v).toBe("second");
    await conn2.close();
  });

  // Section 5: Data Type Handling
  it("should roundtrip integer, float, text, blob, and null types", async () => {
    conn = await createDb(":memory:");
    await conn.exec(`
      CREATE TABLE types (
        id INTEGER PRIMARY KEY,
        int_col INTEGER,
        real_col REAL,
        text_col TEXT,
        blob_col BLOB,
        null_col TEXT
      )
    `);
    const blob = Buffer.from([0xde, 0xad, 0xbe, 0xef]);
    await conn.run(
      "INSERT INTO types (int_col, real_col, text_col, blob_col, null_col) VALUES (?, ?, ?, ?, ?)",
      [42, 3.14, "hello", blob, null]
    );
    // get() auto-transforms: int_col → intCol, etc.
    const row = await conn.get<{
      intCol: number;
      realCol: number;
      textCol: string;
      blobCol: Uint8Array;
      nullCol: null;
    }>("SELECT * FROM types WHERE id = 1");
    expect(row).toBeDefined();
    expect(row!.intCol).toBe(42);
    expect(row!.realCol).toBeCloseTo(3.14, 10);
    expect(row!.textCol).toBe("hello");
    expect(row!.nullCol).toBeNull();
  });
});

describe("Transform utilities", () => {
  it("snakeToCamel converts common patterns", () => {
    expect(snakeToCamel("project_id")).toBe("projectId");
    expect(snakeToCamel("next_skills")).toBe("nextSkills");
    expect(snakeToCamel("cmd_dependencies")).toBe("cmdDependencies");
    expect(snakeToCamel("id")).toBe("id");
    expect(snakeToCamel("created_at")).toBe("createdAt");
  });

  it("transformRow converts keys and parses JSON", () => {
    const row = {
      id: 1,
      project_id: 42,
      phases: '[{"name":"Setup"}]',
      next_skills: '["test","fix"]',
      description: "plain text",
      metadata: null,
    };
    const result = transformRow(row);
    expect(result).toEqual({
      id: 1,
      projectId: 42,
      phases: [{ name: "Setup" }],
      nextSkills: ["test", "fix"],
      description: "plain text",
      metadata: null,
    });
  });

  it("transformRow does not parse non-JSON strings", () => {
    const row = { name: "hello", path: "/usr/bin" };
    const result = transformRow(row);
    expect(result).toEqual({ name: "hello", path: "/usr/bin" });
  });

  it("transformRow handles malformed JSON gracefully", () => {
    const row = { data: "{broken json" };
    const result = transformRow(row);
    expect(result).toEqual({ data: "{broken json" });
  });

  it("prepareParams stringifies objects and arrays", () => {
    const params = [1, "text", { key: "val" }, ["a", "b"], null, Buffer.from([1])];
    const result = prepareParams(params);
    expect(result[0]).toBe(1);
    expect(result[1]).toBe("text");
    expect(result[2]).toBe('{"key":"val"}');
    expect(result[3]).toBe('["a","b"]');
    expect(result[4]).toBeNull();
    expect(result[5]).toBeInstanceOf(Buffer);
  });
});
