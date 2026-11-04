/**
 * RAGSEARCH-UI: the results panel under the search box. Idle shows nothing; waiting says it is
 * searching (never "no results"); a refusal shows one note naming the reason and nothing else, so the
 * text-filtered list below is the answer; an answer lists asks first, then proof pages and broadcasts,
 * each marked as a word or a meaning match, with the index's age and "refreshing" while a pass runs.
 *
 * The list is a listbox driven from the search input (aria-activedescendant): the arrows move the
 * selection and Enter opens it (App.tsx), so focus never leaves the box.
 */
import { Fragment } from "react";
import type { Row } from "./model.ts";
import { highlight, snippet, type Hay } from "./search.ts";
import { excerptAfterSection, indexAgeText, mergeResults, openTarget, unavailableNote, type Match, type ResultItem, type SemanticState } from "./semantic.ts";

export const RESULTS_ID = "search-results";
export const optionId = (i: number) => `sr-${i}`;

const HOW: Record<Match, [string, string]> = {
  word: ["word", "Matched the words you typed"],
  meaning: ["meaning", "Matched on meaning (semantic search)"],
  both: ["word + meaning", "Matched the words you typed and on meaning"],
};
const KIND_LABEL: Record<ResultItem["kind"], string> = { ask: "ask", proof: "proof", broadcast: "broadcast" };

function Marked({ text, terms }: { text: string; terms: string[] }) {
  if (terms.length === 0) return <>{text}</>;
  return <>{highlight(text, terms).map((p, i) => (p.hit ? <mark key={i}>{p.text}</mark> : <Fragment key={i}>{p.text}</Fragment>))}</>;
}

/** The merged items the panel shows for this state (empty unless it holds an answer). */
export function resultItems(state: SemanticState, words: (Row & { extra?: Hay })[]): { items: ResultItem[]; moreWords: number } {
  if (state.phase !== "done" || !state.answer.ok) return { items: [], moreWords: 0 };
  return mergeResults(words, state.answer.hits);
}

export function SearchResults({
  state,
  words,
  selected,
  now,
  terms,
  onOpen,
  onHover,
}: {
  state: SemanticState;
  words: (Row & { extra?: Hay })[];
  selected: number;
  now: number;
  terms: string[];
  onOpen: (i: ResultItem) => void;
  onHover: (index: number) => void;
}) {
  if (state.phase === "idle") return null;
  if (state.phase === "waiting") return <p className="search-note muted" role="status" aria-live="polite">searching by meaning…</p>;
  const a = state.answer;
  if (!a.ok) return <p className="search-note muted" role="status">{unavailableNote(a.reason, a)}</p>;
  const { items, moreWords } = resultItems(state, words);
  return (
    <section className="search-results" aria-label="Search results">
      <p className="sr-head muted">
        <span>Results</span> · <span title={a.indexedAt ?? undefined}>{indexAgeText(a.indexedAt, now)}</span>
        {a.refreshing && <> · <span className="sr-refreshing">refreshing</span></>}
        {/* SEARCHFIX: an empty 200 means nothing reached the floor; the floor is a tooltip only. */}
        {" · "}<span className="sr-meaning" title={a.minScore ? `Meaning matches scored at least ${a.minScore}` : undefined}>{a.hits.length ? `${a.hits.length} by meaning` : "no matches by meaning"}</span>
      </p>
      {items.length === 0 ? (
        <p className="muted pad" role="status">Nothing matches “{a.q}” by meaning or by word.</p>
      ) : (
        <ul className="sr-list" role="listbox" id={RESULTS_ID} aria-label="Search results">
          {items.map((it, i) => {
            const target = openTarget(it);
            const [how, howTitle] = HOW[it.match];
            // A meaning hit did not match on these letters, so nothing in it is marked as if it had.
            const marks = it.match === "meaning" ? [] : terms;
            return (
              <li
                key={it.key}
                id={optionId(i)}
                role="option"
                aria-selected={i === selected}
                aria-disabled={target ? undefined : true}
                className={`sr-item${i === selected ? " sel" : ""}${target ? "" : " dead"}`}
                title={target ? undefined : "This page has no address to open"}
                onMouseEnter={() => onHover(i)}
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => target && onOpen(it)}
              >
                <span className="sr-top">
                  {it.kind !== "ask" && <span className="sr-kind">{KIND_LABEL[it.kind]}</span>}
                  <span className="sr-title"><Marked text={it.title} terms={marks} /></span>
                  <span className={`sr-how ${it.match === "both" ? "word meaning" : it.match}`} title={howTitle}>{how}</span>
                </span>
                {it.excerpt && (
                  <span className="sr-excerpt">
                    {it.section && <span className="sr-section">{it.section}</span>} <Marked text={excerptAfterSection(it.section, it.excerpt)} terms={marks} />
                  </span>
                )}
                {!it.excerpt && it.extra && (
                  <span className="sr-excerpt">
                    <span className="sr-section">{it.extra.field}</span> <Marked text={snippet(it.extra.text, terms)} terms={terms} />
                  </span>
                )}
                {it.seat && <span className="sr-seat muted">{it.seat}</span>}
              </li>
            );
          })}
        </ul>
      )}
      {moreWords > 0 && <p className="sr-more muted">+{moreWords} more word matches in the list below</p>}
    </section>
  );
}
