/**
 * IDE-337 (ASKBRIEF, the app half): an ask's header may carry `brief:` (one link), and `proofs:` and
 * `reading:` (each a `;`-separated list of `[label](url-or-path)`). The app shows the brief as a
 * prominent link at the top of the ask and the two lists under the preamble. An entry that is not a
 * link is shown as plain text, never dropped. Per-fork `Evidence:` lines render inside their card.
 * The fields reach the client through the parser's unknown-header passthrough (format.ts parseHeader).
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAskFile } from "../src/lib/format.ts";
import { parseRef, refList } from "../src/client/askrefs.ts";
import { briefFor, proofLinks } from "../src/client/related.ts";

const head = (extra = "") =>
  `---\nid: b1\nto: operator\nfrom: idealic:kernel\nstatus: open\nrevision: 1\ncreated: 2026-11-04T10:00:00.000Z\n${extra}---\n\n`;
const PREAMBLE = "The kernel needs one ruling before the release.\n\n";
const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes, ship\n- [ ] [NO] No, hold\n";
const stored = (text: string) => ({ ...parseAskFile(text), seat: "idealic:kernel", file: "/x.md", mtimeMs: 0 });

async function render(ask: ReturnType<typeof stored>) {
  const { AskDetail } = await import("../src/client/App.tsx");
  return renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {}, onSent: () => {} }));
}

const ALL3 =
  "brief: [Release brief](https://proofs.example.com/proofs/brief.html)\n" +
  "proofs: [Gate run](https://proofs.example.com/proofs/gate.html); [Bench](http://127.0.0.1:9440/proofs/bench.html)\n" +
  "reading: [Design note](https://example.com/design); [Session log](/home/dev/sessions/X/LOG.md)\n";

describe("parsing one entry", () => {
  it("reads a markdown link, a bare URL, a path, and leaves anything else as text", () => {
    expect(parseRef("[Brief](https://x.test/b.html)")).toEqual({ label: "Brief", href: "https://x.test/b.html", kind: "url" });
    expect(parseRef(" https://x.test/b.html ")).toEqual({ label: "https://x.test/b.html", href: "https://x.test/b.html", kind: "url" });
    expect(parseRef("[Log](/home/dev/LOG.md)")).toEqual({ label: "Log", href: "/home/dev/LOG.md", kind: "path" });
    expect(parseRef("[Notes](sessions/X/NOTES.md)").kind).toBe("path");
    expect(parseRef("[Bad](javascript:alert(1))")).toEqual({ label: "[Bad](javascript:alert(1))", kind: "text" });
    expect(parseRef("[label(missing bracket")).toEqual({ label: "[label(missing bracket", kind: "text" });
    expect(parseRef("just words")).toEqual({ label: "just words", kind: "text" });
  });

  it("splits a list on `;` outside brackets, and drops only empty entries", () => {
    expect(refList("[a;b](https://x.test/1); [c](https://x.test/2;v=1) ;  ;").map((r) => r.label)).toEqual(["a;b", "c"]);
    expect(refList("[c](https://x.test/2;v=1)")[0]).toMatchObject({ kind: "url", href: "https://x.test/2;v=1" });
    expect(refList(undefined)).toEqual([]);
    expect(refList("   ")).toEqual([]);
    // Critique M1: an unclosed `[` BEFORE a complete link must not swallow that link.
    expect(refList("[broken; [Good](https://g.test)")).toEqual([
      { kind: "text", label: "[broken" },
      { kind: "url", label: "Good", href: "https://g.test" },
    ]);
    expect(refList("[half(https://x; [Good](https://g.test)").map((r) => [r.kind, r.label])).toEqual([
      ["text", "[half(https://x"],
      ["url", "Good"],
    ]);
  });

  it("briefFor reads the markdown form of brief: as the brief", () => {
    expect(briefFor(stored(head("brief: [Release brief](http://127.0.0.1:9440/proofs/b.html)\n") + BODY))).toEqual({ url: "http://127.0.0.1:9440/proofs/b.html", source: "brief" });
    // A brief that is a path cannot open in the pane, so the pane falls back as before.
    expect(briefFor(stored(head("brief: [Local](/home/dev/b.md)\n") + BODY))).toBeUndefined();
  });

  it("the related pane and the proof chips read the header's proofs and reading (critique S1)", () => {
    const ask = stored(head(ALL3.replace(/^brief:.*\n/, "")) + BODY);
    expect(proofLinks(ask)).toEqual([
      { url: "https://proofs.example.com/proofs/gate.html", label: "Gate run" },
      { url: "http://127.0.0.1:9440/proofs/bench.html", label: "Bench" },
    ]);
    // With no brief: the pane falls back to the first proof the header names.
    expect(briefFor(ask)).toEqual({ url: "https://proofs.example.com/proofs/gate.html", source: "first proof link" });
    // A proof page listed under reading: counts too; a non-proof page and a path do not.
    expect(proofLinks(stored(head("reading: [Note](https://example.com/n.html); [Log](/home/dev/LOG.md)\n") + BODY))).toEqual([
      { url: "https://example.com/n.html", label: "Note" },
    ]);
  });

  it("a URL named in the header and again in the body is one chip, not two", () => {
    const ask = stored(head("proofs: [Gate run](https://proofs.example.com/proofs/gate.html)\n") + "## ¶ASK_GO: Choose one: Ship it?\nEvidence: [gate again](https://proofs.example.com/proofs/gate.html)\n- [ ] [YES] Yes, ship\n- [ ] [NO] No, hold\n");
    expect(proofLinks(ask).map((p) => p.url)).toEqual(["https://proofs.example.com/proofs/gate.html"]);
  });
});

describe("the ask shows brief, proofs and reading", () => {
  it("a header with all three: the brief at the top, both lists after the preamble", async () => {
    const html = await render(stored(head(ALL3) + PREAMBLE + BODY));
    // The brief is a link in the ask head, before the first fork.
    const briefAt = html.indexOf('class="ask-brief"');
    expect(briefAt).toBeGreaterThan(-1);
    expect(briefAt).toBeLessThan(html.indexOf('class="fork"'));
    expect(html).toMatch(/class="ask-brief"[^]*?<a href="https:\/\/proofs\.example\.com\/proofs\/brief\.html"[^>]*>[^]*?Release brief<\/a>/);
    // The lists sit after the preamble, inside the first card.
    const pre = html.indexOf("The kernel needs one ruling");
    const refs = html.indexOf('class="ask-refs"');
    expect(pre).toBeGreaterThan(-1);
    expect(refs).toBeGreaterThan(pre);
    expect(html).toContain("Proofs</span>");
    expect(html).toContain("Reading</span>");
    expect(html).toMatch(/<a href="https:\/\/proofs\.example\.com\/proofs\/gate\.html"[^>]*>[^]*?Gate run<\/a>/);
    expect(html).toMatch(/<a href="http:\/\/127\.0\.0\.1:9440\/proofs\/bench\.html"[^>]*>[^]*?Bench<\/a>/);
    expect(html).toMatch(/<a href="https:\/\/example\.com\/design"[^>]*>[^]*?Design note<\/a>/);
    // A local path is shown with its path, and is not turned into a link the browser cannot follow.
    expect(html).toContain("Session log");
    expect(html).toContain("<code class=\"ic\">/home/dev/sessions/X/LOG.md</code>");
    expect(html).not.toContain('href="/home/dev/sessions/X/LOG.md"');
  });

  it("a header with none: nothing is rendered for them", async () => {
    const html = await render(stored(head() + PREAMBLE + BODY));
    expect(html).not.toContain("ask-brief");
    expect(html).not.toContain("ask-refs");
    expect(html).not.toContain("Reading</span>");
  });

  it("a malformed list entry is shown as plain text, not dropped", async () => {
    const html = await render(stored(head("reading: [Good](https://example.com/good); [half a link(https://example.com/x; plain words\n") + PREAMBLE + BODY));
    expect(html).toMatch(/<a href="https:\/\/example\.com\/good"[^>]*>[^]*?Good<\/a>/);
    expect(html).toContain("[half a link(https://example.com/x");
    expect(html).toContain("plain words");
    expect(html).not.toContain('href="https://example.com/x"');
  });

  it("a malformed brief is shown as plain text at the top, not dropped", async () => {
    const html = await render(stored(head("brief: see the release page\n") + BODY));
    expect(html).toMatch(/class="ask-brief"[^]*?see the release page/);
  });

  it("the lists show on the first card even when the ask has no preamble", async () => {
    const html = await render(stored(head("proofs: [Gate run](https://proofs.example.com/proofs/gate.html)\n") + BODY));
    expect(html).toContain('class="ask-refs"');
    expect(html.indexOf('class="ask-refs"')).toBeGreaterThan(html.indexOf('class="fork"'));
  });
});

describe("Evidence: lines render inside their fork card", () => {
  it("each fork's Evidence lines sit inside that fork's article, not another's", async () => {
    const two =
      "## ¶ASK_GO: Choose one: Ship it?\nEvidence: [gate log](https://example.com/gate)\nEvidence: the bench held at 41 ms\n- [ ] [YES] Yes\n- [ ] [NO] No\n\n" +
      "## ¶ASK_WHEN: Choose one: When?\nEvidence: the freeze starts Friday\n- [ ] [NOW] Now\n- [ ] [LATER] Later\n";
    const html = await render(stored(head() + two));
    const forks = html.split('<article class="fork"').slice(1);
    expect(forks).toHaveLength(2);
    expect(forks[0]).toMatch(/<details class="evidence"><summary>Evidence <span class="n">2<\/span>/);
    expect(forks[0]).toMatch(/<a href="https:\/\/example\.com\/gate"[^>]*>gate log<\/a>/);
    expect(forks[0]).toContain("the bench held at 41 ms");
    expect(forks[0]).not.toContain("the freeze starts Friday");
    expect(forks[1]).toMatch(/Evidence <span class="n">1<\/span>/);
    expect(forks[1]).toContain("the freeze starts Friday");
  });
});
