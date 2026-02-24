/**
 * RPC Type Infrastructure — typed handler registration via module augmentation.
 *
 * Registered: augmented per handler file with typeof handler.
 * ArgsOf/DataOf: extract args and return data from handler types.
 * NamespaceOf: builds nested method interface from Registered entries.
 */
import type { RpcError } from "./dispatch.js";

// ── Typed response ─────────────────────────────────────

/** Typed success response — narrows data to TData. */
export interface TypedRpcSuccess<TData = Record<string, unknown>> {
  ok: true;
  data: TData;
}

/** Handler return type — typed data on success, standard error on failure. */
export type TypedRpcResponse<TData = Record<string, unknown>> = TypedRpcSuccess<TData> | RpcError;

// ── Handler registration ───────────────────────────────

/**
 * Master handler registry — augmented per handler file via declaration merging.
 *
 * Each handler file adds:
 *   declare module "engine-shared/rpc-types" {
 *     interface Registered {
 *       "db.agents.get": typeof handler;
 *     }
 *   }
 */
// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export interface Registered {}

/** The type of any registered handler function. */
export type AnyHandler = (args: never, ctx: any) => TypedRpcResponse | Promise<TypedRpcResponse>;

// ── Type extraction helpers ────────────────────────────

/** Extract args type from a registered handler. */
export type ArgsOf<K extends keyof Registered> =
  Registered[K] extends (args: infer A, ctx: any) => unknown ? A : never;

/** Extract success data type from a registered handler's return type. */
export type DataOf<K extends keyof Registered> =
  Registered[K] extends (args: never, ctx: any) => Promise<infer R>
    ? R extends { ok: true; data: infer D } ? D : never
    : Registered[K] extends (args: never, ctx: any) => infer R
      ? R extends { ok: true; data: infer D } ? D : never
      : never;

// ── Namespace builder ──────────────────────────────────

/** Strip a prefix from a dotted key. "db.effort.start" → "effort.start" */
type StripPrefix<K extends string, P extends string> = K extends `${P}.${infer Rest}` ? Rest : never;

/** Extract first dot-segment. "effort.start" → "effort" */
type ExtractGroup<K extends string> = K extends `${infer G}.${string}` ? G : never;

/** Extract remainder after group. "effort.start" (group "effort") → "start" */
type ExtractMethod<K extends string, G extends string> = K extends `${G}.${infer M}` ? M : never;

/**
 * Build a nested namespace interface from Registered entries with a given prefix.
 *
 * NamespaceOf<"db"> converts registered "db.effort.start" handlers into:
 *   { effort: { start(args: A): Promise<D> } }
 */
export type NamespaceOf<Prefix extends string> = {
  [Group in ExtractGroup<StripPrefix<keyof Registered & string, Prefix>>]: {
    [Method in ExtractMethod<StripPrefix<keyof Registered & string, Prefix>, Group>]:
      `${Prefix}.${Group}.${Method}` extends keyof Registered
        ? (args: ArgsOf<`${Prefix}.${Group}.${Method}` & keyof Registered>) =>
            Promise<DataOf<`${Prefix}.${Group}.${Method}` & keyof Registered>>
        : never;
  };
};

/**
 * Build a flat namespace interface from Registered entries with a given prefix.
 *
 * FlatNamespaceOf<"search"> converts registered "search.query" handlers into:
 *   { query(args: A): Promise<D> }
 *
 * Use for 2-level command names (prefix.method).
 * Use NamespaceOf for 3-level command names (prefix.group.method).
 */
export type FlatNamespaceOf<Prefix extends string> = {
  [Method in StripPrefix<keyof Registered & string, Prefix>]:
    `${Prefix}.${Method}` extends keyof Registered
      ? (args: ArgsOf<`${Prefix}.${Method}` & keyof Registered>) =>
          Promise<DataOf<`${Prefix}.${Method}` & keyof Registered>>
      : never;
};

// ── Dynamic namespace derivation ───────────────────────

/** Extract unique first-dot-segment prefixes from all Registered keys. */
type ExtractPrefix<K extends string> = K extends `${infer P}.${string}` ? P : never;

/** All namespace prefixes derived from Registered. */
export type Prefixes = ExtractPrefix<keyof Registered & string>;

/** True if any key under prefix P has 3 levels (prefix.group.method). */
type HasNestedKeys<P extends string> =
  Extract<StripPrefix<keyof Registered & string, P>, `${string}.${string}`> extends never ? false : true;

/** Auto-select NamespaceOf (3-level) or FlatNamespaceOf (2-level) based on key depth. */
type AutoNamespace<P extends string> =
  HasNestedKeys<P> extends true ? NamespaceOf<P> : FlatNamespaceOf<P>;

/**
 * Override map for namespaces that need special treatment (e.g., db = DbConnection & NamespaceOf).
 * Augment via declaration merging in the owning package.
 */
// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export interface NamespaceOverrides {}

/** All namespaces derived from Registered — applies overrides where declared. */
export type AllNamespaces = {
  [P in Prefixes]: P extends keyof NamespaceOverrides ? NamespaceOverrides[P] : AutoNamespace<P>;
};

