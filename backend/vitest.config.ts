import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // The rate-limit buckets and the config module are process-global, so
    // parallel files would interfere with each other.
    fileParallelism: false,
    env: {
      NODE_ENV: "test",
      // Forces the fallback path: tests must never make a real API call.
      ANTHROPIC_API_KEY: "",
      AUTH_SECRET: "test-only-secret-at-least-32-characters-long",
    },
  },
});
