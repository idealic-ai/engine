/**
 * RPC CLI — unified entry point for all daemon RPC namespaces.
 *
 * Usage: engine rpc <cmd> [json-args]
 *
 * Examples:
 *   engine rpc agent.skills.list '{}'
 *   engine rpc agent.skills.parse '{"skillPath": "~/.claude/skills/implement/SKILL.md"}'
 *   engine rpc fs.paths.resolve '{"paths": ["~/Projects"]}'
 *   engine rpc fs.files.read '{"path": "/tmp/test.txt"}'
 *   engine rpc db.skills.upsert '{"name": "test", ...}'
 *
 * Sends {cmd, args} over Unix socket to the daemon. Same socket as SQL queries —
 * the daemon routes by presence of `cmd` vs `sql` field.
 */
import * as net from "node:net";
import * as crypto from "node:crypto";

function defaultSocketPath(): string {
  const projectRoot = process.env.PROJECT_ROOT || process.cwd();
  const hash = crypto.createHash("md5").update(projectRoot).digest("hex").slice(0, 8);
  return `/tmp/engine-daemon-${hash}.sock`;
}

interface RpcRequest {
  cmd: string;
  args?: unknown;
  env?: Record<string, string>;
}

interface RpcResponse {
  ok: boolean;
  [key: string]: unknown;
}

async function sendRpc(socketPath: string, request: RpcRequest): Promise<RpcResponse> {
  return new Promise((resolve, reject) => {
    const client = net.createConnection(socketPath, () => {
      client.write(JSON.stringify(request) + "\n");
    });

    let data = "";

    client.on("data", (chunk) => {
      data += chunk.toString();
      if (data.includes("\n")) {
        client.end();
        try {
          resolve(JSON.parse(data.trim()) as RpcResponse);
        } catch {
          reject(new Error(`Invalid JSON response from daemon: ${data}`));
        }
      }
    });

    client.on("error", (err) => {
      reject(err);
    });

    client.setTimeout(30000, () => {
      client.destroy();
      reject(new Error("RPC request timed out after 30 seconds"));
    });
  });
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error("Usage: engine rpc <cmd> [json-args]");
    console.error("");
    console.error("Namespaces:");
    console.error("  db.*     — Database operations");
    console.error("  fs.*     — Filesystem operations");
    console.error("  agent.*  — Convention/workspace operations");
    console.error("");
    console.error("Examples:");
    console.error("  engine rpc agent.skills.list '{}'");
    console.error("  engine rpc fs.paths.resolve '{\"paths\": [\"~/Projects\"]}'");
    process.exit(1);
  }

  const cmd = args[0];
  let rpcArgs: unknown = {};

  if (args.length > 1) {
    try {
      rpcArgs = JSON.parse(args[1]);
    } catch {
      console.error(`Error: Invalid JSON args: ${args[1]}`);
      process.exit(1);
    }
  }

  // Collect env vars to inject into every RPC request
  const env: Record<string, string> = {};
  const envKeys = [
    "AGENT_ID",
    "AGENT_CLAIMS", "AGENT_TARGETED_CLAIMS", "AGENT_MANAGES", "AGENT_PARENT",
    "CLAUDE_PLUGIN_ROOT",
  ];
  for (const key of envKeys) {
    if (process.env[key]) {
      env[key] = process.env[key]!;
    }
  }
  // CWD is always available
  env.CWD = process.env.PROJECT_ROOT || process.cwd();

  const socketPath = defaultSocketPath();

  try {
    const result = await sendRpc(socketPath, { cmd, args: rpcArgs, env });

    if (!result.ok) {
      console.error(`Error [${result.error}]: ${result.message}`);
      if (result.details) {
        console.error(JSON.stringify(result.details, null, 2));
      }
      process.exit(1);
    }

    // Print data as JSON
    console.log(JSON.stringify(result.data, null, 2));
  } catch (err: unknown) {
    if (err instanceof Error && "code" in err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === "ENOENT" || code === "ECONNREFUSED") {
        console.error("Error: Daemon is not running. Start it with: engine daemon start");
        process.exit(1);
      }
    }
    console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
