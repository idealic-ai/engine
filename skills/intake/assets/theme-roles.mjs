#!/usr/bin/env node
/* theme-roles.mjs — census + gate for the /prove theme token ROLE CONTRACT (theme-roles.json).
 *
 * WHAT IT ANSWERS: "what do we need to do with the prefixes, and is it automatable?"
 * The answer this prints is a three-way split of the convergence debt:
 *   prefix-strip owed  — mechanical, a sed away  (--nv-focus -> --focus)
 *   rename owed        — mechanical once the name is decided  (--ink-2 -> --ink-soft)
 *   NAME RULING owed   — NOT automatable; a human must pick the word  (absence, chrome ground, …)
 *
 * THREE INDEPENDENT CHECKS, deliberately kept apart because they fail for different reasons:
 *   1. CONTRACT SELF-CHECK — recomputes every role's tier and `canonicalBy` from the evidence and
 *      errors if theme-roles.json disagrees. This is the guard against grading by taste: the
 *      contract cannot declare a role `required` that only one theme built.
 *   2. DRIFT — every `spellings` entry is a recorded OBSERVATION, so it is re-derived from the
 *      files. If a theme no longer declares what the contract says it declares (or newly declares
 *      a canonical name the contract records as absent), the contract is stale and says so.
 *   3. COMPLIANCE — does each file satisfy the REQUIRED roles under the canonical name?
 *
 * EXIT CODES (deliberate):
 *   0  everything reconciles and every file carries every required role
 *   1  compliance: some file is MISSING a required role outright (a capability gap)
 *   2  drift: the contract's recorded observations no longer match the files (takes precedence —
 *      a lying contract makes every other number here untrustworthy)
 *   3  usage / unreadable input
 *   --report-only forces 0 while still printing everything, for wiring into a soft CI step.
 *
 * WHAT IS *NOT* AN EXIT FAILURE, on purpose: an alias or a prefix. Blocking on a spelling would
 * red every theme on day one for a cosmetic reason and the check would be disabled within a week.
 * Blocking on a MISSING role is different — that is a capability the page cannot render at all.
 *
 * EXTRACTOR LIMITS (a regex, not a CSS parser — no dependency, same as the house pattern):
 *   /(--[A-Za-z0-9_-]+)\s*:/ over the WHOLE file. It is scope-blind: a property declared only
 *   inside a @media/@supports block, only in an inline style="", or only inside a comment counts
 *   as declared. It does not read var() usages (no colon), so a token that is USED but never
 *   declared is correctly not counted. It cannot tell whether a declared token is ever consumed —
 *   reachability is not measured here.
 *
 * Run:  node ~/.claude/engine/skills/intake/assets/theme-roles.mjs [--frozen] [--report-only]
 *                                                                 [--sources <p>] [--contract <p>]
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DECL = /(--[A-Za-z0-9_-]+)\s*:([^;{}]*)/g;

export const expand = (p) => (p.startsWith("~/") ? path.join(os.homedir(), p.slice(2)) : p);

/**
 * Every custom property DECLARED WITH A NON-EMPTY VALUE anywhere in the source.
 * `--focus: ;` is legal CSS — it sets the token to the empty token stream, so every var(--focus)
 * resolves to nothing. It is a declaration that renders as an absence, which is precisely the
 * failure this contract exists to catch, so it does NOT count as satisfying a role. A name counts
 * if ANY of its declarations carries a value.
 * See EXTRACTOR LIMITS in the header for what this regex cannot see.
 */
export function declaredProps(src) {
  const out = new Set();
  for (const m of src.matchAll(DECL)) if (m[2].trim() !== "") out.add(m[1]);
  return out;
}

const CHAN = /--chan-([A-Za-z0-9]+)-(ink|ground|edge|weight)\s*:([^;{}]*)/g;

/**
 * The CHANNEL-ROLE answers a file makes, keyed by role id.
 * A channel class names a role; the --chan-<role>-* slots are the theme's answer to it. Last
 * declaration wins, which is the cascade's own rule for a single :root.
 */
export function channelAnswers(src) {
  const roles = new Map();
  for (const m of src.matchAll(CHAN)) {
    const [, role, slot, raw] = m;
    const val = raw.trim();
    if (val === "") continue;
    if (!roles.has(role)) roles.set(role, {});
    roles.get(role)[slot] = val;
  }
  return roles;
}

/**
 * Does an -edge answer DRAW? A border shorthand whose style is `none` or whose width is zero
 * paints nothing, so it is a declined slot rather than an answer — the same reasoning as
 * declaredProps refusing `--x: ;`. A declaration that renders as an absence is not an answer.
 */
export function edgeDraws(v) {
  if (!v) return false;
  const t = v.trim().toLowerCase();
  if (/(^|\s)none(\s|$)/.test(t)) return false;
  if (/(^|\s)0(px|em|rem|%)?(\s|$)/.test(t)) return false;
  return true;
}

/**
 * INV_DS_NON_COLOUR_CHANNEL, measured at the role seam rather than asserted from token presence:
 * a role class's theme answer must include at least one channel that survives grayscale(1).
 *
 * Only -edge counts. -ink and -ground are hue by construction. -weight is REFUSED on purpose:
 * the kit consumes the weight slot at 2 of its 8 channel sites, so a weight answer does not reach
 * the role everywhere the role renders, and a channel that appears in some hosts and not others
 * does not encode anything a reader can rely on.
 *
 * Deliberately STRUCTURAL, not photometric. A luminance threshold needs a number tied to a font
 * size the checker cannot see — the measured archetype pair sits at dL* 5.1, which is detectable
 * at 26px and unreadable at 10.5px, so one threshold cannot be right for both. Asking whether a
 * non-colour channel EXISTS has no magic number in it.
 *
 * A file declaring no --chan-* slots is not using this seam and is reported n/a, not failed.
 */
export function channelContract(src) {
  const answers = channelAnswers(src);
  const rows = [...answers.entries()].map(([role, slots]) => ({
    role,
    slots: Object.keys(slots).sort(),
    survives: edgeDraws(slots.edge),
    edge: slots.edge || null,
  }));
  rows.sort((a, b) => a.role.localeCompare(b.role));
  return rows;
}

export function tierOf(roleEvidence) {
  return roleEvidence >= 3 ? "required" : roleEvidence === 2 ? "emerging" : "proposed";
}

/** Recompute canonicalBy from the evidence alone — the anti-taste guard. */
export function canonicalByOf(role, graded) {
  if (role.kit) return "kit-incumbent";
  const spelled = graded.map((t) => role.spellings[t]).filter(Boolean);
  if (spelled.length === 1) return "sole-author";
  const counts = new Map();
  for (const s of spelled) counts.set(s, (counts.get(s) || 0) + 1);
  for (const [, n] of counts) if (n >= 2) return "theme-consensus";
  return "undecided";
}

export function expectedCanonical(role, graded) {
  const by = canonicalByOf(role, graded);
  if (by === "kit-incumbent") return role.kit;
  if (by === "sole-author") return graded.map((t) => role.spellings[t]).find(Boolean);
  if (by === "theme-consensus") {
    const counts = new Map();
    for (const t of graded) {
      const s = role.spellings[t];
      if (s) counts.set(s, (counts.get(s) || 0) + 1);
    }
    for (const [s, n] of counts) if (n >= 2) return s;
  }
  return null;
}

/** All token names ever observed for this role, across the kit and every graded theme. */
export function knownNames(role, graded) {
  const s = new Set();
  if (role.canonical) s.add(role.canonical);
  if (role.kit) s.add(role.kit);
  for (const t of graded) if (role.spellings[t]) s.add(role.spellings[t]);
  return [...s];
}

/**
 * Compliance of one file against one role.
 * satisfied > prefix-strip > alias > (missing | undecided-*). Only `missing` and
 * `undecided-absent` are capability gaps; the rest are spelling debt.
 */
export function statusFor(role, declared, prefix, graded) {
  const has = (n) => declared.has(n);
  const p = prefix || "";
  if (role.canonical) {
    if (has(role.canonical)) return { status: "satisfied", found: role.canonical };
    if (p && has(p + role.canonical.slice(2)))
      return { status: "prefix-strip", found: p + role.canonical.slice(2) };
  }
  for (const n of knownNames(role, graded)) {
    if (n === role.canonical) continue;
    if (has(n)) return { status: role.canonical ? "alias" : "undecided-present", found: n };
    if (p && has(p + n.slice(2)))
      return { status: role.canonical ? "alias" : "undecided-present", found: p + n.slice(2) };
  }
  return { status: role.canonical ? "missing" : "undecided-absent", found: null };
}

const GAP = new Set(["missing", "undecided-absent"]);

export function analyze({ contract, files, prefixes, graded }) {
  const errors = { self: [], drift: [] };
  const roles = contract.roles.map((role) => {
    const roleEvidence = graded.filter((t) => role.spellings[t]).length;
    const nameEvidence = graded.filter((t) => role.spellings[t] && role.spellings[t] === role.canonical).length;
    const by = canonicalByOf(role, graded);
    const canon = expectedCanonical(role, graded);
    if (role.canonicalBy !== by)
      errors.self.push(`${role.id}: canonicalBy is "${role.canonicalBy}", evidence says "${by}"`);
    if ((role.canonical || null) !== (canon || null))
      errors.self.push(`${role.id}: canonical is ${JSON.stringify(role.canonical)}, the ${by} rule says ${JSON.stringify(canon || null)}`);
    return { role, roleEvidence, nameEvidence, tier: tierOf(roleEvidence) };
  });

  const seen = new Set();
  for (const { role } of roles) {
    if (seen.has(role.id)) errors.self.push(`${role.id}: duplicate role id`);
    seen.add(role.id);
    for (const t of Object.keys(role.spellings))
      if (!graded.includes(t)) errors.self.push(`${role.id}: spellings has ungraded theme "${t}"`);
    for (const t of graded)
      if (!(t in role.spellings)) errors.self.push(`${role.id}: spellings is missing graded theme "${t}"`);
  }
  for (const m of contract.mandates)
    for (const id of m.satisfiedByAnyOf)
      if (!seen.has(id)) errors.self.push(`mandate ${m.id}: references unknown role "${id}"`);

  const report = {};
  for (const [name, { declared }] of Object.entries(files)) {
    const p = prefixes[name] || "";
    const rows = roles.map((r) => ({ ...r, ...statusFor(r.role, declared, p, graded) }));
    report[name] = rows;

    for (const { role } of roles) {
      // DRIFT — the contract's recorded observation, re-derived from this file.
      if (graded.includes(name)) {
        const rec = role.spellings[name];
        if (rec) {
          const want = p ? p + rec.slice(2) : rec;
          if (!declared.has(want))
            errors.drift.push(`${name}/${role.id}: contract records ${want}, file does not declare it`);
        } else if (role.canonical) {
          const gained = declared.has(role.canonical) ? role.canonical
            : p && declared.has(p + role.canonical.slice(2)) ? p + role.canonical.slice(2) : null;
          if (gained)
            errors.drift.push(`${name}/${role.id}: contract records NO token, file now declares ${gained} — role gained, update the contract`);
        }
      } else if (name === contract._incumbent) {
        if (role.kit && !declared.has(role.kit))
          errors.drift.push(`${name}/${role.id}: contract records ${role.kit}, file does not declare it`);
        if (!role.kit) {
          const gained = knownNames(role, graded).find((n) => declared.has(n));
          if (gained)
            errors.drift.push(`${name}/${role.id}: contract records the incumbent as LACKING this role, file now declares ${gained} — gap filled, update the contract`);
        }
      }
    }
  }

  const mandates = {};
  for (const name of Object.keys(files)) {
    mandates[name] = contract.mandates.map((m) => {
      const via = m.satisfiedByAnyOf.filter((id) => {
        const row = report[name].find((r) => r.role.id === id);
        return row && !GAP.has(row.status);
      });
      return { id: m.id, met: via.length > 0, via };
    });
  }

  return { roles, report, mandates, errors };
}

function parseArgv(argv) {
  const o = { flags: new Set() };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--") && argv[i + 1] && !argv[i + 1].startsWith("--")) o[a.slice(2)] = argv[++i];
    else if (a.startsWith("--")) o.flags.add(a.slice(2));
  }
  return o;
}

function main() {
  const opt = parseArgv(process.argv.slice(2));
  const srcPath = expand(opt.sources || path.join(HERE, "theme-roles.sources.json"));
  const conPath = expand(opt.contract || path.join(HERE, "theme-roles.json"));
  let sources, contract;
  try {
    sources = JSON.parse(fs.readFileSync(srcPath, "utf8"));
    contract = JSON.parse(fs.readFileSync(conPath, "utf8"));
  } catch (e) {
    console.error(`theme-roles: cannot read inputs — ${e.message}`);
    return 3;
  }

  const setName = opt.flags.has("frozen") ? "frozen" : "sources";
  const map = sources[setName];
  if (!map) { console.error(`theme-roles: sources json has no "${setName}" map`); return 3; }
  const graded = sources.graded || [];
  contract._incumbent = sources.incumbent;

  const files = {};
  for (const [name, rel] of Object.entries(map)) {
    const abs = expand(rel);
    let src;
    try { src = fs.readFileSync(abs, "utf8"); }
    catch (e) { console.error(`theme-roles: cannot read ${name} at ${abs} — ${e.message}`); return 3; }
    let mtime = null;
    try { mtime = fs.statSync(abs).mtime.toISOString().replace(/\.\d+Z$/, "Z"); } catch {}
    files[name] = { abs, mtime, declared: declaredProps(src), channels: channelContract(src) };
  }

  const { roles, report, mandates, errors } = analyze({ contract, files, prefixes: sources.prefix || {}, graded });

  const L = [];
  L.push(`THEME ROLE CONTRACT — census + gate     contract v${contract.version}  ·  source set: ${setName}`);
  // Caption what was ACTUALLY read, not what the contract was once measured against. The default
  // run reads the LIVE files on purpose (the difference between the two IS the drift signal), so
  // printing the frozen snapshot's description on a live run captions the run as something it is
  // not. Both facts are stated, kept apart, and every read file carries its own mtime.
  L.push(`contract measured against: ${contract.measuredAgainst}`);
  L.push(`this run read:             the "${setName}" set`
    + (setName === "frozen"
      ? " — the byte-copy snapshot, EXCEPT any entry that points at a live path (mtimes below)"
      : " — LIVE files as they stand now (mtimes below); they may differ from the snapshot above"));
  L.push("");
  L.push("CENSUS — declared custom properties (regex over whole file, scope-blind)");
  for (const [name, f] of Object.entries(files))
    L.push(`  ${name.padEnd(7)}${String(f.declared.size).padStart(4)}   ${(f.mtime || "mtime?").padEnd(21)}${f.abs.replace(os.homedir(), "~")}`);
  L.push("");

  const byTier = (t) => roles.filter((r) => r.tier === t);
  L.push(`CONTRACT — ${roles.length} roles · required ${byTier("required").length} (3/3 themes built one)`
    + ` · emerging ${byTier("emerging").length} (2/3) · proposed ${byTier("proposed").length} (<=1/3)`);
  L.push(`  self-check: ${errors.self.length ? `${errors.self.length} PROBLEM(S)` : "OK — every tier and canonical name re-derived from the evidence"}`);
  for (const e of errors.self) L.push(`    ✗ ${e}`);
  L.push("");
  L.push(`DRIFT — contract's recorded observations vs the files`);
  L.push(`  ${errors.drift.length ? `${errors.drift.length} DRIFTED` : `OK — ${roles.length} roles reconciled across ${Object.keys(files).length} files`}`);
  for (const e of errors.drift) L.push(`    ✗ ${e}`);
  L.push("");

  const gaps = [];
  L.push("COMPLIANCE — required roles only");
  for (const [name, rows] of Object.entries(report)) {
    const req = rows.filter((r) => r.tier === "required");
    const n = (s) => req.filter((r) => r.status === s).length;
    const miss = req.filter((r) => GAP.has(r.status));
    for (const r of miss) gaps.push(`${name}/${r.role.id}`);
    L.push(`  ${name.padEnd(7)} satisfied ${String(n("satisfied")).padStart(2)} · prefix-strip owed ${String(n("prefix-strip")).padStart(2)}`
      + ` · rename owed ${String(n("alias")).padStart(2)} · name-undecided-but-present ${String(n("undecided-present")).padStart(2)}`
      + ` · GAP ${String(miss.length).padStart(2)}`);
    for (const r of miss)
      L.push(`      ✗ GAP  ${r.role.id.padEnd(20)} ${r.role.canonical || "(name undecided)"} — ${r.role.what}`);
  }
  L.push("");

  L.push("MANDATES — the invariants the token layer must be able to express");
  for (const [name, ms] of Object.entries(mandates))
    for (const m of ms)
      L.push(`  ${name.padEnd(7)} ${m.id.padEnd(28)} ${m.met ? `MET     via ${m.via.join(", ")}` : "NOT MET"}`);
  L.push("");

  const hueOnly = [];
  L.push("CHANNEL CONTRACT — INV_DS_NON_COLOUR_CHANNEL, measured at the role seam");
  L.push("  a role class's theme answer must include at least one channel that survives grayscale(1)");
  for (const [name, f] of Object.entries(files)) {
    if (!f.channels.length) { L.push(`  ${name.padEnd(7)} n/a — declares no --chan-* role slots`); continue; }
    const bad = f.channels.filter((c) => !c.survives);
    for (const c of bad) hueOnly.push(`${name}/chan-${c.role}`);
    L.push(`  ${name.padEnd(7)} ${String(f.channels.length).padStart(2)} role(s) answered · `
      + `${String(f.channels.length - bad.length).padStart(2)} survive greyscale · ${String(bad.length).padStart(2)} HUE-ONLY`);
    for (const c of bad)
      L.push(`      ✗ HUE-ONLY  chan-${c.role.padEnd(14)} answered with ${c.slots.join("+")}`
        + `${c.edge ? ` · edge "${c.edge}" draws nothing` : " · no -edge answer"}`);
  }
  L.push("");

  const renames = [];
  const prefixes = [];
  for (const [name, rows] of Object.entries(report)) {
    for (const r of rows) {
      if (r.status === "prefix-strip") prefixes.push(`${name}: ${r.found} -> ${r.role.canonical}`);
      if (r.status === "alias") renames.push(`${name}: ${r.found} -> ${r.role.canonical}   (${r.role.id})`);
    }
  }
  L.push(`RENAME LEDGER — automatable (${prefixes.length} prefix strips, ${renames.length} renames)`);
  for (const r of prefixes) L.push(`    strip   ${r}`);
  for (const r of renames) L.push(`    rename  ${r}`);
  L.push("");

  const undecided = roles.filter((r) => r.role.canonicalBy === "undecided");
  L.push(`NAME RULINGS OWED — NOT automatable, a human must pick the word (${undecided.length})`);
  for (const { role, tier } of undecided)
    L.push(`  [${tier}] ${role.id.padEnd(20)} candidates: ${graded.map((t) => role.spellings[t]).filter(Boolean).join(" | ")}`);
  L.push("");

  const code = errors.self.length || errors.drift.length ? 2 : gaps.length || hueOnly.length ? 1 : 0;
  const verdict = code === 0 ? "PASS"
    : code === 2 ? `FAIL (contract is untrustworthy: ${errors.self.length} self-check + ${errors.drift.length} drift problem(s))`
    : `FAIL (${gaps.length} required-role gap(s)${gaps.length ? ": " + gaps.join(", ") : ""}`
      + `${hueOnly.length ? ` · ${hueOnly.length} hue-only channel role(s): ${hueOnly.join(", ")}` : ""})`;
  L.push(`VERDICT: ${verdict}`);
  if (opt.flags.has("report-only") && code !== 0) L.push(`  (--report-only: exiting 0 anyway)`);
  console.log(L.join("\n"));
  return opt.flags.has("report-only") ? 0 : code;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main());
