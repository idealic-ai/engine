// Shared time-argument parsing for the search CLIs (session-search, doc-search).
// `--since` / `--until` accept either an absolute date (anything `Date` can parse,
// e.g. `2026-01-01` or a full ISO timestamp) or a relative offset from now
// (`7d`, `24h`, `30m`, `2w`, `3mo`, `1y`, optionally suffixed with ` ago`), plus
// the keywords `now`, `today`, `yesterday`. Throws on anything unrecognized so the
// callers can surface an "Invalid --since/--until value" error.

const UNIT_MS: Record<string, number> = {
  s: 1000,
  m: 60_000,
  h: 3_600_000,
  d: 86_400_000,
  w: 604_800_000,
};

const UNIT_ALIASES: Record<string, keyof typeof UNIT_MS | "mo" | "y"> = {
  s: "s", sec: "s", secs: "s", second: "s", seconds: "s",
  m: "m", min: "m", mins: "m", minute: "m", minutes: "m",
  h: "h", hr: "h", hrs: "h", hour: "h", hours: "h",
  d: "d", day: "d", days: "d",
  w: "w", wk: "w", wks: "w", week: "w", weeks: "w",
  mo: "mo", mos: "mo", month: "mo", months: "mo",
  y: "y", yr: "y", yrs: "y", year: "y", years: "y",
};

export function parseTimeArg(input: string): Date {
  const raw = input.trim();
  if (!raw) throw new Error("empty time value");

  const lower = raw.toLowerCase();

  if (lower === "now") return new Date();
  if (lower === "today") {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    return d;
  }
  if (lower === "yesterday") {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() - 1);
    return d;
  }

  const rel = lower.match(/^(\d+(?:\.\d+)?)\s*([a-z]+)(?:\s+ago)?$/);
  if (rel) {
    const amount = parseFloat(rel[1]);
    const alias = UNIT_ALIASES[rel[2]];
    if (!alias) throw new Error(`unrecognized time unit: "${rel[2]}"`);
    const d = new Date();
    if (alias === "mo") {
      d.setMonth(d.getMonth() - Math.round(amount));
    } else if (alias === "y") {
      d.setFullYear(d.getFullYear() - Math.round(amount));
    } else {
      return new Date(d.getTime() - amount * UNIT_MS[alias]);
    }
    return d;
  }

  const abs = new Date(raw);
  if (Number.isNaN(abs.getTime())) {
    throw new Error(`unrecognized time value: "${input}"`);
  }
  return abs;
}

export function toISOString(date: Date): string {
  return date.toISOString();
}

export function toUnixMs(date: Date): number {
  return date.getTime();
}
