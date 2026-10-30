import fs from "node:fs";
import path from "node:path";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import { BUILD_ID_FILE, computeBuildId } from "./src/build-id.ts";

/** Stamp the build with the id of the sources it was built from. */
function buildId(): Plugin {
  return {
    name: "ask-app-build-id",
    writeBundle(opts) {
      if (opts.dir) fs.writeFileSync(path.join(opts.dir, BUILD_ID_FILE), `${computeBuildId()}\n`);
    },
  };
}

export default defineConfig({
  root: "src/client",
  plugins: [react(), buildId()],
  // NOTE: with no --outDir this builds INTO the app's own dist/, which a live server reads; never run a
  // bare `npm run build` beside a live server. `engine ask serve` passes a temp --outDir and moves the
  // result into place under a lock; pass --outDir <scratch> for any other build.
  build: { outDir: "../../dist", emptyOutDir: true },
  server: { host: "127.0.0.1", proxy: { "/api": "http://127.0.0.1:4977" } },
  // The suite runs on a shared, often heavily loaded machine; the limits are for a hang, not a pace.
  // ASK_SEARCH_AUTO=0: a server a test spawns inherits this env, so it never indexes on start or on an ask write,
  // and never reaches this machine's real embedder or proof store that way (IDE-334). A search test turns it back on with its own sources.
  test: { root: ".", include: ["test/**/*.test.ts"], testTimeout: 30_000, hookTimeout: 60_000, env: { ASK_SEARCH_AUTO: "0" } },
});
