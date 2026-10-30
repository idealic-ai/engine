import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { answerAsk, listAsks, newAsk, resolveAskPath } from "../src/lib/store.ts";
import { parseAskFile, StaleRevisionError } from "../src/lib/format.ts";

let root: string;
let sessions: string;
beforeEach(() => {
  const base = fs.mkdtempSync(path.join("/tmp", "asks-"));
  root = path.join(base, "asks");
  sessions = path.join(base, "s");
  fs.mkdirSync(sessions, { recursive: true });
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

const BODY = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";

describe("newAsk", () => {
  it("writes <root>/<from>/<id>.md with an open header at revision 1", () => {
    const file = newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "a1", why: "w" }, BODY);
    expect(file).toBe(path.join(root, "idealic:kernel", "a1.md"));
    const ask = parseAskFile(fs.readFileSync(file, "utf8"));
    expect(ask.header).toMatchObject({ id: "a1", from: "idealic:kernel", to: "manager:idealic", status: "open", revision: "1", why: "w" });
    expect(ask.questions[0].askName).toBe("GO");
  });

  it("refuses to overwrite an existing ask", () => {
    newAsk(root, { from: "s", to: "t", id: "a1" }, BODY);
    expect(() => newAsk(root, { from: "s", to: "t", id: "a1" }, BODY)).toThrow(/exists/);
  });

  it("refuses a body with no decision-tree question", () => {
    expect(() => newAsk(root, { from: "s", to: "t", id: "a1" }, "just prose\n")).toThrow(/Choose/);
  });
});

describe("listAsks", () => {
  it("lists every ask across seats with its seat and path, and skips unreadable files", () => {
    newAsk(root, { from: "s1", to: "t", id: "a1" }, BODY);
    newAsk(root, { from: "s2", to: "t", id: "a2" }, BODY);
    fs.writeFileSync(path.join(root, "s2", "junk.md"), "no header here");
    const all = listAsks(root);
    expect(all.map((a) => `${a.seat}/${a.header.id}`).sort()).toEqual(["s1/a1", "s2/a2"]);
    expect(all[0].file).toMatch(/\.md$/);
  });

  it("returns an empty list when the root does not exist yet", () => {
    expect(listAsks(path.join(root, "nope"))).toEqual([]);
  });
});

describe("answerAsk", () => {
  it("writes the answer into the file and marks it undelivered when the asker has no live session", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a1" }, BODY);
    const res = await answerAsk(root, "idealic:kernel", "a1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { sessionsDir: sessions, expectedRevision: 1 });
    expect(res.delivery.status).toBe("undelivered");
    const ask = parseAskFile(fs.readFileSync(resolveAskPath(root, "idealic:kernel", "a1"), "utf8"));
    expect(ask.header.status).toBe("answered");
    expect(ask.header.delivery).toBe("undelivered");
    expect(ask.answer?.answers).toEqual({ GO: ["YES"] });
    expect(ask.answer?.answeredAt).toMatch(/^\d{4}-/);
  });

  it("pushes to the asking seat and marks the file delivered", async () => {
    const sock = path.join(sessions, "k.sock");
    const got: string[] = [];
    const srv = net.createServer((c) => c.on("data", (d) => got.push(d.toString())));
    await new Promise((r) => srv.listen(sock, () => r(null)));
    fs.writeFileSync(path.join(sessions, "1.json"), JSON.stringify({ pid: process.pid, name: "idealic:kernel", messagingSocketPath: sock }));
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a1" }, BODY);
    const res = await answerAsk(root, "idealic:kernel", "a1", { answers: { GO: ["NO"] }, answeredBy: "operator" }, { sessionsDir: sessions, expectedRevision: 1 });
    await new Promise((r) => setTimeout(r, 50));
    await new Promise((r) => srv.close(() => r(null)));
    expect(res.delivery.status).toBe("delivered");
    const text = got.join("");
    const content = JSON.parse(text.trim().split("\n").pop()!).message.content as string;
    // The socket carries no sender label, so the first line must name who answered and which ask.
    expect(content.split("\n")[0]).toBe("[ask-answer] from operator via ask-app: idealic:kernel/a1 is answered");
    expect(text).toContain("idealic:kernel/a1");
    // The push names the file (the record) and carries the answer's lines
    // exactly as a batch does (the operator's ruling), read back from the file just written.
    expect(content).toContain("revision 2");
    expect(content).toContain(res.file);
    expect(content).toContain("- Ship it? → No · idealic:kernel/a1#GO");
    expect(parseAskFile(fs.readFileSync(res.file, "utf8")).header.delivery).toBe("delivered");
  });

  it("refuses a seat or id that would escape the root", () => {
    expect(() => resolveAskPath(root, "../x", "a1")).toThrow(/invalid/);
    expect(() => resolveAskPath(root, "s", "../../etc")).toThrow(/invalid/);
  });
});

describe("answerAsk races and refusals", () => {
  async function fakeSeat() {
    const sock = path.join(sessions, "k.sock");
    const got: string[] = [];
    const srv = net.createServer((c) => c.on("data", (d) => got.push(d.toString())));
    await new Promise((r) => srv.listen(sock, () => r(null)));
    fs.writeFileSync(path.join(sessions, "1.json"), JSON.stringify({ pid: process.pid, name: "idealic:kernel", messagingSocketPath: sock }));
    return { got, close: () => new Promise((r) => srv.close(() => r(null))) };
  }

  it("lets exactly one of two concurrent answers win, and pushes only the winner", async () => {
    const seat = await fakeSeat();
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a1" }, BODY);
    const results = await Promise.allSettled([
      answerAsk(root, "idealic:kernel", "a1", { answers: { GO: ["YES"] }, answeredBy: "operator", note: "A" }, { sessionsDir: sessions, expectedRevision: 1 }),
      answerAsk(root, "idealic:kernel", "a1", { answers: { GO: ["NO"] }, answeredBy: "operator", note: "B" }, { sessionsDir: sessions, expectedRevision: 1 }),
    ]);
    await new Promise((r) => setTimeout(r, 80));
    await seat.close();
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    const lost = results.find((r) => r.status === "rejected") as PromiseRejectedResult;
    expect(lost.reason).toBeInstanceOf(StaleRevisionError);
    expect(seat.got.join("").match(/\[ask-answer\]/g)).toHaveLength(1);
    expect(parseAskFile(fs.readFileSync(resolveAskPath(root, "idealic:kernel", "a1"), "utf8")).header.revision).toBe("2");
  });

  it("refuses an empty answer and records nothing", async () => {
    newAsk(root, { from: "s", to: "t", id: "a1" }, BODY);
    await expect(answerAsk(root, "s", "a1", { answers: {}, answeredBy: "t" }, { sessionsDir: sessions, expectedRevision: 1 })).rejects.toThrow(/empty/);
    expect(parseAskFile(fs.readFileSync(resolveAskPath(root, "s", "a1"), "utf8")).header.status).toBe("open");
  });

  it("records a decline with its reason", async () => {
    newAsk(root, { from: "s", to: "t", id: "a1" }, BODY);
    const res = await answerAsk(root, "s", "a1", { declined: true, reason: "beyond my grant", answeredBy: "t" }, { sessionsDir: sessions, expectedRevision: 1 });
    const ask = parseAskFile(fs.readFileSync(res.file, "utf8"));
    expect(ask.header.status).toBe("declined");
    expect(ask.answer?.reason).toBe("beyond my grant");
  });
});
