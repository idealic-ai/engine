import { Fragment, useCallback, useEffect, useMemo, useState } from "react";
import {
  answeredByText,
  cardFor,
  draftAuthor,
  questionKey,
  relayerOf,
  ticketKeys,
  visibleAsks,
  dependsOnDeclined,
  visibleQuestions,
  type AskAnswer,
  type AnswerMap,
  type AnswerValue,
  type AskOption,
  type AskQuestion,
  type Card,
  type ParsedAsk,
} from "../lib/format.ts";

type StoredAsk = ParsedAsk & { seat: string; file: string; mtimeMs: number };
type Tab = "open" | "drafts" | "settled" | "all";

const valueOf = (o: AskOption) => o.code ?? o.label;
const askRef = (a: StoredAsk) => `${a.seat}/${a.header.id}`;
const token = () => document.querySelector('meta[name="ask-token"]')?.getAttribute("content") ?? "";
/** React 18's DOM types predate the popover attributes; lowercase names pass straight to the DOM. */
const pop = (attrs: Record<string, string>) => attrs as Record<string, unknown>;
const settled = (a: StoredAsk) => a.header.status === "answered" || a.header.status === "declined";

async function post(url: string, body: unknown): Promise<{ status: number; json: any }> {
  const r = await fetch(url, { method: "POST", headers: { "content-type": "application/json", "x-ask-token": token() }, body: JSON.stringify(body) });
  return { status: r.status, json: await r.json().catch(() => ({})) };
}

export function App() {
  const [root, setRoot] = useState("");
  const [asks, setAsks] = useState<StoredAsk[]>([]);
  const [tab, setTab] = useState<Tab>("open");
  const [selected, setSelected] = useState<string | undefined>(() => decodeURIComponent(location.hash.slice(1)) || undefined);
  const [live, setLive] = useState(false);
  const [batchResult, setBatchResult] = useState("");
  const [sending, setSending] = useState(false);

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
  // S1: the tray holds the operator's own drafts; a seat's draft is sent by that seat.
  // Round 2: by its AUTHOR — a seat's relay draft says answeredBy operator but belongs to the relayer,
  // and the operator can neither send nor discard it.
  const drafts = trayDrafts(shown);
  const inTab = shown.filter((a) =>
    tab === "all" ? true : tab === "drafts" ? !!a.draft : tab === "settled" ? settled(a) : a.header.status === "open",
  );
  const current = asks.find((a) => askRef(a) === selected) ?? inTab[0];
  const count = (t: Tab) => (t === "all" ? shown.length : t === "drafts" ? drafts.length : t === "settled" ? shown.filter(settled).length : shown.filter((a) => a.header.status === "open").length);

  async function sendBatch() {
    setSending(true);
    setBatchResult("");
    try {
      // Refs only: the server reads every answer from its file.
      const { status, json } = await post("/api/send", { refs: drafts.map(askRef) });
      if (status !== 200) return setBatchResult(`Error: ${json.error}`);
      const pushes = (json.pushes as { seat: string; refs: string[]; delivery: { status: string; reason?: string } }[])
        .map((p) => `${p.seat}: ${p.delivery.status === "delivered" ? "queued, not read yet" : `${p.delivery.status}${p.delivery.reason ? ` (${p.delivery.reason})` : ""}`} — ${p.refs.length} answer${p.refs.length === 1 ? "" : "s"} in one message`)
        .join(" · ");
      const refused = (json.refused as { ref: string; error: string }[]).map((r) => `${r.ref}: ${r.error}`).join(" · ");
      setBatchResult(`Sent ${json.settled.length}. ${pushes}${refused ? ` · Refused: ${refused}` : ""}`);
      load();
    } finally {
      setSending(false);
    }
  }

  return (
    <>
      <header className="top">
        <h1>Asks</h1>
        <div className="tabs" role="group" aria-label="Status">
          {(["open", "drafts", "settled", "all"] as Tab[]).map((t) => (
            <button key={t} aria-pressed={tab === t} onClick={() => setTab(t)}>
              {t} ({count(t)})
            </button>
          ))}
        </div>
        <span className={`pill ${live ? "ok" : "warn"}`}>{live ? "live" : "offline"}</span>
        <span className="root">{root}</span>
      </header>
      {drafts.length > 0 && (
        <div className="tray" role="region" aria-label="Drafts ready to send">
          <span>
            <b>{drafts.length}</b> draft{drafts.length === 1 ? "" : "s"} saved in {drafts.length === 1 ? "its file" : "their files"}, not sent:{" "}
            {drafts.map((d) => (
              <button key={askRef(d)} className="linkish" onClick={() => setSelected(askRef(d))}>{askRef(d)}</button>
            ))}
          </span>
          <button className="btn primary" disabled={sending} onClick={sendBatch}>Send batch · one message per seat</button>
        </div>
      )}
      {batchResult && <p className="tray-result" role="status">{batchResult}</p>}
      <div className="layout">
        <nav className="list" aria-label="Asks">
          {inTab.length === 0 && <p className="hidden-note">No {tab === "all" ? "" : tab} asks.</p>}
          {inTab.map((a) => (
            <button key={askRef(a)} className="item" aria-current={current && askRef(a) === askRef(current)} onClick={() => setSelected(askRef(a))}>
              <div className="title">{a.questions[0]?.title ?? a.header.id}</div>
              <div className="ref">{askRef(a)} → {a.header.to}{a.questions.length > 1 ? ` · ${a.questions.length} questions` : ""}</div>
              <div className="chips">
                {a.header.importance && <span className={`pill ${a.header.importance === "high" ? "bad" : ""}`}>{a.header.importance}</span>}
                <span className="pill">{a.header.status}</span>
                {a.draft && <span className="pill warn">draft</span>}
                {a.header["reserved-for"] && <span className="pill bad">reserved · {a.header["reserved-for"]}</span>}
                {settled(a) && <LifeChip h={a.header} />}
              </div>
            </button>
          ))}
          {hiddenCount > 0 && <p className="hidden-note">{hiddenCount} ask(s) hidden until the ask they depend on is settled.</p>}
        </nav>
        <main className="detail">
          {current ? <AskDetail key={askRef(current) + current.header.revision} ask={current} all={asks} onChanged={load} /> : <p>Nothing selected.</p>}
        </main>
      </div>
    </>
  );
}

/** queued → read → acted. A delivered push is QUEUED; only `readAt` makes it read. */
function lifeStage(h: Record<string, string | undefined>): string {
  if (h.acted) return "acted";
  if (h.readAt) return "read";
  if (h.delivery === "delivered") return "queued";
  return h.delivery ?? "";
}
function LifeChip({ h }: { h: Record<string, string | undefined> }) {
  const s = lifeStage(h);
  if (!s) return null;
  return <span className={`pill ${s === "acted" || s === "read" ? "ok" : s === "queued" ? "" : "warn"}`}>{s}</span>;
}
function Life({ h }: { h: Record<string, string | undefined> }) {
  const steps: [string, boolean, string | undefined][] = [
    ["queued", h.delivery === "delivered" || !!h.readAt || !!h.acted, h.delivery === "delivered" ? "the seat's socket took it; that is not a read" : h.delivery ? `${h.delivery}${h.deliveryNote ? `: ${h.deliveryNote}` : ""}` : undefined],
    ["read", !!h.readAt, h.readAt ? `${h.readBy ?? ""} at ${h.readAt}` : "waiting for engine ask read"],
    ["acted", !!h.acted, h.acted ? `${h.acted}${h.actedAt ? ` (${h.actedAt})` : ""}` : undefined],
  ];
  return (
    <ol className="life" aria-label={`Answer state: ${lifeStage(h) || "not sent"}`}>
      {steps.map(([name, on, note]) => (
        <li key={name} className={on ? "on" : ""}>
          <b>{name}</b>
          {note && <span> · {note}</span>}
        </li>
      ))}
    </ol>
  );
}

type Values = Record<string, AnswerValue | undefined>;

/**
 * What the card starts filled with: the recorded answer, or the OPERATOR's own draft. A seat's draft
 * (MUST-2) is never shown as the operator's choice; the card says a seat holds one instead.
 */
export function initialValues(ask: ParsedAsk): { values: Values; text: Record<string, string>; note: string } {
  const own = ask.draft && draftAuthor(ask.draft) === "operator" ? ask.draft : undefined;
  const src = own ?? ask.answer;
  const values: Values = {};
  const text: Record<string, string> = {};
  for (const [k, v] of Object.entries(src?.answers ?? {})) {
    if (k.endsWith(".other")) text[k.slice(0, -6)] = String(v);
    else values[k] = v;
  }
  return { values, text, note: src?.note ?? "" };
}

const hasValue = (v: AnswerValue | undefined) =>
  v !== undefined && v !== "" && !(Array.isArray(v) && v.length === 0) && !(typeof v === "number" && Number.isNaN(v));

export function AskDetail({ ask, all, onChanged }: { ask: StoredAsk; all: StoredAsk[]; onChanged: () => void }) {
  const init = useMemo(() => initialValues(ask), [ask]);
  const [values, setValues] = useState<Values>(init.values);
  const [text, setText] = useState<Record<string, string>>(init.text);
  const [note, setNote] = useState(init.note);
  const [result, setResult] = useState("");
  const [busy, setBusy] = useState(false);

  // Only questions visible under the answers so far are sent, repeated until stable, so a hidden
  // dependent's stale pick is dropped. Free text goes under `<key>.other`.
  const collect = (qs: AskQuestion[]) => {
    const out: AnswerMap = {};
    ask.questions.forEach((q, i) => {
      if (!qs.includes(q)) return;
      const k = questionKey(q, i);
      if (hasValue(values[k])) out[k] = values[k] as AnswerValue;
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
  const depDeclined = dependsOnDeclined(ask, all);
  const open = ask.header.status === "open";

  async function act(kind: "draft" | "draft-decline" | "discard" | "send-now") {
    setBusy(true);
    setResult("");
    try {
      if (kind === "discard") {
        const r = await post("/api/discard", { seat: ask.seat, id: ask.header.id });
        setResult(r.status === 200 ? "Draft discarded." : `Error: ${r.json.error}`);
        return onChanged();
      }
      const base = { seat: ask.seat, id: ask.header.id, expectedRevision: Number(ask.header.revision), note: note || undefined };
      const body = kind === "draft-decline" ? { ...base, decline: note.trim() } : { ...base, answers };
      const r = await post("/api/draft", body);
      if (r.status === 409) return setResult(`Not saved: the ask moved (now revision ${r.json.revision}). Read the current state before answering again.`);
      if (r.status !== 200) return setResult(`Error: ${r.json.error}`);
      if (kind === "send-now") {
        const s = await post("/api/send", { refs: [askRef(ask)] });
        const p = s.json.pushes?.[0];
        if (s.json.refused?.length) setResult(`Refused: ${s.json.refused[0].error}`);
        else if (p) setResult(p.delivery.status === "delivered" ? `Queued at ${p.seat}, not read yet. It turns "read" when the seat runs engine ask read.` : `Saved, but ${p.delivery.status} (${p.delivery.reason ?? ""}). The asker's /next picks it up from the file.`);
      } else setResult("Draft saved in the file. Nothing has been sent: use Send batch at the top.");
      onChanged();
    } finally {
      setBusy(false);
    }
  }

  return (
    <article className="ask">
      {depMissing && <p className="pill warn">depends on {dep}, which is not in this root</p>}
      {depDeclined && <p className="pill warn">depends on {dep}, which was declined</p>}
      {ask.questions.map((q, i) => {
        const k = questionKey(q, i);
        return (
          <Fragment key={k}>
          <QuestionCard
            ask={ask}
            q={q}
            index={i}
            waiting={!visible.includes(q)}
            value={values[k]}
            onValue={(v) => setValues({ ...values, [k]: v })}
            note={text[k] ?? ""}
            onNote={(t) => setText({ ...text, [k]: t })}
            readOnly={!open}
          />
          {/* Prose written after a fork's options, before the next heading, sits between the cards. */}
          <ForkProse text={q.proseAfter} between />
          </Fragment>
        );
      })}

      <section className="answerbar">
        {settled(ask) && (
          <>
            <h3>{ask.header.status === "declined" ? "Declined" : "Answered"} · revision {ask.header.revision}</h3>
            <AnsweredBy answer={ask.answer} />
            <Life h={ask.header} />
            <details>
              <summary>Recorded answer block</summary>
              <pre className="answer">{JSON.stringify(ask.answer, null, 2)}</pre>
            </details>
          </>
        )}
        {open && (
          <>
            <textarea rows={2} className="fb-note" placeholder="Note to the asker (optional). To decline, write the reason here." value={note} onChange={(e) => setNote(e.target.value)} />
            <p className="actions">
              <button className="btn primary" disabled={busy || Object.keys(answers).length === 0} onClick={() => act("draft")}>{ask.draft ? "Update draft" : "Save draft"}</button>
              <button className="btn" disabled={busy || Object.keys(answers).length === 0} onClick={() => act("send-now")}>Send this one now</button>
              <button className="btn" disabled={busy || !note.trim()} title="Declining needs a reason: write it in the note" onClick={() => act("draft-decline")}>Draft a decline</button>
              {ask.draft && <button className="btn" disabled={busy} onClick={() => act("discard")}>Discard draft</button>}
            </p>
            {ask.draft && (
              <p className="hidden-note">
                {draftAuthor(ask.draft) === "operator"
                  ? <>Draft saved {ask.draft.savedAt} against revision {ask.draft.basedOn}{ask.draft.declined ? `, a decline: ${ask.draft.reason}` : ""}. Not sent.</>
                  : <>{draftAuthor(ask.draft)} holds an unsent draft here ({ask.draft.savedAt}); it is not shown as your choice. Saving your own draft replaces it.</>}
              </p>
            )}
          </>
        )}
        {result && <p className="result" role="status">{result}</p>}
        <AskDetails ask={ask} />
      </section>
    </article>
  );
}

function AskDetails({ ask }: { ask: StoredAsk }) {
  return (
    <details className="askmeta">
      <summary>Ask header and file</summary>
      <dl className="ctx">
        {Object.entries(ask.header).filter(([, v]) => v).map(([k, v]) => (
          <div key={k} style={{ display: "contents" }}>
            <dt>{k}</dt>
            <dd>{v}</dd>
          </div>
        ))}
        <dt>file</dt>
        <dd><code>{ask.file}</code></dd>
      </dl>
    </details>
  );
}

const OPTIONAL: [keyof Card, string][] = [
  ["confidence", "Confidence"], ["reversible", "Reversible"], ["verify", "Verify"], ["falsifier", "Falsifier"],
  ["ifUnanswered", "If unanswered"], ["neededBy", "Needed by"], ["blocks", "Blocks"], ["askedBy", "Asked by"],
];
const KIND_LABEL: Record<string, string> = { "choose-one": "choose one", choose: "choose any", rank: "rank all", text: "free text", number: "a number", date: "a date", yesno: "yes or no" };

function QuestionCard(p: {
  ask: StoredAsk; q: AskQuestion; index: number; waiting: boolean; readOnly: boolean;
  value: AnswerValue | undefined; onValue: (v: AnswerValue | undefined) => void; note: string; onNote: (t: string) => void;
}) {
  const { ask, q, index } = p;
  const card = cardFor(ask, index);
  const k = questionKey(q, index);
  const id = `${ask.header.id}-${k}`;
  const keys = index === 0 ? ticketKeys(ask) : [];
  const total = ask.questions.length;
  const eyebrow = `Q${index + 1}${card.rank ? ` · rank ${card.rank}` : total > 1 ? ` of ${total}` : ""}`;
  return (
    <article className="mod block" id={id} data-kind={q.kind}>
      <div className="mod-head">
        <span className="mod-title">
          <span className="mod-eyebrow">{eyebrow}</span>{" "}
          <span className="mod-slug">{card.topic ?? `${KIND_LABEL[q.kind]} · ${k}`}</span>
        </span>
        <span className="mod-aff" aria-label="Affordance rail">
          {(card.evidence.length > 0 || keys.length > 0) && (
            <span className="affgroup" role="group" aria-label="Block affordances">
              {card.evidence.length > 0 && (
                <button className="affseg" {...pop({ popovertarget: `ev-${id}` })} aria-label={`${card.evidence.length} evidence pieces`}>
                  <span className="segico" aria-hidden="true">📎</span><span className="seglab">Evidence</span>·<span className="segn">{card.evidence.length}</span>
                </button>
              )}
              {keys.length > 0 && (
                <span className="affseg tk" aria-label={`${keys.length} linked tickets`}>
                  <span className="segico" aria-hidden="true">🎫</span><span className="seglab">Tickets</span>·<span className="segn">{keys.length}</span>
                </span>
              )}
            </span>
          )}
          {card.reservedFor && <span className="pill bad" title="Only this party may answer; others may forward it">reserved · {card.reservedFor}</span>}
          <a className="aff mod-perma" href={`#${id}`} aria-label="Permalink to this question">¶</a>
        </span>
      </div>

      <div className="mod-body">
        <h3 className="fork-q">{q.title}</h3>
        {index === 0 && ask.preamble.trim() && <Prose text={ask.preamble.trim()} />}
        {card.context && <p>{card.context}</p>}
        <ForkProse text={q.prose} />
        {keys.length > 0 && <p className="tickets">{keys.map((t) => <TicketLink key={t} k={t} />)}</p>}
        {card.stake && (
          <div className="callout caution">
            <div className="ci">⚠</div>
            <div><div className="ctitle">At stake</div><div className="cbody">{card.stake}</div></div>
          </div>
        )}
        {card.unblocks && (
          <div className="callout insight">
            <div className="ci">◆</div>
            <div><div className="ctitle">Deciding this unblocks</div><div className="cbody">{card.unblocks}</div></div>
          </div>
        )}
        {OPTIONAL.some(([f]) => card[f]) && (
          <dl className="cardmeta">
            {OPTIONAL.filter(([f]) => card[f]).map(([f, label]) => (
              <div key={f}><dt>{label}</dt><dd>{card[f] as string}</dd></div>
            ))}
          </dl>
        )}
        {card.related && (
          <details>
            <summary>Related, not asked here</summary>
            <p>{card.related}</p>
          </details>
        )}

        {p.waiting ? (
          <p className="waiting">Waiting on ASK_{q.dependsOn?.ask}{q.dependsOn?.code ? ` = ${q.dependsOn.code}` : ""}.</p>
        ) : (
          <Input q={q} card={card} value={p.value} onValue={p.onValue} readOnly={p.readOnly} />
        )}
        {card.lean && !card.lean.code && (
          <p className="lean-line"><b>Lean:</b> “{card.lean.text}”{card.counter && <> <b>Strongest counter:</b> {card.counter}</>}</p>
        )}
        {q.panel.length > 0 && (
          <details className="panelread">
            <summary>Council panel read · {q.panel.length} lens{q.panel.length === 1 ? "" : "es"}</summary>
            <ul>
              {q.panel.map((r, i) => (
                <li key={i}><b>{r.lens}</b> → <span className="okey">{r.pick}</span> · {r.why}</li>
              ))}
            </ul>
          </details>
        )}
        {!p.waiting && (
          <textarea
            className="fb-note"
            rows={2}
            disabled={p.readOnly}
            placeholder={`Your note on Q${index + 1}: a different answer, a condition, or a question back. Optional.`}
            value={p.note}
            onChange={(e) => p.onNote(e.target.value)}
          />
        )}
      </div>

      <div className="mod-foot">
        <span><span className="fk">prov</span> <span className="fv">{card.provenance ?? `asked by ${card.askedBy ?? ask.header.from}`}</span></span>
        {card.asOf && <span><span className="fk">as-of</span> <span className="fv">{card.asOf}</span></span>}
        <span><span className="fk">ref</span> <span className="fv">{card.sourceRef ?? `${ask.seat}/${ask.header.id}#${k}`}</span></span>
        {q.dependsOn && <span><span className="fk">after</span> <span className="fv">ASK_{q.dependsOn.ask}{q.dependsOn.code ? `=${q.dependsOn.code}` : ""}</span></span>}
      </div>

      {card.evidence.length > 0 && (
        <div id={`ev-${id}`} {...pop({ popover: "auto" })} className="evpop" role="dialog" aria-label="Evidence for this question">
          <div className="evpop-head"><b>Evidence</b> <span className="cnt">{card.evidence.length} items</span>
            <button className="evpop-close" {...pop({ popovertarget: `ev-${id}`, popovertargetaction: "hide" })} aria-label="Close">✕</button></div>
          <ul className="evlist">
            {card.evidence.map((e, i) => (
              <li key={i} className="evrow"><span className="evtype src">source</span><div className="evbody">{e}</div></li>
            ))}
          </ul>
        </div>
      )}
    </article>
  );
}

function Prose({ text }: { text: string }) {
  return <>{text.split(/\n{2,}/).map((para, i) => <p key={i}>{para}</p>)}</>;
}

// ── inputs by kind ────────────────────────────────────────

function Input({ q, card, value, onValue, readOnly }: { q: AskQuestion; card: Card; value: AnswerValue | undefined; onValue: (v: AnswerValue | undefined) => void; readOnly: boolean }) {
  if (q.kind === "text") {
    return <textarea className="answer-text" rows={3} disabled={readOnly} placeholder="Your answer" value={typeof value === "string" ? value : ""} onChange={(e) => onValue(e.target.value)} />;
  }
  if (q.kind === "number") {
    const n = q.number ?? {};
    return (
      <p className="answer-num">
        <input type="number" disabled={readOnly} min={n.min} max={n.max} value={typeof value === "number" ? value : ""} onChange={(e) => onValue(e.target.value === "" ? undefined : Number(e.target.value))} />
        {n.unit && <span> {n.unit}</span>}
        {(n.min !== undefined || n.max !== undefined) && <span className="hidden-note"> between {n.min ?? "−∞"} and {n.max ?? "∞"}</span>}
      </p>
    );
  }
  if (q.kind === "date") {
    return <p><input type="date" disabled={readOnly} value={typeof value === "string" ? value : ""} onChange={(e) => onValue(e.target.value || undefined)} /></p>;
  }
  if (q.kind === "rank") return <RankInput q={q} card={card} value={Array.isArray(value) ? value : undefined} onValue={onValue} readOnly={readOnly} />;
  return <OptionTree q={q} card={card} options={q.options} picks={Array.isArray(value) ? value : []} onChange={(v) => onValue(v.length ? v : undefined)} readOnly={readOnly} />;
}

function OptionBody({ o, card, q }: { o: AskOption; card: Card; q: AskQuestion }) {
  const isLean = !!card.lean?.code && card.lean.code === o.code;
  const marks = q.panel.filter((r) => r.pick === o.code || r.pick === o.label);
  return (
    <span className="fb-opt-body">
      <span className="fb-opt-label">
        {o.code && <><span className="okey">{o.code}</span> · </>}
        {o.label}
        {isLean && <> <span className="pill ok lean-badge">lean</span></>}
      </span>
      {(o.description || o.cost || o.effort || o.blastRadius || isLean) && (
        <span className="fb-opt-desc">
          {o.description}
          {o.cost && <> <b>Cost:</b> {o.cost}</>}
          {(o.effort || o.blastRadius) && (
            <span className="optmeta">
              {o.effort && <span><b>Effort:</b> {o.effort}</span>}
              {o.blastRadius && <span><b>Blast radius:</b> {o.blastRadius}</span>}
            </span>
          )}
          {isLean && (
            <span className="lean-line">
              <b>Lean:</b> {o.code}, “{card.lean!.text}”{card.counter && <> <b>Strongest counter:</b> {card.counter}</>}
            </span>
          )}
        </span>
      )}
      {marks.length > 0 && (
        <span className="marks">
          {marks.map((m, i) => <span key={i} className="panel-mark">◆ <b>{m.lens}</b> picks this: {m.why}</span>)}
        </span>
      )}
    </span>
  );
}

/** Collect every value in a subtree, so un-picking a branch also un-picks what was chosen under it. */
function subtreeValues(o: AskOption): string[] {
  return [valueOf(o), ...(o.children ?? []).flatMap(subtreeValues)];
}

function OptionTree({ q, card, options, picks, onChange, readOnly }: { q: AskQuestion; card: Card; options: AskOption[]; picks: string[]; onChange: (p: string[]) => void; readOnly: boolean }) {
  return (
    <div className="fb-options">
      {options.map((o) => {
        const v = valueOf(o);
        const on = picks.includes(v);
        const toggle = () => {
          if (readOnly) return;
          if (q.multiSelect) onChange(on ? picks.filter((p) => !subtreeValues(o).includes(p)) : [...picks, v]);
          else {
            const siblings = options.flatMap(subtreeValues);
            onChange(on ? picks.filter((p) => !subtreeValues(o).includes(p)) : [...picks.filter((p) => !siblings.includes(p)), v]);
          }
        };
        return (
          <div key={v} className="optwrap">
            <label className="fb-opt">
              <input type={q.multiSelect ? "checkbox" : "radio"} disabled={readOnly} checked={on} onChange={toggle} onClick={() => { if (on && !q.multiSelect) toggle(); }} />
              <OptionBody o={o} card={card} q={q} />
            </label>
            {on && o.children && (
              <div className="nested">
                <OptionTree q={q} card={card} options={o.children} picks={picks} onChange={onChange} readOnly={readOnly} />
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function RankInput({ q, card, value, onValue, readOnly }: { q: AskQuestion; card: Card; value: string[] | undefined; onValue: (v: string[] | undefined) => void; readOnly: boolean }) {
  const order = value ?? q.options.map(valueOf);
  const move = (i: number, d: number) => {
    const next = [...order];
    const [x] = next.splice(i, 1);
    next.splice(i + d, 0, x);
    onValue(next);
  };
  return (
    <div className="rank">
      <ol className="fb-options">
        {order.map((v, i) => {
          const o = q.options.find((x) => valueOf(x) === v)!;
          return (
            <li key={v} className="fb-opt rank-row">
              <span className="rank-n">{i + 1}</span>
              <OptionBody o={o} card={card} q={q} />
              {!readOnly && (
                <span className="rank-btns">
                  <button className="btn" aria-label={`Move ${o.label} up`} disabled={i === 0} onClick={() => move(i, -1)}>↑</button>
                  <button className="btn" aria-label={`Move ${o.label} down`} disabled={i === order.length - 1} onClick={() => move(i, 1)}>↓</button>
                </span>
              )}
            </li>
          );
        })}
      </ol>
      {!readOnly && !value && <button className="btn" onClick={() => onValue(order)}>Use this order as my ranking</button>}
      {!readOnly && value && <p className="hidden-note">Ranking set. Move items to change it.</p>}
    </div>
  );
}

// ── linked tickets (the Linear key stays on the server) ──

type TicketInfo = { key: string; title: string; status: string; statusType: string; statusSince: string; assignee: string; summary: string; url: string };
const ticketCache = new Map<string, Promise<TicketInfo | { error: string }>>();
function loadTicket(k: string) {
  if (!ticketCache.has(k)) {
    ticketCache.set(
      k,
      fetch(`/api/ticket/${encodeURIComponent(k)}`, { headers: { "x-ask-token": token() } }).then(async (r) =>
        r.ok ? r.json() : { error: (await r.json().catch(() => ({}))).error ?? `HTTP ${r.status}` },
      ),
    );
  }
  return ticketCache.get(k)!;
}

function TicketLink({ k }: { k: string }) {
  const [info, setInfo] = useState<TicketInfo | { error: string } | undefined>();
  const [show, setShow] = useState(false);
  useEffect(() => {
    let live = true;
    loadTicket(k).then((i) => live && setInfo(i));
    return () => {
      live = false;
    };
  }, [k]);
  const t = info && "key" in info ? info : undefined;
  return (
    <span className="ticket" onMouseEnter={() => setShow(true)} onMouseLeave={() => setShow(false)} onFocus={() => setShow(true)} onBlur={() => setShow(false)}>
      <a href={safeHref(t?.url)} target="_blank" rel="noreferrer" tabIndex={0} aria-describedby={`tt-${k}`}>{k}</a>
      {t && <span className={`pill ${t.statusType === "completed" ? "ok" : t.statusType === "canceled" ? "bad" : t.statusType === "started" ? "warn" : ""}`}>{t.status}</span>}
      {show && info && (
        <span className="tooltip" role="tooltip" id={`tt-${k}`}>
          {t ? (
            <>
              <b>{t.key} · {t.title}</b>
              <span>{t.status} since {t.statusSince.slice(0, 10)} · {t.assignee}</span>
              {t.summary && <span className="tt-sum">{t.summary}</span>}
            </>
          ) : (
            <span>{k}: {(info as { error: string }).error}</span>
          )}
        </span>
      )}
    </span>
  );
}

/** N3: a ticket link is followed only when it is https; anything else (javascript:, data:) is dropped. */
function safeHref(url: string | undefined): string | undefined {
  return url && /^https:\/\//i.test(url) ? url : undefined;
}

/**
 * Who answered, with a relay made visible: an answer a seat RECORDED for the operator says so in
 * plain words, so the operator can spot a relay it never gave.
 */
export function AnsweredBy({ answer }: { answer?: AskAnswer }) {
  if (!answer) return null;
  const relayer = relayerOf(answer);
  return (
    <p className="answered-by">
      by <b>{answer.answeredBy || "unknown"}</b>
      {relayer ? (
        <span className="pill warn relay" title={`${relayer} recorded this as the operator's answer${answer.note ? `: ${answer.note}` : ""}`}>
          relayed by {relayer}
        </span>
      ) : answer.answeredVia ? (
        <span className="hidden-note"> via {answer.answeredVia}</span>
      ) : null}
      <span className="sr-only">{answeredByText(answer)}</span>
    </p>
  );
}

/** The author's prose under a fork's heading, paragraph by paragraph: the reasons the options rest on. */
export function ForkProse({ text, between }: { text?: string; between?: boolean }) {
  if (!text?.trim()) return null;
  return (
    <div className={between ? "fork-prose between-forks" : "fork-prose"}>
      {text.split(/\n\s*\n/).map((p, i) => (
        <p key={i}>{p.trim()}</p>
      ))}
    </div>
  );
}

/** The tray: the operator's own drafts only (by author — a seat's relay draft is the relayer's). */
export function trayDrafts<T extends ParsedAsk>(asks: T[]): T[] {
  return asks.filter((a) => a.draft && draftAuthor(a.draft) === "operator");
}
