/* Phase-gate teeth for the FIN-3577 unfakeable-gate fields.
 *
 * contract-sync.test.mjs proves the SPEC still describes the fields; this proves the ENGINE
 * still ENFORCES them. It drives `engine session phase` against a crafted minimal .state.json
 * and asserts that leaving Phase 5 (Outcomes) is REJECTED when the new declared proof fields are
 * absent and ACCEPTED when they are present — the in-session stand-in for the ticket's "run a
 * wave" falsifier (acceptance #2, #3; also asserts the Phase-3 triageAccounting gate, #1).
 *
 * The crafted phase carries steps:[]/commands:[] on purpose, to isolate the DECLARED-field
 * presence gate (the thing this ticket adds) from the unrelated §CMD_ step schemas the live
 * phase also merges in. Proof is delivered by file redirect, mirroring the heredoc the engine
 * expects (a piped spawn stdin does not reach the `engine` wrapper).
 *
 * Run:  node ~/.claude/engine/skills/intake/assets/__tests__/proof-gates.test.mjs
 */
import assert from "node:assert";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const skillMd = fs.readFileSync(path.join(here, "..", "..", "SKILL.md"), "utf8");

/* Read the proof arrays the running SKILL.md actually declares — don't hardcode, so this test
 * tracks the spec instead of drifting from it. */
const jsonBlock = /### Session Parameters\s*```json\s*([\s\S]*?)```/.exec(skillMd);
assert.ok(jsonBlock, "SKILL.md has a Session Parameters json block");
const params = JSON.parse(jsonBlock[1]);
const outcomes = params.phases.find((p) => p.name === "Outcomes");
const triage = params.phases.find((p) => p.name === "Triage");
assert.ok(outcomes && triage, "Outcomes + Triage phases exist");

/* The fields this ticket added/reshaped must be in their gates. */
for (const f of ["panelRun", "decisionBoard", "announce"]) {
  assert.ok(outcomes.proof.includes(f), `Outcomes proof array declares ${f}`);
}
assert.ok(triage.proof.includes("triageAccounting"), "Triage proof array declares triageAccounting");

/* --- Drive the real engine against a crafted state --- */
const root = fs.mkdtempSync(path.join(os.tmpdir(), "intake-gate-"));
const dir = path.join(root, "sessions", "scratch");
fs.mkdirSync(dir, { recursive: true });

const writeState = () =>
  fs.writeFileSync(path.join(dir, ".state.json"), JSON.stringify({
    skill: "intake",
    lifecycle: "active",
    currentPhase: "5: Outcomes",
    phaseHistory: [],
    phases: [
      // steps/commands emptied to isolate the declared-field presence gate
      { major: 5, minor: 0, name: "Outcomes", label: "5", steps: [], commands: [], proof: outcomes.proof },
      { major: 6, minor: 0, name: "Discussion", label: "6", steps: [], commands: [], proof: [] },
    ],
  }, null, 2));

const leaveOutcomes = (proofObj) => {
  writeState(); // reset currentPhase to Outcomes before each attempt
  const pf = path.join(root, "proof.json");
  // trailing newline REQUIRED: session.sh reads proof with `read -r -t 1`, which returns
  // failure (→ "no STDIN provided") on a file whose last line has no newline terminator.
  fs.writeFileSync(pf, JSON.stringify(proofObj) + "\n");
  return spawnSync("sh", ["-c", `engine session phase '${dir}' '6: Discussion' < '${pf}'`], { encoding: "utf8" });
};

let checks = 0;
const check = (msg, fn) => { fn(); checks++; };

/* A) A wave that ranked + disposed but published no board and fired no announce (the exact
 *    "board skipped / announce never fired" failure) CANNOT leave Phase 5. */
check("Phase 5 REJECTS a transition missing panelRun/decisionBoard/announce", () => {
  const r = leaveOutcomes({ logEntries: "x", dispositions: "y" });
  assert.notStrictEqual(r.status, 0, "transition should be rejected (non-zero exit)");
  for (const f of ["panelRun", "decisionBoard", "announce"]) {
    assert.ok(r.stderr.includes(f), `rejection names the missing field ${f}\n${r.stderr}`);
  }
});

/* B) The same wave, once every stage is recorded (a real pointer OR an explicit declared
 *    absence), leaves cleanly — the gate demands recording, not success. */
check("Phase 5 ACCEPTS once every declared field is recorded", () => {
  const r = leaveOutcomes({
    logEntries: "posted the update",
    dispositions: "3 graduated, 2 marinating",
    panelRun: "skipped: single-item decision list",
    decisionBoard: "published: https://s3/.../board.html docId=abc123",
    announce: "projectUpdate id=SU_1; slack ts=1785500543.870449",
  });
  assert.strictEqual(r.status, 0, `transition should succeed\n${r.stderr}`);
});

/* C) An empty value does not satisfy the gate — silence stays a failing state. */
check("Phase 5 REJECTS a blank decisionBoard value", () => {
  const r = leaveOutcomes({
    logEntries: "x", dispositions: "y", panelRun: "skipped: none",
    decisionBoard: "", announce: "slack ts=1",
  });
  assert.notStrictEqual(r.status, 0, "blank decisionBoard should be rejected");
});

fs.rmSync(root, { recursive: true, force: true });

console.log(`proof-gates.test: PASS — ${checks} gate checks (Phase-5 rejects silence + blanks, accepts recorded stages; Phase-3 triageAccounting declared)`);
