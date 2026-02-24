/**
 * Type-safety tests for the Registered interface + NamespaceOf.
 *
 * These tests verify that declare module augmentations on Registered
 * flow through NamespaceOf<"db"> into ctx.db.* with proper arg/return types.
 * If any resolve to `any`, these tests FAIL at compile time.
 */
import { describe, it, expectTypeOf } from "vitest";
import type { RpcContext } from "../context.js";
import type { Registered, ArgsOf, DataOf, NamespaceOf } from "../rpc-types.js";

// Import handler registrations so declare module augmentations are visible
import "engine-db/rpc/registry";

describe("Registered type map", () => {
  it("should have db.effort.start registered", () => {
    type HasKey = "db.effort.start" extends keyof Registered ? true : false;
    expectTypeOf<HasKey>().toEqualTypeOf<true>();
  });

  it("should have db.session.heartbeat registered", () => {
    type HasKey = "db.session.heartbeat" extends keyof Registered ? true : false;
    expectTypeOf<HasKey>().toEqualTypeOf<true>();
  });

  it("should have db.project.upsert registered", () => {
    type HasKey = "db.project.upsert" extends keyof Registered ? true : false;
    expectTypeOf<HasKey>().toEqualTypeOf<true>();
  });
});

describe("ArgsOf extracts typed args (not any)", () => {
  it("db.effort.start args should have taskId and skill", () => {
    type Args = ArgsOf<"db.effort.start">;
    expectTypeOf<Args>().toHaveProperty("taskId");
    expectTypeOf<Args>().toHaveProperty("skill");
    // Must NOT be any — if it were, this would pass for any string
    expectTypeOf<Args>().not.toBeAny();
  });

  it("db.project.upsert args should have path", () => {
    type Args = ArgsOf<"db.project.upsert">;
    expectTypeOf<Args>().toHaveProperty("path");
    expectTypeOf<Args>().not.toBeAny();
  });

  it("db.session.heartbeat args should have sessionId", () => {
    type Args = ArgsOf<"db.session.heartbeat">;
    expectTypeOf<Args>().toHaveProperty("sessionId");
    expectTypeOf<Args>().not.toBeAny();
  });
});

describe("DataOf extracts typed return data (not any)", () => {
  it("db.effort.start should return { effort: EffortRow }", () => {
    type Data = DataOf<"db.effort.start">;
    expectTypeOf<Data>().toHaveProperty("effort");
    expectTypeOf<Data>().not.toBeAny();
  });

  it("db.project.upsert should return { project: ... }", () => {
    type Data = DataOf<"db.project.upsert">;
    expectTypeOf<Data>().toHaveProperty("project");
    expectTypeOf<Data>().not.toBeAny();
  });
});

describe("NamespaceOf builds typed nested interface", () => {
  type DbNs = NamespaceOf<"db">;

  it("should have effort group", () => {
    expectTypeOf<DbNs>().toHaveProperty("effort");
  });

  it("should have session group", () => {
    expectTypeOf<DbNs>().toHaveProperty("session");
  });

  it("should have project group", () => {
    expectTypeOf<DbNs>().toHaveProperty("project");
  });

  it("effort.start should be a function", () => {
    type StartFn = DbNs["effort"]["start"];
    expectTypeOf<StartFn>().toBeFunction();
    // Return type should be a Promise (not any)
    expectTypeOf<StartFn>().returns.toBeObject();
    expectTypeOf<StartFn>().returns.not.toBeAny();
  });

  it("effort.start should accept typed args", () => {
    type StartFn = DbNs["effort"]["start"];
    // Parameter should have taskId
    expectTypeOf<StartFn>().parameter(0).toHaveProperty("taskId");
    expectTypeOf<StartFn>().parameter(0).not.toBeAny();
  });
});

describe("RpcContext.db has typed namespace methods", () => {
  it("ctx.db should not be any", () => {
    expectTypeOf<RpcContext["db"]>().not.toBeAny();
  });

  it("ctx.db.effort should exist and not be any", () => {
    expectTypeOf<RpcContext["db"]>().toHaveProperty("effort");
  });

  it("ctx.db.effort.start should be a callable function", () => {
    type Db = RpcContext["db"];
    type StartFn = Db["effort"]["start"];
    expectTypeOf<StartFn>().toBeFunction();
    expectTypeOf<StartFn>().parameter(0).not.toBeAny();
    expectTypeOf<StartFn>().returns.not.toBeAny();
  });

  it("ctx.db should also have raw DbConnection methods (get, run, all)", () => {
    type Db = RpcContext["db"];
    expectTypeOf<Db>().toHaveProperty("get");
    expectTypeOf<Db>().toHaveProperty("run");
    expectTypeOf<Db>().toHaveProperty("all");
  });
});
