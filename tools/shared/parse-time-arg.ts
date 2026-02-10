/**
 * Parse a time argument into an absolute Date.
 *
 * Supported formats:
 *   - Relative: "16h", "7d", "2w", "1m", "1y"
 *     (hours, days, weeks, months, years — subtracted from now)
 *   - Absolute date: "2026-02-01" (parsed as midnight UTC)
 *   - ISO datetime: "2026-02-01T14:30:00" or "2026-02-01T14:30:00Z"
 *
 * @param input The time argument string
 * @param now Optional reference time (defaults to Date.now(), useful for testing)
 * @returns Resolved absolute Date
 * @throws Error on invalid input
 */
export function parseTimeArg(input: string, now?: Date): Date {
  const trimmed = input.trim();
  if (trimmed.length === 0) {
    throw new Error(`Invalid time argument: empty string`);
  }

  // Try relative format: <number><unit>
  const relativeMatch = trimmed.match(/^(\d+)([hdwmy])$/i);
  if (relativeMatch) {
    const amount = parseInt(relativeMatch[1], 10);
    const unit = relativeMatch[2].toLowerCase();
    return resolveRelative(amount, unit, now ?? new Date());
  }

  // Try ISO datetime: YYYY-MM-DDTHH:MM:SS[Z]
  if (trimmed.includes("T")) {
    const date = new Date(trimmed);
    if (isNaN(date.getTime())) {
      throw new Error(`Invalid time argument: "${input}" (invalid ISO datetime)`);
    }
    return date;
  }

  // Try absolute date: YYYY-MM-DD
  const dateMatch = trimmed.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (dateMatch) {
    const date = new Date(`${trimmed}T00:00:00Z`);
    if (isNaN(date.getTime())) {
      throw new Error(`Invalid time argument: "${input}" (invalid date)`);
    }
    return date;
  }

  throw new Error(
    `Invalid time argument: "${input}". Expected relative (e.g., "7d", "16h"), date ("YYYY-MM-DD"), or ISO datetime ("YYYY-MM-DDTHH:MM:SS").`
  );
}

function resolveRelative(amount: number, unit: string, now: Date): Date {
  const result = new Date(now);

  switch (unit) {
    case "h":
      result.setTime(result.getTime() - amount * 60 * 60 * 1000);
      break;
    case "d":
      result.setTime(result.getTime() - amount * 24 * 60 * 60 * 1000);
      break;
    case "w":
      result.setTime(result.getTime() - amount * 7 * 24 * 60 * 60 * 1000);
      break;
    case "m":
      result.setMonth(result.getMonth() - amount);
      break;
    case "y":
      result.setFullYear(result.getFullYear() - amount);
      break;
    default:
      throw new Error(`Unknown time unit: "${unit}"`);
  }

  return result;
}

/**
 * Convert a parsed Date to an ISO date string (YYYY-MM-DD) for SQL comparison
 * against session_date columns.
 */
export function toDateString(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/**
 * Convert a parsed Date to an ISO datetime string for SQL comparison
 * against timestamp columns.
 */
export function toISOString(date: Date): string {
  return date.toISOString();
}

/**
 * Convert a parsed Date to a Unix timestamp in milliseconds for comparison
 * against mtime columns.
 */
export function toUnixMs(date: Date): number {
  return date.getTime();
}
