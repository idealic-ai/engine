/**
 * search.docs.reindex — Scan doc files, chunk with breadcrumbs, embed, and upsert.
 *
 * Uses H1/H2/H3 chunking with breadcrumb titles. Content-hash deduplication
 * ensures identical text across files shares one embedding.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import { dispatch } from "../../../db/src/rpc/dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import { parseChunks, type DocChunk } from "./chunkers/doc-chunker.js";

const SOURCE_TYPE = "doc";

const schema = z.object({
  /** File contents keyed by path — avoids filesystem access in tests. */
  fileContents: z.record(z.string(), z.string()),
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

  // Step 1: Chunk all files
  const allChunks: DocChunk[] = [];
  for (const [filePath, content] of Object.entries(args.fileContents)) {
    allChunks.push(...parseChunks(content, filePath));
  }

  // Step 2: Load existing doc chunks
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

  // Step 3: Classify and upsert
  let inserted = 0;
  let updated = 0;
  let skipped = 0;
  const incomingKeys = new Set<string>();

  for (const chunk of allChunks) {
    const key = `${chunk.sourcePath}::${chunk.sectionTitle}`;
    incomingKeys.add(key);
    const existing = existingMap.get(key);

    if (!existing || existing.contentHash !== chunk.contentHash) {
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
      if (!existing) inserted++;
      else updated++;
    } else {
      skipped++;
    }
  }

  // Step 4: Delete orphans
  let deleted = 0;
  for (const [key, existing] of existingMap) {
    if (!incomingKeys.has(key)) {
      await db.run("DELETE FROM chunks WHERE id = ?", [existing.id]);
      deleted++;
    }
  }

  if (deleted > 0) {
    await db.run(
      "DELETE FROM embeddings WHERE content_hash NOT IN (SELECT DISTINCT content_hash FROM chunks)"
    );
  }

  return {
    ok: true,
    data: { inserted, updated, skipped, deleted, totalChunks: allChunks.length },
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
    "search.docs.reindex": typeof handler;
  }
}

registerCommand("search.docs.reindex", { schema, handler });
