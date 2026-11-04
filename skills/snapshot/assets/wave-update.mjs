#!/usr/bin/env node
// wave-update.mjs — /snapshot's wave-end update renderer (pure: stdin JSON -> stdout JSON).
//
// Decides, without touching Linear, what /snapshot §3 [6]/[7] would post:
//   node wave-update.mjs health   < {gates, direction, blocked, mustFixOpen}
//   node wave-update.mjs project  < {wave, project, lane, existing[], since?, health?, unattended?, selfId?, confirmed?,
//                                     projectLevel?, bodyFile?}
//   node wave-update.mjs rollup   < {wave, initiative, manager, updates[], existing[], since?, overrides?, unattended?, confirmed?}
//
// Every decision — including a decline — exits 0 with {action, ...}. Malformed input exits 1.
// `existing` / `updates` are what get_status_updates returned, mapped to {id, body, health,
// createdAt, project?, url?}. "create" omits id, "edit" passes it, "decline" posts nothing.
// `projectLevel: true` (a --project run) lets the lane carry no ticket: it renders as the project's
// own section, "### Project · <name>", beside any ticket lanes. `bodyFile: <path>` (--body-file)
// makes the approved text in that file the whole body: the renderer reads the bytes itself, so no
// caller retypes them, normalises it (a BOM stripped, CRLF and a lone CR turned into LF, trailing
// whitespace at the end dropped; a file that is not a regular file, invalid UTF-8, or a body over
// 64 KiB as sent declines), appends only the wave marker, and still derives the health from the
// lane's signals. approvedSha256 is the hash of the file bytes as approved; sentBodySha256 is the
// hash of the body sent. `bodySha256` (--body-sha256) is the approver's hash: a mismatch declines,
// and an unattended run requires it, plus `allowedRoots` (the session directory) that the file's
// realpath must sit inside; "/", $HOME or a parent of it, and a repository toplevel are refused.
// A project-level lane with no signals of its own takes the worst health of this wave's posted
// lanes (healthSource "lanes"). That section is marked inherited and recomputed on every render,
// so a lane re-posting moves it. With a ticket, projectLevel is ignored and the ticket lane renders.
// Tests: engine/scripts/tests/test-snapshot-update-sh.sh.

import { readFileSync, realpathSync, writeSync, openSync, fstatSync, closeSync, existsSync } from "node:fs";
import { sep, join } from "node:path";
import { homedir } from "node:os";
import { createHash } from "node:crypto";

const HEALTHS = ["onTrack", "atRisk", "offTrack"];
const RANK = { onTrack: 0, atRisk: 1, offTrack: 2 };
const GATES = ["green", "red", "unrun", "none"];
const DIRECTIONS = ["aligned", "rescoped", "drifted"];
// A local path in a body sent to Linear is unreadable to everyone else and leaks the machine layout.
// Matched after whitespace, an opening bracket or quote (a markdown link target included), or
// after file:// (file:///Users/...). A URL path that merely contains /Users/ is not local.
const LOCAL_PATH = /(^|[\s(`'"]|file:\/\/)(\/Users\/|\/home\/|\/private\/|\/tmp\/|~\/)/;
const BODY_CAP = 64 * 1024; // bytes; an approved body above this declines before the confirm
const SIGNALS = ["gates", "direction", "blocked", "mustFixOpen"];
const LAPSE_PREFIX = "**Override lapsed:**";
const PROJECT_KEY = "Project"; // the section key of a --project run's own section
// An inherited project health (healthSource "lanes") is a copy of the lanes' worst, not a reading:
// its Health line carries this mark, it is left out of the worst-of, and every render rewrites it.
const INHERITED = "inherited from this wave's lanes";
const INHERITED_RE = new RegExp(`^Health: (onTrack|atRisk|offTrack) — ${INHERITED}\\b`, "m");
const OVERRIDE_RE = /^\*\*Health set to (onTrack|atRisk|offTrack) by the (.+?) manager \(was (onTrack|atRisk|offTrack)\):\*\* /;

// Written synchronously: process.stdout/stderr.write to a pipe is asynchronous, and process.exit()
// right after it cut anything larger than the pipe buffer (a 64 KiB body arrived as unparseable JSON).
const writeAll = (fd, text) => {
  const buf = Buffer.from(text, "utf8");
  for (let off = 0; off < buf.length;) {
    try { off += writeSync(fd, buf, off); } catch (e) { if (e.code !== "EAGAIN") throw e; }
  }
};
const die = (msg) => { writeAll(2, `wave-update: ${msg}\n`); process.exit(1); };
const out = (obj) => { writeAll(1, JSON.stringify(obj, null, 2) + "\n"); process.exit(0); };

// Worst of a set of healths. An empty or invalid set returns null, never an implicit onTrack.
function worst(hs) {
  if (!hs.length || hs.some((h) => !HEALTHS.includes(h))) return null;
  return hs.reduce((a, b) => (RANK[b] > RANK[a] ? b : a));
}
const marker = (wave) => `— wave ${wave}`;
const lastLine = (body) => String(body ?? "").trimEnd().split("\n").pop().trim();
const waveOf = (body) => { const m = lastLine(body).match(/^— wave (\S.*)$/); return m ? m[1] : null; };
const byCreated = (a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt) || String(a.id).localeCompare(String(b.id));

// Partition the caller's window into this wave's updates, other waves' (ignored, never a
// conflict), and unmarked ones (foreign). `since` (ISO) filters by createdAt.
function partition(list, wave, since) {
  const sinceMs = since ? Date.parse(since) : null;
  if (since && Number.isNaN(sinceMs)) die(`since ${JSON.stringify(since)} is not an ISO date`);
  const inWindow = (Array.isArray(list) ? list : []).filter((u) =>
    sinceMs === null || !u.createdAt || Date.parse(u.createdAt) >= sinceMs);
  return {
    ours: inWindow.filter((u) => waveOf(u.body) === wave),
    otherWaves: inWindow.filter((u) => waveOf(u.body) !== null && waveOf(u.body) !== wave),
    foreign: inWindow.filter((u) => waveOf(u.body) === null),
  };
}

// The health rule. Every signal is required in its exact vocabulary (the PART 5 template's);
// a missing or unknown one is underivable, never a default.
function deriveHealth(s = {}) {
  const bad = (name, v, want) => ({ health: "underivable", reason: `${name} signal is ${JSON.stringify(v ?? null)}, expected ${want}` });
  if (!GATES.includes(s.gates)) return bad("gates", s.gates, GATES.join("|"));
  if (!DIRECTIONS.includes(s.direction)) return bad("direction", s.direction, DIRECTIONS.join("|"));
  const blocked = s.blocked === true || s.blocked === "yes" ? true : s.blocked === false || s.blocked === "no" ? false : null;
  if (blocked === null) return bad("blocked", s.blocked, "yes|no");
  const mf = typeof s.mustFixOpen === "number" ? s.mustFixOpen
    : /^\d+$/.test(String(s.mustFixOpen ?? "")) ? Number(s.mustFixOpen) : NaN;
  if (!Number.isInteger(mf) || mf < 0) return bad("mustFixOpen", s.mustFixOpen, "a count >= 0");
  if (blocked) return { health: "offTrack", reason: "the ticket is blocked" };
  if (s.gates === "red") return { health: "offTrack", reason: "verification gates are red" };
  if (s.direction === "drifted") return { health: "offTrack", reason: "the work drifted from the ticket's intent" };
  if (s.gates === "unrun") return { health: "atRisk", reason: "verification gates were not run" };
  if (s.direction === "rescoped") return { health: "atRisk", reason: "the ticket was re-scoped" };
  if (mf > 0) return { health: "atRisk", reason: `${mf} critique MUST-FIX finding(s) still open` };
  return { health: "onTrack", reason: s.gates === "none" ? "aligned; no runnable gate for this work" : "gates green and aligned with the ticket" };
}

// Parse a project-update body: the lead line, keyed lane sections ("### KEY · title"), and the
// manager's override notes, which are their own block and never part of a lane section.
// Returns null when the body has text outside those parts (someone else's words, not ours to
// rewrite) or a lane section with no readable Health line.
function parseBody(body) {
  const lines = String(body).trimEnd().split("\n");
  if (lines.length && waveOf(lines[lines.length - 1]) !== null) lines.pop();
  const sections = [], overrides = [];
  let cur = null, sawLead = false;
  for (const line of lines) {
    const head = line.match(/^### (\S+)/);
    const ov = line.match(OVERRIDE_RE);
    if (head) { cur = { key: head[1], lines: [line] }; sections.push(cur); continue; }
    if (ov) { overrides.push({ health: ov[1], manager: ov[2], was: ov[3], line }); cur = null; continue; }
    if (line.startsWith(LAPSE_PREFIX)) { cur = null; continue; } // regenerated on every render
    if (cur) { cur.lines.push(line); continue; }
    if (!sawLead && /^\*\*(\d+ (ticket|project)s? |Project update ).*— health /.test(line)) { sawLead = true; continue; }
    if (line.trim() === "") continue;
    return null;
  }
  const parsed = sections.map((s) => {
    const text = s.lines.join("\n").trim();
    const hm = text.match(/^Health: (onTrack|atRisk|offTrack)\b/m);
    const inherited = s.key === PROJECT_KEY && INHERITED_RE.test(text);
    return { key: s.key, text, health: hm ? hm[1] : null, ...(inherited ? { inherited: true } : {}) };
  });
  if (!parsed.length || parsed.some((s) => !s.health)) return null;
  return { sections: parsed, overrides };
}

function renderLane(lane, health, reason, projectName) {
  if (projectName !== undefined) {
    // A --project run's own section: no ticket, so no state line.
    const parts = [`### ${PROJECT_KEY} · ${projectName}`];
    if (lane.tldr) parts.push(String(lane.tldr).trim());
    if (lane.commit) parts.push(`Commit: ${lane.commit}`);
    parts.push(`Health: ${health} — ${reason}`);
    return parts.join("\n");
  }
  const head = `### ${lane.ticket} · ${lane.title ?? ""}`.trimEnd();
  const move = lane.stateFrom && lane.stateTo && lane.stateFrom !== lane.stateTo
    ? `${lane.stateFrom} → ${lane.stateTo}` : `Status: ${lane.stateTo ?? lane.stateFrom ?? "unchanged"}`;
  const parts = [head, move];
  if (lane.tldr) parts.push(String(lane.tldr).trim());
  if (lane.commit) parts.push(`Commit: ${lane.commit}`);
  parts.push(`Health: ${health} — ${reason}`);
  return parts.join("\n");
}

// Assemble a project body. The LAST manager override stands only while the lanes are no worse
// than the health it ruled on (its recorded "was"): a manager who ruled on atRisk did not rule on
// red. While it stands, the field and the lead carry its health; once a lane is worse, it lapses,
// the lanes' worst posts, and a regenerated line says so. Every override note is carried forward
// (they stack, so the history of rulings stays readable); the lanes keep their own Health lines.
function renderProjectBody(wave, sectionsIn, overrides) {
  // S1 (round 2): an inherited section is not counted; it is re-stamped with the lanes' worst now.
  const counted = sectionsIn.filter((s) => !s.inherited);
  const lanesWorst = worst((counted.length ? counted : sectionsIn).map((s) => s.health));
  const sections = sectionsIn.map((s) => (s.inherited && lanesWorst
    ? { ...s, health: lanesWorst, text: s.text.replace(INHERITED_RE, `Health: ${lanesWorst} — ${INHERITED}`) } : s));
  const ov = overrides.length ? overrides[overrides.length - 1] : null;
  const stands = !!ov && RANK[lanesWorst] <= RANK[ov.was];
  const health = stands ? ov.health : lanesWorst;
  const n = sections.filter((s) => s.key !== PROJECT_KEY).length;
  const opening = n === 0 ? "Project update this round" : `${n} ticket${n === 1 ? "" : "s"} moved this round`;
  const lead = stands
    ? `**${opening} — health ${health}, set by the ${ov.manager} manager.**`
    : `**${opening} — health ${health}.**`;
  const parts = [lead, "", sections.map((s) => s.text).join("\n\n")];
  if (overrides.length) parts.push("", overrides.map((o) => o.line).join("\n"));
  if (ov && !stands) parts.push(`${LAPSE_PREFIX} a lane is now ${lanesWorst}, worse than the ${ov.was} the ${ov.manager} manager ruled on, so the project shows ${lanesWorst}.`);
  parts.push("", marker(wave));
  return { health, lanesWorst, overrideStands: stands, body: parts.join("\n") };
}

// S5: compare what would post now against what the confirm showed.
function driftFrom(confirmed, now) {
  if (!confirmed) return [];
  const keys = ["action", "id", "health"].filter((k) => (confirmed[k] ?? null) !== (now[k] ?? null));
  if (confirmed.body !== undefined && confirmed.body !== now.body) keys.push("body");
  return keys;
}
function finish(input, decision) {
  // RR-S1: the S4 repair (retire is non-empty, and only ever holds this run's own selfId) is a
  // mechanical merge of this run's own create into the earliest update, not a new choice, so it
  // is not held to the confirm's "create" — not even unattended.
  if (decision.retire && decision.retire.length) return out({ ...decision, repair: true });
  const drift = driftFrom(input.confirmed, decision);
  if (!drift.length) return out(decision);
  if (input.unattended) return out({ action: "decline", reason: `what would post differs from what was confirmed (${drift.join(", ")}); an unattended run does not post an unconfirmed write`, drift, wouldHavePosted: decision });
  return out({ ...decision, drift, reconfirm: true });
}

function project(input) {
  const { wave, project: proj, lane } = input;
  if (!wave || !proj) die("project mode needs wave and project");
  if (!lane || (!lane.ticket && input.projectLevel !== true)) die("project mode needs lane.ticket (or projectLevel: true)");
  // F5: a ticket lane is always the ticket's, even on a --project run for the ticket's own project.
  const projectLevel = input.projectLevel === true && !lane.ticket;
  const laneKey = projectLevel ? PROJECT_KEY : lane.ticket;

  let health, reason, healthSource;
  if (input.health !== undefined) {
    if (input.unattended) return out({ action: "decline", reason: "a chosen health is refused on an unattended (--yes) run; health must be derived" });
    if (!HEALTHS.includes(input.health)) return out({ action: "decline", reason: `chosen health ${JSON.stringify(input.health)} is not one of ${HEALTHS.join("|")}` });
    health = input.health; healthSource = "chosen";
    reason = input.healthReason ?? "set at the confirm";
  } else if (projectLevel && SIGNALS.every((k) => lane[k] === undefined)) {
    // F1: no signals of its own; the worst of this wave's lanes already posted for the project.
    const posted = postedLanesWorst(input);
    if (!posted) return out({ action: "decline", reason: "health could not be derived: the project-level run carries no signals of its own and no lane has posted for this wave in this project" });
    health = posted; healthSource = "lanes";
    reason = `${INHERITED}: the worst of them posted for the project, recomputed on every render`;
  } else {
    const d = deriveHealth(lane);
    if (d.health === "underivable") return out({ action: "decline", reason: `health could not be derived: ${d.reason}` });
    ({ health, reason } = d); healthSource = "derived";
  }
  if (input.bodyFile !== undefined) return approvedBody(input, { health, reason, healthSource });
  const laneText = renderLane(lane, health, reason, projectLevel ? proj : undefined);
  if (LOCAL_PATH.test(laneText)) return out({ action: "decline", reason: "the lane text carries a local file path; a project update must read cold, so remove it before posting" });

  const { ours, foreign, otherWaves } = partition(input.existing, wave, input.since);
  if (foreign.length && !ours.length) {
    const why = input.since
      ? `project ${proj} already carries an update since this wave began that has no wave marker (posted by /intake or by hand); the rule is one update per project per wave`
      : `project ${proj} carries an update with no wave marker in the default window, and with no wave start given (--wave <id>@<ISO start>) it cannot be told apart from this wave's`;
    return out({ action: "decline", reason: why, ids: foreign.map((u) => u.id) });
  }

  // S4: two of ours means a concurrent create slipped past the re-read. The earliest is
  // canonical; every one of ours merges into it, and this run retires only its own duplicate.
  let canonical = ours[0] ?? null; const retire = [], duplicates = [];
  let sources = ours;
  if (ours.length > 1) {
    if (ours.some((u) => !u.createdAt)) return out({ action: "decline", reason: `project ${proj} carries ${ours.length} updates for wave ${wave} and their order cannot be read (no createdAt)`, ids: ours.map((u) => u.id) });
    sources = [...ours].sort(byCreated);
    canonical = sources[0];
    for (const u of sources.slice(1)) (u.id === input.selfId ? retire : duplicates).push(u.id);
  }

  const sections = [], overrides = [];
  for (const u of sources) {
    const p = parseBody(u.body);
    if (!p) return out({ action: "decline", reason: `update ${u.id} on project ${proj} has text this renderer did not write, or a lane with no readable health; it will not be rewritten`, ids: [u.id] });
    for (const s of p.sections) { const i = sections.findIndex((x) => x.key === s.key); if (i >= 0) sections[i] = s; else sections.push(s); }
    overrides.push(...p.overrides);
  }
  const mine = { key: laneKey, text: laneText, health, ...(healthSource === "lanes" ? { inherited: true } : {}) };
  const idx = sections.findIndex((s) => s.key === laneKey);
  if (idx >= 0) sections[idx] = mine; else sections.push(mine);

  const r = renderProjectBody(wave, sections, overrides);
  return finish(input, {
    action: canonical ? "edit" : "create",
    ...(canonical ? { id: canonical.id } : {}),
    type: "project", project: proj, health: r.health, laneHealth: healthSource === "lanes" ? r.lanesWorst : health, lanesWorst: r.lanesWorst,
    overrideStands: r.overrideStands, healthSource, reason, body: r.body,
    ...(retire.length ? { retire } : {}), ...(duplicates.length ? { duplicates } : {}),
    ...(otherWaves.length ? { ignoredOtherWaves: otherWaves.map((u) => u.id) } : {}),
  });
}

// The worst health among the ticket lanes this wave already posted for the project (a previous
// project section is not a lane, so a manager never inherits from itself). Null when there are none.
function postedLanesWorst(input) {
  const { ours } = partition(input.existing, input.wave, input.since);
  const hs = [];
  for (const u of ours) {
    const p = parseBody(u.body);
    if (p) for (const sec of p.sections) if (sec.key !== PROJECT_KEY) hs.push(sec.health);
  }
  return worst(hs);
}

const sha256 = (buf) => createHash("sha256").update(buf).digest("hex");
const normalise = (text) => text.replace(/\r\n?/g, "\n");
const isInside = (p, root) => p === root || p.startsWith(root.endsWith(sep) ? root : root + sep);

// --body-file: the approved text is the body as written. Only trailing whitespace at the very end
// is dropped, and the wave marker is appended after a blank line (or kept, when the text already
// ends with this wave's). The health is the one project() derived, or chosen under a confirm.
function approvedBody(input, { health, reason, healthSource }) {
  const { wave, project: proj } = input;
  const file = String(input.bodyFile);
  let real;
  try { real = realpathSync(file); } catch (e) { die(`body file ${JSON.stringify(file)} cannot be read: ${e.code ?? e.message}`); }
  if (input.unattended) {
    // F2: unattended, the file must sit inside the session directory, after symlinks. Round 2 S2: a
    // root wide enough to hold secrets is refused outright — "/", $HOME or a parent of it, and a
    // repository toplevel (a directory holding .git), whose root keeps .env files beside the code.
    const roots = Array.isArray(input.allowedRoots) ? input.allowedRoots.filter(Boolean) : [];
    if (!roots.length) return out({ action: "decline", reason: "an unattended run reads a body file only inside the session directory, and no roots were given (allowedRoots)" });
    const realRoots = roots.map((r) => { try { return realpathSync(String(r)); } catch { return null; } }).filter(Boolean);
    let home = null; try { home = realpathSync(homedir()); } catch { /* no home: nothing to compare */ }
    for (const [i, r] of realRoots.entries()) {
      const kind = r === sep ? "the filesystem root"
        : home && isInside(home, r) ? "$HOME or a parent of it"
        : existsSync(join(r, ".git")) ? "a repository toplevel" : null;
      if (kind) return out({ action: "decline", reason: `allowedRoots[${i}] is ${kind}, which is refused as a root; an unattended run reads a body file only from the session directory` });
    }
    if (!realRoots.some((r) => isInside(real, r))) return out({ action: "decline", reason: `the body file resolves outside the session directory (${realRoots.length} root(s) checked); an unattended run does not post it` });
  }
  // N4 (round 2): fstat the opened file before reading it, so /dev/zero, a FIFO or a directory
  // declines instead of hanging or failing, and a file too large to send under the cap even after
  // CRLF halves it is declined unread.
  let raw, fd;
  try { fd = openSync(real, "r"); } catch (e) { die(`body file ${JSON.stringify(file)} cannot be read: ${e.code ?? e.message}`); }
  try {
    const st = fstatSync(fd);
    if (!st.isFile()) return out({ action: "decline", reason: "the body file is not a regular file" });
    if (st.size > 2 * BODY_CAP + 3) return out({ action: "decline", reason: `the approved body file is ${st.size} bytes, so its body would be over the 64 KiB cap as sent` });
    raw = readFileSync(fd);
  } catch (e) { die(`body file ${JSON.stringify(file)} cannot be read: ${e.code ?? e.message}`); }
  finally { try { closeSync(fd); } catch { /* already closed */ } }
  const approvedSha256 = sha256(raw);
  const given = input.bodySha256 == null ? null : String(input.bodySha256).trim().toLowerCase();
  if (given === null && input.unattended) return out({ action: "decline", reason: "an unattended run posts an approved body only with the approver's hash (--body-sha256 <hex>)", approvedSha256 });
  if (given !== null && given !== approvedSha256) return out({ action: "decline", reason: `the body file's sha256 ${approvedSha256} does not match the approved ${given}; the file changed since it was approved, or the wrong file was named`, approvedSha256 });
  let text;
  try { text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(raw); } catch { return out({ action: "decline", reason: "the approved body is not valid UTF-8", approvedSha256 }); }
  // TextDecoder strips a leading BOM with ignoreBOM false.
  let core = normalise(text).replace(/\s+$/, "");
  const carried = waveOf(core);
  if (carried !== null && carried !== wave) return out({ action: "decline", reason: `the approved body ends with the marker of wave ${carried}, not ${wave}; it was approved for another wave`, approvedSha256 });
  if (carried === wave) core = core.split("\n").slice(0, -1).join("\n").replace(/\s+$/, "");
  if (!core) return out({ action: "decline", reason: "the approved body is empty", approvedSha256 });
  if (LOCAL_PATH.test(core)) return out({ action: "decline", reason: "the approved body carries a local file path; a project update must read cold, and an approved body is posted as written, so fix the file and re-approve it", approvedSha256 });
  const body = `${core}\n\n${marker(wave)}`;
  // N3 (round 2): the cap counts the body as sent, the wave marker included, after normalisation.
  const sentBytes = Buffer.byteLength(body, "utf8");
  if (sentBytes > BODY_CAP) return out({ action: "decline", reason: `the approved body is ${sentBytes} bytes as sent, over the 64 KiB cap`, approvedSha256 });
  const sentBodySha256 = sha256(Buffer.from(body, "utf8"));

  const { ours, foreign, otherWaves } = partition(input.existing, wave, input.since);
  if (foreign.length && !ours.length) {
    const why = input.since
      ? `project ${proj} already carries an update since this wave began that has no wave marker (posted by /intake or by hand); the rule is one update per project per wave`
      : `project ${proj} carries an update with no wave marker in the default window, and with no wave start given (--wave <id>@<ISO start>) it cannot be told apart from this wave's`;
    return out({ action: "decline", reason: why, ids: foreign.map((u) => u.id), approvedSha256 });
  }
  if (ours.length > 1) return out({ action: "decline", reason: `project ${proj} carries ${ours.length} updates for wave ${wave}; an approved body will not pick one of them to replace`, ids: ours.map((u) => u.id), approvedSha256 });
  const existing = ours[0] ?? null;
  let replacesText = false;
  if (existing) {
    const theirs = normalise(String(existing.body ?? "")).trimEnd().split("\n").slice(0, -1).join("\n").replace(/\s+$/, "");
    if (theirs !== core) {
      if (input.unattended) return out({ action: "decline", reason: `update ${existing.id} already holds this wave's text for project ${proj}; an approved body would replace it, and an unattended run does not replace text nobody confirmed it may`, ids: [existing.id], approvedSha256 });
      replacesText = true;
    }
  }
  return finish(input, {
    action: existing ? "edit" : "create",
    ...(existing ? { id: existing.id } : {}),
    type: "project", project: proj, health, healthSource, reason, body, bodySource: "file", approvedSha256, sentBodySha256,
    ...(replacesText ? { replacesText: true } : {}),
    ...(otherWaves.length ? { ignoredOtherWaves: otherWaves.map((u) => u.id) } : {}),
  });
}

function rollup(input) {
  const { wave, initiative, manager } = input;
  if (!wave || !initiative || !manager) die("rollup mode needs wave, initiative and manager");
  const overrides = input.overrides ?? {};
  const updates = partition(input.updates, wave, input.since).ours;
  const unmatched = Object.keys(overrides).filter((p) => !updates.some((u) => u.project === p))
    .map((p) => `${p}: no wave ${wave} update for this project, so the override was not applied`);
  if (updates.length === 0) return out({ action: "decline", reason: `no project update was posted for wave ${wave} under ${initiative}; a roll-up is built only from posted updates`, edits: [], declined: unmatched });

  const badHealth = updates.filter((u) => !HEALTHS.includes(u.health));
  if (badHealth.length) return out({ action: "decline", reason: `update(s) ${badHealth.map((u) => u.id).join(", ")} carry no readable health; the roll-up will not guess one`, edits: [], declined: unmatched });
  const noUrl = updates.filter((u) => !u.url);
  if (noUrl.length) return out({ action: "decline", reason: `update(s) ${noUrl.map((u) => u.id).join(", ")} have no url, so the roll-up could not link its sources`, edits: [], declined: unmatched });

  const edits = [], declined = [...unmatched];
  const effective = updates.map((u) => {
    const o = overrides[u.project];
    if (!o) return { ...u };
    if (!HEALTHS.includes(o.health)) { declined.push(`${u.project}: override health ${JSON.stringify(o.health)} is invalid`); return { ...u }; }
    if (!o.reason) { declined.push(`${u.project}: an override needs a reason so it is visible in Linear`); return { ...u }; }
    if (o.health === u.health) return { ...u };
    const p = parseBody(u.body);
    if (!p) { declined.push(`${u.project}: update ${u.id} has text this renderer did not write; the override was not applied`); return { ...u }; }
    // "was" records the lanes' worst health the manager ruled on (for a first override this is
    // the field's value); the override lapses if the lanes later get worse than it (RR-M1).
    const ruledOn = worst(p.sections.map((s) => s.health));
    const note = `**Health set to ${o.health} by the ${manager} manager (was ${ruledOn}):** ${o.reason}`;
    const r = renderProjectBody(wave, p.sections, [...p.overrides, { health: o.health, manager, was: ruledOn, line: note }]);
    edits.push({ id: u.id, project: u.project, health: r.health, body: r.body });
    return { ...u, health: o.health, overriddenFrom: u.health };
  });

  const health = worst(effective.map((u) => u.health));
  const blocks = effective.map((u) => {
    const p = parseBody(u.body);
    const lanes = (p ? p.sections : []).map((s) => {
      const [head, ...rest] = s.text.split("\n");
      // renderLane order: a ticket section has its move line, then the TL;DR; a project section
      // (key Project) has no move line, so its TL;DR comes first. Then Commit/Health.
      const cand = (s.key === PROJECT_KEY ? rest[0] : rest[1]) ?? "";
      const summary = /^(Health|Commit):/.test(cand) ? "" : cand;
      return `- ${head.replace(/^### /, "")}${summary ? ` — ${summary}` : ""}`;
    });
    const ov = u.overriddenFrom ? ` (set by the ${manager} manager; worker proposed ${u.overriddenFrom})` : "";
    return [`**${u.project}** — ${u.health}${ov} · [update](${u.url})`, ...lanes].join("\n");
  });
  const n = effective.length;
  const lead = `**${n} project${n === 1 ? "" : "s"} reported this round — health ${health}.**`;
  const body = [lead, "", blocks.join("\n\n"), "", marker(wave)].join("\n");

  const existing = partition(input.existing, wave, input.since).ours;
  if (existing.length > 1) return out({ action: "decline", reason: `initiative ${initiative} already carries ${existing.length} roll-ups for wave ${wave}`, ids: existing.map((u) => u.id), edits, declined });
  return finish(input, {
    action: existing.length ? "edit" : "create",
    ...(existing.length ? { id: existing[0].id } : {}),
    type: "initiative", initiative, health, body, sources: effective.map((u) => u.id), edits, declined,
  });
}

const mode = process.argv[2];
if (!["health", "project", "rollup"].includes(mode)) die(`unknown mode ${JSON.stringify(mode)}; expected health|project|rollup`);
let input;
try { input = JSON.parse(readFileSync(0, "utf8")); } catch { die("stdin is not JSON"); }
if (mode === "health") out(deriveHealth(input));
if (mode === "project") project(input);
if (mode === "rollup") rollup(input);
