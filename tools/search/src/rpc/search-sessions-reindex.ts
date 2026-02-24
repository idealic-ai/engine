/**
 * search.sessions.reindex — Scan session files, chunk, embed, and upsert into the search index.
 *
 * Reconciliation: compares incoming chunks against existing DB state.
 * New chunks are inserted, unchanged chunks are skipped, removed chunks are deleted.
 *
 * Uses ai.embed for embeddings and search.upsert/search.delete for DB operations.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import { dispatch } from "../../../db/src/rpc/dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import {
  parseMarkdownChunks,
  parseStateJsonChunks,
  type SessionChunk,
} from "./chunkers/session-chunker.js";

const SOURCE_TYPE = "session";

const schema = z.object({
  /** Session directory paths to scan (relative or absolute). */
  sessionPaths: z.array(z.string()).min(1),
  /** File contents keyed by path — avoids filesystem access in tests. */
  fileContents: z.record(z.string(), z.string()).optional(),
});

type Args = z.infer<typeof schema>;

interface ReindexReport {
  inserted: number;
  updated: number;
  skipped: number;
  deleted: number;
  totalChunks: number;
}

async function handler(
  args: Args,
  ctx: RpcContext
): Promise<TypedRpcResponse<ReindexReport>> {
  const db = ctx.db;
  const fileContents = args.fileContents ?? {};

  // Step 1: Collect all chunks from all session paths
  const allChunks: SessionChunk[] = [];

  for (const sessionPath of args.sessionPaths) {
    for (const [filePath, content] of Object.entries(fileContents)) {
      if (!filePath.startsWith(sessionPath)) continue;

      if (filePath.endsWith(".state.json")) {
        allChunks.push(...parseStateJsonChunks(content, filePath));
      } else if (filePath.endsWith(".md")) {
        allChunks.push(...parseMarkdownChunks(content, filePath));
      }
    }
  }

  // Step 2: Load existing chunks from DB for these session paths
  const existingChunks = await db.all<{
    id: number;
    sourcePath: string;
    sectionTitle: string;
    contentHash: string;
  }>(
    "SELECT id, source_path AS sourcePath, section_title AS sectionTitle, content_hash AS contentHash FROM chunks WHERE source_type = ?",
    [SOURCE_TYPE]
  );

  const existingMap = new Map<string, { id: number; contentHash: string }>();
  for (const row of existingChunks) {
    existingMap.set(`${row.sourcePath}::${row.sectionTitle}`, {
      id: row.id,
      contentHash: row.contentHash,
    });
  }

  // Step 3: Classify chunks
  let inserted = 0;
  let updated = 0;
  let skipped = 0;

  const incomingKeys = new Set<string>();

  for (const chunk of allChunks) {
    const key = `${chunk.sourcePath}::${chunk.sectionTitle}`;
    incomingKeys.add(key);

    const existing = existingMap.get(key);

    if (!existing) {
      // New chunk — need embedding
      const embResult = await getEmbedding(chunk.chunkText, ctx);
      if (!embResult) continue;

      await dispatch(
        {
          cmd: "search.upsert",
          args: {
            sourceType: SOURCE_TYPE,
            sourcePath: chunk.sourcePath,
            sectionTitle: chunk.sectionTitle,
            chunkText: chunk.chunkText,
            contentHash: chunk.contentHash,
            embedding: embResult,
          },
        },
        ctx
      );
      inserted++;
    } else if (existing.contentHash !== chunk.contentHash) {
      // Changed chunk — re-embed
      const embResult = await getEmbedding(chunk.chunkText, ctx);
      if (!embResult) continue;

      await dispatch(
        {
          cmd: "search.upsert",
          args: {
            sourceType: SOURCE_TYPE,
            sourcePath: chunk.sourcePath,
            sectionTitle: chunk.sectionTitle,
            chunkText: chunk.chunkText,
            contentHash: chunk.contentHash,
            embedding: embResult,
          },
        },
        ctx
      );
      updated++;
    } else {
      skipped++;
    }
  }

  // Step 4: Delete orphaned chunks
  let deleted = 0;
  for (const [key, existing] of existingMap) {
    if (!incomingKeys.has(key)) {
      const [sourcePath, sectionTitle] = key.split("::");
      // Delete individually by removing from chunks table
      await db.run(
        "DELETE FROM chunks WHERE id = ?",
        [existing.id]
      );
      deleted++;
    }
  }

  // Clean orphaned embeddings
  if (deleted > 0) {
    await db.run(
      "DELETE FROM embeddings WHERE content_hash NOT IN (SELECT DISTINCT content_hash FROM chunks)"
    );
  }

  return {
    ok: true,
    data: {
      inserted,
      updated,
      skipped,
      deleted,
      totalChunks: allChunks.length,
    },
  };
}

async function getEmbedding(
  text: string,
  ctx: RpcContext
): Promise<number[] | null> {
  const result = await dispatch(
    { cmd: "ai.embed", args: { texts: [text] } },
    ctx
  );
  if (!result.ok) return null;
  return (result.data as { embeddings: number[][] }).embeddings[0];
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "search.sessions.reindex": typeof handler;
  }
}

registerCommand("search.sessions.reindex", { schema, handler });
