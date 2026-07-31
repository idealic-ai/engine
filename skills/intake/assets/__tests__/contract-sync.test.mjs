/* Cross-file contract drift check — the mechanical answer to a failure this repo has already had.
 *
 * TEMPLATE_COUNCIL_BRIEF.md and council/SKILL.md describe the SAME contract from two sides, and
 * they had silently disagreed on two points (the panel-size list, and a "Wildcard seat" the skill
 * no longer has) before anyone read them together. The board's widget kit and its render spec are
 * the same hazard: the kit reads data-fb-* attributes a render agent only knows about because the
 * spec lists them, so an attribute added to one and not the other fails silently at render time.
 *
 * These are documentation-agreement checks, not behaviour tests — board-widgets.test.mjs covers
 * behaviour. Both matter; only this one catches a spec that quietly stopped describing the code.
 *
 * Run:  node ~/.claude/engine/skills/intake/assets/__tests__/contract-sync.test.mjs
 */
import assert from "node:assert";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const intake = path.join(here, "..");
const council = path.join(intake, "..", "..", "council");
const read = (p) => fs.readFileSync(p, "utf8");

const kitJs = read(path.join(intake, "board-widgets.js"));
const renderSpec = read(path.join(intake, "TEMPLATE_DECISION_BOARD_PROMPT.md"));
const intakeSkill = read(path.join(intake, "..", "SKILL.md"));
const schema = read(path.join(intake, "PAYLOAD_SCHEMA.md"));
const publishSh = read(path.join(intake, "..", "..", "prove", "assets", "publish-s3.sh"));
const publishKitSh = read(path.join(intake, "..", "..", "prove", "assets", "publish-kit.sh"));
const transport = read(path.join(intake, "..", "..", "prove", "assets", "STATE_TRANSPORT.md"));
const brief = read(path.join(council, "assets", "TEMPLATE_COUNCIL_BRIEF.md"));
const councilSkill = read(path.join(council, "SKILL.md"));
const personas = read(path.join(council, "personas", "INDEX.md"));

let checks = 0;
const check = (msg, fn) => { fn(); checks++; };

/* ---- 1. The Brief template and council/SKILL.md agree on the contract they both describe ---- */
check("brief_version agrees", () => {
  const tpl = /## Brief version — \*\*REQUIRED\*\*\n`(\d+)`/.exec(brief);
  const skl = /template revision the Brief was written against \(current: \*\*`(\d+)`\*\*\)/.exec(councilSkill);
  assert.ok(tpl && skl, "both files state a brief_version");
  assert.strictEqual(tpl[1], skl[1],
    `brief_version drift: template says ${tpl && tpl[1]}, SKILL.md says ${skl && skl[1]}`);
});

check("panel sizes agree", () => {
  const sizes = (s) => (/(\d(?: \| \d)+)/.exec(s) || [])[1];
  const tpl = sizes(/## Panel size[^\n]*\n<([^.]+)/.exec(brief)[1]);
  const skl = sizes(/\*\*Size\.\*\* Take it from the Brief or `--size`; default \*\*3\*\*; accept \*\*([^*]+)\*\*/.exec(councilSkill)[1]);
  assert.strictEqual(tpl, skl, `panel-size drift: template offers ${tpl}, SKILL.md accepts ${skl}`);
});

check("the removed Wildcard seat is gone from both", () => {
  assert.ok(!/Wildcard seat/i.test(brief), "template still references the removed Wildcard seat");
  assert.ok(!/Wildcard seat/i.test(councilSkill), "SKILL.md references a Wildcard seat");
});

check("report_path exists in the template SKILL.md tells callers to fill", () => {
  assert.ok(/## Report path/.test(brief), "template has no Report path field");
  assert.ok(/`report_path`/.test(councilSkill), "SKILL.md does not mention report_path");
});

check("the poll capability is described on both sides", () => {
  assert.ok(/## Poll \(ask the panel to VOTE/.test(brief), "template has no Poll section");
  assert.ok(/\*\*`poll`\*\*/.test(councilSkill), "SKILL.md's field contract omits poll");
  assert.ok(/`votes`/.test(councilSkill), "SKILL.md's verdict block omits votes");
});

/* ---- 2. Every attribute the kit READS is documented in the render spec ----
   A render agent emits markup from the spec alone. An attribute the kit reads but the spec
   never names is unreachable: the agent cannot know to emit it, and nothing errors. */
check("every data-fb-* the kit reads is documented in the render spec", () => {
  const used = new Set((kitJs.match(/data-fb-[a-z-]+/g) || []));
  const undocumented = [...used].filter((a) => !renderSpec.includes(a));
  assert.deepStrictEqual(undocumented, [],
    `the kit reads attributes the render spec never names — a render agent cannot emit them: ${undocumented.join(", ")}`);
});

/* ---- 3. Persona icons: present, unique, one per entry ----
   Two personas sharing an icon are indistinguishable on a board, which is precisely what the
   icon exists to prevent — so uniqueness is the property worth asserting, not presence. */
check("every persona carries a unique icon", () => {
  const entries = personas.split("\n").filter((l) => /^\*   .+ · \*\*/.test(l));
  assert.ok(entries.length >= 21, `expected the full roster, found ${entries.length} entries`);
  const icons = entries.map((l) => /^\*   (\S+) ·/.exec(l)[1]);
  assert.strictEqual(new Set(icons).size, icons.length,
    "two personas share an icon — they would be indistinguishable on a board");
  assert.ok(!/^\*   \*\*/m.test(personas), "an entry is missing its icon");
});

/* ---- 4. The ingest rule lives in exactly one place ----
   It used to be written out in full in both PAYLOAD_SCHEMA.md and intake/SKILL.md. */
check("the ingest rule is single-sourced in PAYLOAD_SCHEMA.md", () => {
  assert.ok(/## Ingestion \(orchestrator, Phase 6\)/.test(schema), "schema no longer owns the ingest rule");
  assert.ok(!/tally `selected` across voters/.test(intakeSkill),
    "intake/SKILL.md restates the ingest rule instead of pointing at PAYLOAD_SCHEMA.md");
  assert.ok(/PAYLOAD_SCHEMA\.md/.test(intakeSkill), "intake/SKILL.md does not point at the schema");
});

/* ---- 5. The mechanical-contract count agrees wherever it is stated ---- */
check("nothing still says there are two mechanical contracts", () => {
  for (const [name, src] of [["render spec", renderSpec], ["intake/SKILL.md", intakeSkill]]) {
    assert.ok(!/two mechanical contracts/.test(src), `${name} still says "two mechanical contracts" — there are three`);
  }
});

/* ---- 6. Both payload versions are documented, since ingest accepts both ---- */
check("v1 and v2 are both documented", () => {
  assert.ok(/## v2 — an event stream \(current\)/.test(schema), "v2 not documented");
  assert.ok(/## v1 — legacy, still accepted/.test(schema), "v1 dropped — ingest still accepts it");
  assert.ok(/actor/.test(schema) && /`actor\.kind` is the load-bearing field/.test(schema),
    "the schema does not explain why actor.kind is required");
});

/* ---- 7. Every kind any writer can produce is enumerated, and its scope is stated ----
   A v2 rewrite once dropped the `reader` class because the enum named only the kinds the
   board's own copy path emits. A fold then writes a kind the reader has never heard of. */
check("the reader class is enumerated and scoped", () => {
  assert.ok(/`human` \| `council` \| `reader`/.test(schema),
    "actor.kind does not enumerate all three kinds a writer can produce");
  assert.ok(/`reaction`/.test(schema), "the reaction event type is missing from the type enum");
  assert.ok(/Two scopes share one vocabulary/.test(schema),
    "the two-scopes section is missing — the enum alone does not say WHICH path emits what");
  assert.ok(/absent by design from a copy-back payload and real at the transport layer/.test(schema),
    "the schema does not state reader's scope explicitly, so 'is it a payload class' stays ambiguous");
});

/* ---- 8. The contributor filter names all three kinds ----
   It feeds the abandonment alarm. An unenumerated kind arriving here either inflates the
   human count or vanishes from every bucket; both break the one measure of the system dying. */
check("the contributor filter accounts for every kind", () => {
  const m = /The filter is `actor\.kind == "human"`[\s\S]{0,900}/.exec(schema);
  assert.ok(m, "the contributor-filter statement is missing");
  assert.ok(/`reader` is excluded too/.test(m[0]), "the filter does not say reader is excluded");
  assert.ok(/neither bucket/.test(m[0]), "the filter does not say reader belongs to neither bucket");
  assert.ok(/`council` is a machine and is excluded/.test(m[0]), "the filter does not exclude council explicitly");
});

/* ---- 9. The kit-reference token means the same thing on both sides ----
   The render agent writes the token; the publish step substitutes it. If they disagree, the
   substitution silently no-ops and every board ships with a dead kit reference — no error,
   the widgets just do nothing. The two files must literally agree on the string. */
check("the kit placeholder token agrees between spec and publish step", () => {
  const TOKEN = "__FB_KIT_BASE__";
  assert.ok(renderSpec.includes(TOKEN), "the render spec does not name the kit placeholder token");
  assert.ok(publishSh.includes(TOKEN), "publish-s3.sh does not substitute the token the spec tells agents to write");
  assert.ok(/sed .*__FB_KIT_BASE__/.test(publishSh), "publish-s3.sh names the token but never substitutes it");
});

/* ---- 10. The spec no longer instructs inlining ---- */
check("the render spec references the kit rather than inlining it", () => {
  assert.ok(!/inline \(CSP-safe\) the ENTIRE contents/.test(renderSpec),
    "the render spec still instructs inlining the kit");
  assert.ok(/Reference the shared widget kit — do NOT inline it/.test(renderSpec),
    "the reference-don't-inline contract is missing");
  assert.ok(/board-widgets\.v2\.js/.test(renderSpec), "the spec does not name the versioned kit file");
  assert.ok(!/Self-contained \+ CSP-safe/.test(renderSpec),
    "the spec still claims self-contained — a board now depends on its host");
});

/* ---- 11 (T1). The transport doc POINTS at the payload contract instead of restating it ----
   STATE_TRANSPORT.md carried its own copy of the event shape and a tally rule. The copy went
   stale — it still described a pre-v2 record while the contract had moved to actor.kind — and a
   stale copy is worse than no copy, because a reader who finds it stops looking. The fix is
   REMOVAL plus a pointer, never a correction: a corrected restatement is a restatement, and
   drifts again on the next revision. So this asserts the restatement is GONE, not that it agrees. */
check("STATE_TRANSPORT.md does not restate the payload shape", () => {
  assert.ok(!/class\s*:\s*"reader"/.test(transport),
    'STATE_TRANSPORT.md still restates a `class:"reader"` record — the contract is actor.kind, and this copy drifted once already');
  assert.ok(!/items\s*:\s*\[\s*\{/.test(transport),
    "STATE_TRANSPORT.md still restates the pre-v2 nested items[] shape");
  assert.ok(!/tallies by/.test(transport),
    "STATE_TRANSPORT.md still states a tally rule — the tally rule belongs to PAYLOAD_SCHEMA.md alone");
  assert.ok(/PAYLOAD_SCHEMA\.md/.test(transport),
    "STATE_TRANSPORT.md removed the shape but points nowhere — a reader now has no route to the contract");
});

check("STATE_TRANSPORT.md states the two facts the TRANSPORT actually owns", () => {
  assert.ok(/One event per object/i.test(transport),
    "the one-event-per-object rule is unstated — it is what makes N events N POSTs, and only the transport knows it");
  assert.ok(/append-only/i.test(transport) && /blind append/i.test(transport),
    "the doc does not say the fold is a blind append, so a reader cannot know duplicates are expected");
  assert.ok(/dedupe by `id`, then greatest-`ts` per `\(actor, item\)`/.test(transport),
    "the doc does not say the READER applies the rules — which is the whole reason the fold may stay blind");
});

/* ---- 12. The state-config placeholder means the same thing on both sides ----
   Same hazard as the kit token (check 9), one layer down: the render agent writes the
   placeholder, publish substitutes it. Disagree and the substitution silently no-ops, the board
   falls back to copy-back, and nothing errors — the multiplayer layer just never turns on. */
check("the state-config placeholder token agrees between spec and publish step", () => {
  const TOKEN = "__PROVE_STATE_CONFIG__";
  assert.ok(renderSpec.includes(TOKEN), "the render spec does not name the state-config placeholder token");
  assert.ok(publishSh.includes(TOKEN), "publish-s3.sh does not know the token the spec tells agents to write");
  /* Naming a token is not substituting it — check 9 already carries this lesson for the kit
     token. A publish step that merely mentions the token ships the raw placeholder, the board
     silently degrades to copy-back, and nothing anywhere errors. */
  assert.ok(new RegExp("replace\\(\"" + TOKEN + "\"").test(publishSh),
    "publish-s3.sh names the state-config token but never replaces it");
  assert.ok(/data-fb-state-config/.test(renderSpec),
    "the spec names the token but not the attribute the kit reads it through");
});

/* ---- 13. publish-kit.sh delivers every file the render spec tells a board to reference ----
   A spec line pointing at an object nothing publishes is a guaranteed 404 with no error anywhere. */
check("every kit file the render spec references is actually published", () => {
  /* Assert the UPLOAD, not a mention: publish-kit.sh naming a file in a comment while never
     copying it is exactly the state that produces a silent 404 on every board. */
  const uploads = publishKitSh.match(/aws s3 cp "\$kitDir\/[a-z.-]+"/g) || [];
  for (const f of ["board-widgets.js", "board-widgets.css", "proof-ticket.js"]) {
    assert.ok(uploads.includes(`aws s3 cp "$kitDir/${f}"`),
      `publish-kit.sh never uploads ${f} — a board referencing it 404s with nothing in any log`);
  }
  assert.ok(/board-widgets\.v\$\{ver\}\.js/.test(publishKitSh),
    "the board-widgets key is not version-stamped from the source's own SCHEMA_VERSION");
  assert.ok(/proof-ticket\.v\$\{ticketVer\}\.js/.test(publishKitSh),
    "proof-ticket.js is published at an unversioned key — a breaking change would overwrite every live board's copy");
  assert.ok(/proof-ticket\.v\d+\.js/.test(renderSpec),
    "the render spec does not name the versioned proof-ticket file it tells agents to reference");
});

console.log(`contract-sync.test: PASS — ${checks} cross-file checks `
  + "(brief_version, panel sizes, removed-Wildcard, report_path, poll on both sides, "
  + "kit attributes vs render spec, persona icon uniqueness, ingest single-sourcing, "
  + "contract count, v1+v2 both documented, reader enumerated+scoped, contributor filter complete, "
  + "kit-token agreement, spec references rather than inlines, transport doc points-not-restates, "
  + "transport owns one-event-per-object + blind-append, state-config token agreement, "
  + "every referenced kit file is published)");
