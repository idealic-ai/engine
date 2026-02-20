import * as net from "node:net";

export interface QueryRequest {
  sql: string;
  params: (string | number | null)[];
  format: "json" | "tsv" | "scalar";
  single: boolean;
}

export interface QueryResult {
  ok: boolean;
  [key: string]: unknown;
}

/**
 * Send a query to the daemon over Unix socket and return the response.
 * Throws if the daemon is not running or the connection fails.
 */
export async function sendQuery(
  socketPath: string,
  request: QueryRequest
): Promise<QueryResult> {
  return new Promise((resolve, reject) => {
    const client = net.createConnection(socketPath, () => {
      client.write(JSON.stringify(request) + "\n");
    });

    let data = "";

    client.on("data", (chunk) => {
      data += chunk.toString();

      // Response is newline-delimited
      if (data.includes("\n")) {
        client.end();
        try {
          resolve(JSON.parse(data.trim()) as QueryResult);
        } catch {
          reject(new Error(`Invalid JSON response from daemon: ${data}`));
        }
      }
    });

    client.on("error", (err) => {
      reject(err);
    });

    client.setTimeout(10000, () => {
      client.destroy();
      reject(new Error("Query timed out after 10 seconds"));
    });
  });
}
