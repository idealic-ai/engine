import { useCallback, useEffect, useMemo, useState } from "react";
import {
  questionKey,
  visibleAsks,
  visibleQuestions,
  type AnswerMap,
  type AskOption,
  type AskQuestion,
  type ParsedAsk,
} from "../lib/format.ts";

type StoredAsk = ParsedAsk & { seat: string; file: string; mtimeMs: number };
type Tab = "open" | "answered" | "all";

const CONTEXT_FIELDS = ["why", "importance", "stakes", "context", "alternatives", "lean", "falsifier", "to", "from", "dependsOn", "revision", "created", "delivery", "deliveryNote"];

const valueOf = (o: AskOption) => o.code ?? o.label;
const askRef = (a: StoredAsk) => `${a.seat}/${a.header.id}`;

export function App() {
  const [root, setRoot] = useState("");
  const [asks, setAsks] = useState<StoredAsk[]>([]);
  const [tab, setTab] = useState<Tab>("open");
  const [selected, setSelected] = useState<string | undefined>();
  const [live, setLive] = useState(false);

  const load = useCallback(async () => {
    const r = await fetch("/api/asks");
    const j = await r.json();
    setRoot(j.root);
    setAsks(j.asks);
  }, []);

  useEffect(() => {
    load();
    const es = new EventSource("/api/events");
    es.addEventListener("hello", () => setLive(true));
    es.addEventListener("change", () => load());
    es.onerror = () => setLive(false);
    return () => es.close();
  }, [load]);

  const shown = useMemo(() => visibleAsks(asks), [asks]);
  const hiddenCount = asks.length - shown.length;
  const inTab = shown.filter((a) => tab === "all" || a.header.status === tab);
  const current = asks.find((a) => askRef(a) === selected) ?? inTab[0];

  return (
    <>
      <header className="top">
        <h1>Asks</h1>
        <div className="tabs" role="group" aria-label="Status">
          {(["open", "answered", "all"] as Tab[]).map((t) => (
            <button key={t} aria-pressed={tab === t} onClick={() => setTab(t)}>
              {t} ({t === "all" ? shown.length : shown.filter((a) => a.header.status === t).length})
            </button>
          ))}
        </div>
        <span className="badge">{live ? "live" : "offline"}</span>
        <span className="root">{root}</span>
      </header>
      <div className="layout">
        <nav className="list" aria-label="Asks">
          {inTab.length === 0 && <p className="hidden-note">No {tab === "all" ? "" : tab} asks.</p>}
          {inTab.map((a) => (
            <button key={askRef(a)} className="item" aria-current={current && askRef(a) === askRef(current)} onClick={() => setSelected(askRef(a))}>
              <div className="title">{a.questions[0]?.title ?? a.header.id}</div>
              <div className="ref">{askRef(a)} → {a.header.to}</div>
              <div>
                {a.header.importance && <span className={`badge ${a.header.importance === "high" ? "high" : ""}`}>{a.header.importance}</span>}
                <span className="badge">{a.header.status}</span>
                {a.header.delivery && <span className={`badge ${a.header.delivery}`}>{a.header.delivery}</span>}
              </div>
            </button>
          ))}
          {hiddenCount > 0 && <p className="hidden-note">{hiddenCount} ask(s) hidden until the ask they depend on is answered.</p>}
        </nav>
        <main className="detail">{current ? <AskDetail key={askRef(current) + current.header.revision} ask={current} all={asks} onAnswered={load} /> : <p>Nothing selected.</p>}</main>
      </div>
    </>
  );
}

function AskDetail({ ask, all, onAnswered }: { ask: StoredAsk; all: StoredAsk[]; onAnswered: () => void }) {
  const [sel, setSel] = useState<Record<string, string[]>>(() => {
    const init: Record<string, string[]> = {};
    for (const [k, v] of Object.entries(ask.answer?.answers ?? {})) if (Array.isArray(v)) init[k] = v;
    return init;
  });
  const [text, setText] = useState<Record<string, string>>({});
  const [note, setNote] = useState("");
  const [result, setResult] = useState<string>("");
  const [busy, setBusy] = useState(false);

  // Free text goes under `<key>.other`, never into the codes list. Only questions visible under the
  // answers so far are sent, repeated until stable, so a hidden dependent's stale pick is dropped.
  const collect = (qs: AskQuestion[]) => {
    const out: AnswerMap = {};
    ask.questions.forEach((q, i) => {
      if (!qs.includes(q)) return;
      const k = questionKey(q, i);
      if ((sel[k] ?? []).length) out[k] = sel[k];
      if (text[k]?.trim()) out[`${k}.other`] = text[k].trim();
    });
    return out;
  };
  let visible = visibleQuestions(ask.questions, {});
  let answers = collect(visible);
  for (let pass = 0; pass < ask.questions.length; pass++) {
    const next = visibleQuestions(ask.questions, answers);
    if (next.length === visible.length) break;
    visible = next;
    answers = collect(visible);
  }
  const dep = ask.header.dependsOn?.trim();
  const depMissing = dep && !all.some((a) => a.header.id === dep);
  const answerable = ask.header.status !== "superseded";

  async function submit(decline?: string) {
    setBusy(true);
    setResult("");
    try {
      const token = document.querySelector('meta[name="ask-token"]')?.getAttribute("content") ?? "";
      const payload = decline !== undefined ? { decline } : { answers };
      const r = await fetch("/api/answer", {
        method: "POST",
        headers: { "content-type": "application/json", "x-ask-token": token },
        body: JSON.stringify({ seat: ask.seat, id: ask.header.id, expectedRevision: Number(ask.header.revision), note: note || undefined, ...payload }),
      });
      const j = await r.json();
      if (r.status === 409) setResult(`Not written: someone answered first (now revision ${j.revision}). The list has refreshed; read their answer before answering again.`);
      else if (!r.ok) setResult(`Error: ${j.error}`);
      else setResult(j.delivery.status === "delivered" ? `Queued at ${ask.header.from} (it reads it when its current turn ends).` : `Saved, but undelivered (${j.delivery.reason}). The asker's /next picks it up from the file.`);
      onAnswered();
    } finally {
      setBusy(false);
    }
  }

  return (
    <article>
      <h2>{ask.questions[0]?.title ?? ask.header.id}</h2>
      <dl className="ctx">
        {CONTEXT_FIELDS.filter((f) => ask.header[f]).map((f) => (
          <div key={f} style={{ display: "contents" }}>
            <dt>{f}</dt>
            <dd>{ask.header[f]}</dd>
          </div>
        ))}
        <dt>file</dt>
        <dd><code>{ask.file}</code></dd>
      </dl>
      {depMissing && <p className="badge undelivered">depends on {dep}, which is not in this root</p>}
      {ask.preamble.trim() && <div className="preamble">{ask.preamble.trim()}</div>}

      {ask.questions.map((q, i) => {
        const k = questionKey(q, i);
        if (!visible.includes(q)) {
          return (
            <section className="q" key={k}>
              <h3>{q.title}</h3>
              <p className="waiting">Waiting on ASK_{q.dependsOn?.ask}{q.dependsOn?.code ? ` = ${q.dependsOn.code}` : ""}.</p>
            </section>
          );
        }
        return (
          <section className="q" key={k}>
            <h3>
              {q.title} <span className="mode">{q.multiSelect ? "choose any" : "choose one"} · {k}</span>
            </h3>
            <OptionTree q={q} options={q.options} picks={sel[k] ?? []} onChange={(p) => setSel({ ...sel, [k]: p })} />
            <input type="text" placeholder="Other / free text" value={text[k] ?? ""} onChange={(e) => setText({ ...text, [k]: e.target.value })} />
          </section>
        );
      })}

      {ask.answer && (
        <>
          <h3>Recorded answer</h3>
          <pre className="answer">{JSON.stringify(ask.answer, null, 2)}</pre>
        </>
      )}
      {answerable && (
        <section className="q">
          <h3>{ask.answer ? "Answer again" : "Answer"}</h3>
          <textarea rows={2} placeholder="Note to the asker (optional)" value={note} onChange={(e) => setNote(e.target.value)} />
          <p>
            <button className="btn primary" disabled={busy || Object.keys(answers).length === 0} onClick={() => submit()}>
              Write answer and push to {ask.header.from}
            </button>{" "}
            <button className="btn" disabled={busy || !note.trim()} title="Declining needs a reason: write it in the note" onClick={() => submit(note.trim())}>
              Decline (note is the reason)
            </button>
          </p>
          {result && <p className="result">{result}</p>}
        </section>
      )}
    </article>
  );
}

/** Collect every value in a subtree, so un-picking a branch also un-picks what was chosen under it. */
function subtreeValues(o: AskOption): string[] {
  return [valueOf(o), ...(o.children ?? []).flatMap(subtreeValues)];
}

function OptionTree({ q, options, picks, onChange }: { q: AskQuestion; options: AskOption[]; picks: string[]; onChange: (p: string[]) => void }) {
  return (
    <ul className="opts">
      {options.map((o) => {
        const v = valueOf(o);
        const on = picks.includes(v);
        const toggle = () => {
          if (q.multiSelect) {
            onChange(on ? picks.filter((p) => !subtreeValues(o).includes(p)) : [...picks, v]);
          } else {
            const siblings = options.flatMap(subtreeValues);
            onChange(on ? picks.filter((p) => !subtreeValues(o).includes(p)) : [...picks.filter((p) => !siblings.includes(p)), v]);
          }
        };
        return (
          <li className="opt" key={v}>
            <label>
              <input type={q.multiSelect ? "checkbox" : "radio"} checked={on} onChange={toggle} onClick={() => { if (on && !q.multiSelect) toggle(); }} />
              <span>
                {o.code && <code>[{o.code}] </code>}
                {o.label}
                {o.description && <div className="desc">{o.description}</div>}
              </span>
            </label>
            {on && o.children && <OptionTree q={q} options={o.children} picks={picks} onChange={onChange} />}
          </li>
        );
      })}
    </ul>
  );
}
