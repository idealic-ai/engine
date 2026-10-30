/**
 * IDE-334 (RAGPROOFS): how a proof page becomes text, and how text becomes sections an embedding can hold.
 */
import { describe, expect, it } from "vitest";
import { chunkSections, htmlToText, MAX_CHUNK_CHARS, pageTitle, publishedSeat } from "../src/search/text.ts";

describe("htmlToText", () => {
  it("drops scripts, styles and tags, keeps h1-h3 as markdown headings, and decodes entities", () => {
    const html = `<!doctype html><html><head><title>RAG &amp; proofs</title><style>.x{color:red}</style>
      <script>var secret = "never indexed";</script></head><body>
      <h1 class="t">The <em>thesis</em></h1><p>Search &lt;works&gt; now&nbsp;here.</p>
      <h2>Evidence</h2><ul><li>one</li><li>two</li></ul><h4>small heading</h4><p>body&#39;s text &#x2014; done</p>
      <!-- a comment --><svg><text>chart label</text></svg></body></html>`;
    const text = htmlToText(html);
    expect(text).not.toContain("secret");
    expect(text).not.toContain("color:red");
    expect(text).not.toContain("a comment");
    expect(text).not.toContain("chart label");
    expect(text).not.toMatch(/<\/?(p|h1|h2|li|ul|em|body)\b/);
    expect(text).toMatch(/^# The thesis$/m);
    expect(text).toMatch(/^## Evidence$/m);
    expect(text).toContain("Search <works> now here.");
    expect(text).toContain("body's text — done");
    expect(text).toMatch(/one\s*\n\s*two/);
    expect(pageTitle(html)).toBe("RAG & proofs");
  });
});

describe("a published page and its builds/ copy", () => {
  it("strip to the same text: the publisher's seat strip is not page text, and it names the seat", () => {
    const page = "<html><head><title>T</title></head><body><h1>Claim</h1><p>the finding</p></body></html>";
    const published = page.replace("<body>", '<body><!--prove-seat-strip:begin-->\n<div class="prove-seat-strip" data-seat="meta:engine"><span>Published by <b>meta:engine</b></span></div>\n<!--prove-seat-strip:end-->');
    expect(htmlToText(published)).toBe(htmlToText(page));
    expect(htmlToText(published)).not.toContain("Published by");
    expect(publishedSeat(published)).toBe("meta:engine");
    expect(publishedSeat(page)).toBe("");
  });
});

describe("chunkSections", () => {
  it("splits on H1-H3 with breadcrumb titles, as doc-search does", () => {
    const text = `intro words that are long enough to stand on their own as a section of the page, more than a hundred characters.\n\n# Thesis\n${"a".repeat(150)}\n\n## Claim one\n${"b".repeat(150)}\n\n### Detail\n${"c".repeat(150)}\n\n# Scope\n${"d".repeat(150)}`;
    const chunks = chunkSections(text, "Page");
    expect(chunks.map((c) => c.section)).toEqual(["Page", "Page > Thesis", "Page > Thesis > Claim one", "Page > Thesis > Claim one > Detail", "Page > Scope"]);
    expect(chunks[2].content).toContain("Page > Thesis > Claim one");
    expect(chunks[2].content).toContain("b".repeat(150));
  });

  it("merges a section under 100 characters into the next one", () => {
    const chunks = chunkSections(`# A\nshort\n\n# B\n${"x".repeat(200)}`, "P");
    expect(chunks).toHaveLength(1);
    expect(chunks[0].content).toContain("short");
    expect(chunks[0].content).toContain("x".repeat(200));
  });

  it("caps a long section and splits it on paragraph boundaries into numbered parts", () => {
    const para = (n: number) => `paragraph ${n} ` + "word ".repeat(150);
    const body = Array.from({ length: 12 }, (_, i) => para(i)).join("\n\n");
    const chunks = chunkSections(`# Long\n${body}`, "P");
    expect(chunks.length).toBeGreaterThan(1);
    for (const c of chunks) expect(c.content.length).toBeLessThanOrEqual(MAX_CHUNK_CHARS + 200);
    expect(chunks[0].section).toBe("P > Long");
    expect(chunks[1].section).toBe("P > Long (part 2)");
    const all = chunks.map((c) => c.content).join("\n");
    for (let i = 0; i < 12; i++) expect(all).toContain(`paragraph ${i} `);
  });

  it("cuts a single paragraph longer than the cap rather than letting the model truncate it", () => {
    const chunks = chunkSections(`# One\n${"z".repeat(MAX_CHUNK_CHARS * 2 + 10)}`, "P");
    expect(chunks.length).toBe(3);
    expect(chunks.map((c) => c.content).join("").replace(/[^z]/g, "").length).toBe(MAX_CHUNK_CHARS * 2 + 10);
  });

  it("keeps section titles unique when a heading repeats", () => {
    const chunks = chunkSections(`# Same\n${"a".repeat(120)}\n\n# Same\n${"b".repeat(120)}`, "P");
    expect(chunks.map((c) => c.section)).toEqual(["P > Same", "P > Same (2)"]);
  });
});
