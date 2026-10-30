/* proof-highlight.js — the kit's code highlighter. PROOF_HIGHLIGHT_VERSION = 1
 *
 * Highlights every <pre><code class="language-X"> (or <pre class="language-X">) in the page, in the
 * browser, into hl-* spans that proof-highlight.css colours from the kit's palette tokens, so a
 * block follows the page's light and dark themes with no colours of its own.
 *
 * Why our own and not highlight.js: a proof page is deliberately self-contained. It loads no script
 * from anywhere (no CDN, no sibling object), and /prove-explore's page check runs it with the network
 * blocked. So the highlighter rides inline in the page's own bytes — publish-s3.sh injects this file
 * through skills/prove/assets/_fence-lang.py — and has to be small enough to carry on every page.
 * It is a tokeniser, not a parser: comments, strings, numbers, keywords, literals, calls, and for
 * markup the tags and attribute names. Good enough to read; never load-bearing for meaning.
 *
 * Left alone, deliberately:
 *   - language-text (and plaintext / txt / none / output / log): the author said "no language";
 *   - an unknown language: rendered as the plain text it is, never guessed at;
 *   - a block that already holds child elements: it was marked up by hand (the .codewrap .c/.k/.g
 *     spans in proof-blocks.css), and rewriting it would erase that marking. A block holding those
 *     kit colour spans is already highlighted, so _fence-lang.py's check counts it as tagged.
 *
 * Which <code> is a block: only one directly inside a <pre> (`pre > code`); the check agrees.
 *
 * Behaviour only: it injects no <style>. proof-highlight.css rides at this file's version.
 * In node, module.exports = { highlight, highlightElement } for the test harness.
 */
(function (root) {
  "use strict";

  // Every lookup table is a null-prototype map, so a language named "constructor" or "__proto__"
  // finds nothing rather than an Object.prototype member.
  function dict(o) {
    var m = Object.create(null);
    for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) m[k] = o[k];
    return m;
  }

  var PLAIN = dict({ text: 1, plaintext: 1, plain: 1, txt: 1, none: 1, nohighlight: 1, output: 1, log: 1 });

  function words(list) { return "\\b(?:" + list.split(" ").join("|") + ")\\b"; }

  var S_DQ = '"(?:\\\\.|[^"\\\\\\n])*"';
  var S_SQ = "'(?:\\\\.|[^'\\\\\\n])*'";
  var S_BT = "`(?:\\\\[\\s\\S]|[^`\\\\])*`";
  var NUM = "\\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\\d[\\d_]*(?:\\.\\d[\\d_]*)?(?:[eE][+-]?\\d+)?)n?\\b";
  var C_LINE = "//.*", C_BLOCK = "/\\*[\\s\\S]*?\\*/", C_HASH = "#.*";
  var CALL = "\\b[A-Za-z_$][\\w$]*(?=\\s*\\()";

  var JS_KW = "async await break case catch class const continue debugger default delete do else export " +
    "extends finally for from function if import in instanceof let new of return static super switch throw " +
    "try typeof var void while with yield as implements interface enum type namespace declare readonly " +
    "private protected public abstract keyof satisfies";
  var JS_LIT = "true false null undefined NaN Infinity this";

  // Each language: an ordered list of [class, regex source]. Order is precedence: the first rule that
  // matches at a position wins, so comments and strings come before anything they could contain.
  var L = Object.create(null);
  L.js = [["c", C_LINE], ["c", C_BLOCK], ["s", S_DQ], ["s", S_SQ], ["s", S_BT],
    ["k", words(JS_KW)], ["l", words(JS_LIT)], ["n", NUM], ["f", CALL]];
  L.json = [["a", S_DQ + '(?=\\s*:)'], ["s", S_DQ], ["l", words("true false null")], ["n", "-?" + NUM]];
  L.sh = [["c", "(?:^|\\s)#.*"], ["s", S_DQ], ["s", S_SQ],
    ["v", "\\$\\{[^}\\n]*\\}|\\$[A-Za-z_]\\w*|\\$[0-9@#?$!*-]"],
    ["k", words("if then else elif fi for while until do done case esac function in return local " +
      "export set unset shift break continue exit source declare readonly trap")],
    ["l", words("true false")], ["n", NUM]];
  L.py = [["c", C_HASH], ["s", '"""[\\s\\S]*?"""'], ["s", "'''[\\s\\S]*?'''"],
    ["s", "\\b[rbfuRBFU]{0,2}" + S_DQ], ["s", "\\b[rbfuRBFU]{0,2}" + S_SQ], ["f", "@[\\w.]+"],
    ["k", words("and as assert async await break class continue def del elif else except finally for " +
      "from global if import in is lambda nonlocal not or pass raise return try while with yield match case")],
    ["l", words("True False None self")], ["n", NUM], ["f", CALL]];
  L.css = [["c", C_BLOCK], ["s", S_DQ], ["s", S_SQ], ["k", "@[\\w-]+"], ["n", "#[0-9a-fA-F]{3,8}\\b"],
    ["a", "--?[A-Za-z][\\w-]*(?=\\s*:)"], ["n", "-?\\b\\d+(?:\\.\\d+)?(?:%|[a-z]+)?\\b"], ["f", "\\b[\\w-]+(?=\\()"]];
  // "<!-" + "-": the inlined script must never hold an HTML comment opener (see _fence-lang.py).
  L.html = [["c", "<!-" + "-[\\s\\S]*?-->"], ["t", "</?[A-Za-z][\\w:.-]*|/?>"], ["a", "\\s[A-Za-z_:@][\\w:.-]*(?==)"],
    ["s", S_DQ], ["s", S_SQ]];
  L.sql = [["c", "--.*"], ["c", C_BLOCK], ["s", S_SQ], ["a", S_DQ],
    ["k", words("select from where and or not insert into values update set delete create table " +
      "alter drop index view join left right inner outer full on group by order having limit offset as " +
      "distinct union all case when then else end begin commit rollback returning with exists in is like " +
      "between primary key references default constraint unique cascade")],
    ["l", words("null true false")], ["n", NUM], ["f", CALL]];
  L.yaml = [["c", "(?:^|\\s)#.*"], ["a", "^[ \\t]*(?:- )?[\\w./-]+(?=:(?:\\s|$))"], ["s", S_DQ], ["s", S_SQ],
    ["l", words("true false null yes no on off")], ["n", NUM]];
  L.diff = [["m", "^(?:diff|index|\\+\\+\\+|---) .*"], ["hunk", "^@@.*"], ["add", "^\\+.*"], ["del", "^-.*"]];
  function cLike(kw, lit) {
    return [["c", C_LINE], ["c", C_BLOCK], ["s", S_DQ], ["s", S_SQ], ["k", words(kw)], ["l", words(lit)],
      ["n", NUM], ["f", CALL]];
  }
  L.go = cLike("break case chan const continue default defer else fallthrough for func go goto if import " +
    "interface map package range return select struct switch type var", "true false nil iota");
  L.rust = cLike("as async await break const continue crate dyn else enum extern fn for if impl in let loop " +
    "match mod move mut pub ref return self Self static struct super trait type unsafe use where while",
    "true false None Some Ok Err");
  L.java = cLike("abstract break case catch class continue default do else enum extends final finally for if " +
    "implements import instanceof interface new package private protected public return static super switch " +
    "this throw throws try void while var record", "true false null");
  L.c = cLike("auto break case char const continue default do double else enum extern float for goto if int " +
    "long register return short signed sizeof static struct switch typedef union unsigned void volatile while " +
    "class namespace template typename public private protected virtual new delete using include define",
    "true false NULL nullptr");

  var ALIAS = dict({
    javascript: "js", mjs: "js", cjs: "js", jsx: "js", ts: "js", typescript: "js", tsx: "js", mts: "js",
    jsonc: "json", json5: "json",
    bash: "sh", shell: "sh", zsh: "sh", console: "sh", "shell-session": "sh", shellsession: "sh",
    python: "py", python3: "py",
    scss: "css", less: "css",
    xml: "html", svg: "html", xhtml: "html", vue: "html",
    postgres: "sql", postgresql: "sql", psql: "sql", sqlite: "sql", mysql: "sql",
    yml: "yaml", toml: "yaml",
    patch: "diff",
    golang: "go", rs: "rust", kotlin: "java", kt: "java", cpp: "c", "c++": "c", h: "c", hpp: "c", cs: "c", csharp: "c"
  });

  // Per-language regex flags beyond "gm": SQL keywords are case-insensitive.
  var FLAGS = dict({ sql: "i" });

  var compiled = Object.create(null);
  function rulesFor(lang) {
    var key = L[lang] ? lang : ALIAS[lang];
    if (!key || !L[key]) return null;
    if (!compiled[key]) {
      var rules = L[key];
      compiled[key] = {
        classes: rules.map(function (r) { return r[0]; }),
        re: new RegExp(rules.map(function (r) { return "(" + r[1] + ")"; }).join("|"), "gm" + (FLAGS[key] || ""))
      };
    }
    return compiled[key];
  }

  function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  // Returns highlighted HTML, or null when the block should stay as it is (text / unknown language).
  // The rule sources use only non-capturing groups, so capture group i+1 is rule i.
  function highlight(text, lang) {
    lang = String(lang || "").toLowerCase();
    if (!lang || PLAIN[lang]) return null;
    var R;
    try { R = rulesFor(lang); } catch (e) { return null; } // an engine without a regex feature: plain text
    if (!R) return null;
    var re = R.re, out = "", last = 0, m;
    re.lastIndex = 0;
    while ((m = re.exec(text)) !== null) {
      if (m[0] === "") { re.lastIndex++; continue; }
      var i = 1;
      while (i < m.length && m[i] === undefined) i++;
      out += esc(text.slice(last, m.index)) + '<span class="hl-' + R.classes[i - 1] + '">' + esc(m[0]) + "</span>";
      last = m.index + m[0].length;
    }
    return out + esc(text.slice(last));
  }

  var LANG_RE = /(?:^|\s)language-([A-Za-z0-9_+#.-]+)(?=\s|$)/;
  function langOf(el) {
    var m = LANG_RE.exec(el.className || "");
    if (!m && el.parentNode && el.parentNode.tagName === "PRE") m = LANG_RE.exec(el.parentNode.className || "");
    return m ? m[1].toLowerCase() : null;
  }

  function highlightElement(el) {
    if (!el || (el.dataset && el.dataset.hl)) return;
    if (el.children && el.children.length) return; // hand-marked: leave it
    var html = highlight(el.textContent || "", langOf(el));
    if (html === null) return;
    el.innerHTML = html;
    if (el.dataset) el.dataset.hl = "done";
  }

  function hasCodeChild(pre) {
    for (var c = pre.firstElementChild; c; c = c.nextElementSibling) if (c.tagName === "CODE") return true;
    return false;
  }

  function run(doc) {
    var els = doc.querySelectorAll('pre > code, pre[class*="language-"]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      // A <pre> carrying the language with a <code> directly inside: the <code> is the block,
      // handled itself. Only a direct child counts, as in _fence-lang.py's check.
      if (el.tagName === "PRE" && hasCodeChild(el)) continue;
      highlightElement(el);
    }
  }

  var api = { highlight: highlight, highlightElement: highlightElement, run: run, version: 1 };
  if (typeof module === "object" && module.exports) { module.exports = api; return; }
  root.ProofHighlight = api;
  if (root.document) {
    if (root.document.readyState === "loading") root.document.addEventListener("DOMContentLoaded", function () { run(root.document); });
    else run(root.document);
  }
})(typeof window !== "undefined" ? window : this);
