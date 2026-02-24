import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    include: ["hooks/test/**/*.test.ts"],
    testTimeout: 120_000,
    hookTimeout: 30_000,
  },
});
