/**
 * agent.messages.ingest — Incrementally ingest transcript JSONL into the messages table.
 *
 * Reads a Claude Code transcript file (JSONL) from the last-known byte offset,
 * parses new lines into messages, bulk-inserts them, and advances the waterline.
 *
 * Waterline strategy: byte offset stored on the session row. On each call,
 * we fseek to that offset, read new bytes, split into complete JSONL lines,
 * and update the offset to just past the last complete line. Partial trailing
 * lines (file still being written) are left for the next ingestion cycle.
 *
 * Trigger points: hooks.postToolUse (off the hot path), hooks.userPrompt.
 *
 * Graceful failure: if file is missing, unreadable, or empty — returns {ingested: 0}.
 * Never throws — ingestion failures must not block hook responses.
 */
import * as fs from "node:fs";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  sessionId: z.number(),
  transcriptPath: z.string().optional(),
});

type Args = z.infer<typeof schema>;

interface ParsedMessage {
  role: string;
  content: string;
  toolName?: string;
}

/**
 * Extract the JSONL entry type and optional tool name from a parsed line.
 */
function parseJsonlLine(line: string): ParsedMessage | null {
  try {
    const obj = JSON.parse(line);
    const role = obj.type ?? "unknown";

    // Extract tool name from assistant tool_use blocks
    let toolName: string | undefined;
    if (role === "assistant" && obj.message?.content) {
      const toolUse = (obj.message.content as Array<{ type: string; name?: string }>)
        .find((block) => block.type === "tool_use");
      if (toolUse?.name) {
        toolName = toolUse.name;
      }
    }

    // Extract tool name from result entries
    if (role === "result" && obj.tool_name) {
      toolName = obj.tool_name as string;
    }

    return { role, content: line, toolName };
  } catch {
    return null;
  }
}

/**
 * Read new bytes from a file starting at the given offset.
 * Returns the buffer content and the number of bytes read.
 */
function readFromOffset(filePath: string, offset: number): { text: string; bytesRead: number } | null {
  let fd: number | undefined;
  try {
    const stat = fs.statSync(filePath);
    if (stat.size <= offset) {
      return { text: "", bytesRead: 0 };
    }

    const readSize = stat.size - offset;
    const buffer = Buffer.alloc(readSize);
    fd = fs.openSync(filePath, "r");
    const bytesRead = fs.readSync(fd, buffer, 0, readSize, offset);
    return { text: buffer.toString("utf8", 0, bytesRead), bytesRead };
  } catch {
    return null;
  } finally {
    if (fd !== undefined) {
      try { fs.closeSync(fd); } catch { /* ignore */ }
    }
  }
}

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ ingested: number; newOffset: number }>> {
  // 1. Get session to find transcript_path and transcript_offset
  const { session } = await ctx.db.session.get({ id: args.sessionId });
  if (!session) {
    return { ok: true, data: { ingested: 0, newOffset: 0 } };
  }

  let transcriptPath = session.transcriptPath;
  let transcriptOffset = session.transcriptOffset ?? 0;

  // 2. If transcriptPath provided and not stored yet, store it
  if (args.transcriptPath && !transcriptPath) {
    transcriptPath = args.transcriptPath;
    await ctx.db.session.setTranscript({
      sessionId: args.sessionId,
      transcriptPath,
    });
  }

  // 3. No path available — nothing to ingest
  if (!transcriptPath) {
    return { ok: true, data: { ingested: 0, newOffset: transcriptOffset } };
  }

  // 4. Read new bytes from file
  const result = readFromOffset(transcriptPath, transcriptOffset);
  if (!result || result.bytesRead === 0) {
    return { ok: true, data: { ingested: 0, newOffset: transcriptOffset } };
  }

  // 5. Split into complete lines (leave partial trailing line for next cycle)
  const { text } = result;
  const lastNewline = text.lastIndexOf("\n");
  if (lastNewline === -1) {
    // No complete line yet — partial write in progress
    return { ok: true, data: { ingested: 0, newOffset: transcriptOffset } };
  }

  const completeText = text.slice(0, lastNewline + 1);
  const lines = completeText.split("\n").filter((l) => l.trim().length > 0);

  // 6. Parse each line into message format
  const messages: ParsedMessage[] = [];
  for (const line of lines) {
    const parsed = parseJsonlLine(line);
    if (parsed) {
      messages.push(parsed);
    }
  }

  // 7. Bulk insert
  if (messages.length > 0) {
    await ctx.db.messages.upsert({
      sessionId: args.sessionId,
      messages,
    });
  }

  // 8. Advance waterline to past the last complete line
  const newOffset = transcriptOffset + Buffer.byteLength(completeText, "utf8");
  await ctx.db.session.setTranscript({
    sessionId: args.sessionId,
    transcriptOffset: newOffset,
  });

  return { ok: true, data: { ingested: messages.length, newOffset } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "agent.messages.ingest": typeof handler;
  }
}

registerCommand("agent.messages.ingest", { schema, handler });
