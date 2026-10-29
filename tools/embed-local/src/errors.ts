import type { EmbedErrorCode } from "./contract.js";

/**
 * Every embedding failure, thrown with a code a caller can branch on and a
 * message written for a human who has not been watching (it names the remedy).
 * Nothing in this module returns a vector it did not receive.
 */
export class EmbedLocalError extends Error {
  readonly code: EmbedErrorCode;

  constructor(code: EmbedErrorCode, message: string) {
    super(`[embed-local] ${code}: ${message}`);
    this.name = "EmbedLocalError";
    this.code = code;
  }
}

export function isEmbedLocalError(err: unknown, code?: EmbedErrorCode): err is EmbedLocalError {
  return err instanceof EmbedLocalError && (code === undefined || err.code === code);
}
