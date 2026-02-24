import { defineConfig } from "vitest/config";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  test: {
    globals: true,
    include: [
      "shared/src/**/*.test.ts",
      "db/src/**/*.test.ts",
      "agent/src/**/*.test.ts",
      "fs/src/**/*.test.ts",
      "commands/src/**/*.test.ts",
      "config/src/**/*.test.ts",
      "ai/src/**/*.test.ts",
      "hooks/src/**/*.test.ts",
      "search/src/**/*.test.ts",
      "daemon/src/**/*.test.ts",
    ],
  },
  resolve: {
    alias: {
      "engine-shared": path.resolve(__dirname, "shared/src"),
      "engine-db": path.resolve(__dirname, "db/src"),
      "engine-agent": path.resolve(__dirname, "agent/src"),
      "engine-fs": path.resolve(__dirname, "fs/src"),
    },
  },
});
