// OpenClaw native plugin for memory39
// Spawns `memory39 mcp` and communicates via MCP JSON-RPC over stdio.

import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { Type } from "@sinclair/typebox";
import { spawn, type ChildProcess } from "node:child_process";
import { createInterface, type Interface as ReadlineInterface } from "node:readline";

const CALL_TIMEOUT_MS = 30_000;

// ---------------------------------------------------------------------------
// MCP JSON-RPC client — talks to `memory39 mcp` over stdio
// ---------------------------------------------------------------------------

interface PendingEntry {
  resolve: (v: unknown) => void;
  reject: (e: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

interface McpClient {
  proc: ChildProcess;
  rl: ReadlineInterface;
  nextId: number;
  pending: Map<number, PendingEntry>;
  initialized: Promise<void>;
}

function destroyClient(client: McpClient) {
  client.rl.close();
  for (const [, entry] of client.pending) {
    clearTimeout(entry.timer);
    entry.reject(new Error("memory39 process exited"));
  }
  client.pending.clear();
  if (client.proc.exitCode === null) {
    client.proc.kill();
  }
}

function createMcpClient(binaryPath: string, extraArgs: string[]): McpClient {
  const args = ["mcp", ...extraArgs];

  const proc = spawn(binaryPath, args, {
    stdio: ["pipe", "pipe", "ignore"],
  });

  const rl = createInterface({ input: proc.stdout! });
  const client: McpClient = {
    proc,
    rl,
    nextId: 0,
    pending: new Map(),
    initialized: Promise.resolve(),
  };

  rl.on("line", (line) => {
    try {
      const msg = JSON.parse(line);
      if (msg.id !== undefined) {
        const entry = client.pending.get(msg.id);
        if (entry) {
          clearTimeout(entry.timer);
          client.pending.delete(msg.id);
          if (msg.error) {
            entry.reject(new Error(msg.error.message || JSON.stringify(msg.error)));
          } else {
            entry.resolve(msg.result);
          }
        }
      }
    } catch {
      // ignore non-JSON lines
    }
  });

  proc.on("exit", () => destroyClient(client));

  // MCP initialize handshake
  client.initialized = (async () => {
    await rpcCall(client, "initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "openclaw-memory39", version: "1.0.0" },
    });
    proc.stdin!.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  })();

  return client;
}

function rpcCall(client: McpClient, method: string, params?: unknown): Promise<unknown> {
  return new Promise((resolve, reject) => {
    client.nextId++;
    const id = client.nextId;
    const timer = setTimeout(() => {
      client.pending.delete(id);
      reject(new Error(`memory39 RPC timeout: ${method}`));
    }, CALL_TIMEOUT_MS);
    client.pending.set(id, { resolve, reject, timer });
    client.proc.stdin!.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
}

interface ToolResult {
  content?: Array<{ type: string; text?: string }>;
  isError?: boolean;
}

async function callTool(client: McpClient, toolName: string, args?: Record<string, unknown>): Promise<string> {
  await client.initialized;
  const result = await rpcCall(client, "tools/call", { name: toolName, arguments: args ?? {} }) as ToolResult;

  if (result.isError) {
    const text = result.content?.map((c) => c.text ?? "").join("\n") || "Unknown error";
    throw new Error(text);
  }

  return result.content?.map((c) => c.text ?? "").join("\n") || "";
}

// ---------------------------------------------------------------------------
// Plugin entry
// ---------------------------------------------------------------------------

export default definePluginEntry({
  id: "memory39",
  name: "memory39",
  description: "Temporal-priority memory system for AI agents — store and recall with intelligent scoring",

  register(api) {
    const config = api.pluginConfig as { binaryPath?: string; dbPath?: string };
    const binaryPath = config.binaryPath || "memory39";
    const extraArgs: string[] = [];
    if (config.dbPath) {
      extraArgs.push("--db", config.dbPath);
    }

    let client: McpClient | null = null;
    let clientCreating = false;

    function getClient(): McpClient {
      if (!client || client.proc.exitCode !== null) {
        if (clientCreating) return client!;
        clientCreating = true;
        client = createMcpClient(binaryPath, extraArgs);
        clientCreating = false;
      }
      return client;
    }

    function proxyTool(
      name: string,
      description: string,
      parameters: ReturnType<typeof Type.Object>,
    ) {
      api.registerTool({
        name,
        description,
        parameters,
        async execute(_id, params) {
          const text = await callTool(getClient(), name, params as Record<string, unknown>);
          return { content: [{ type: "text" as const, text }] };
        },
      });
    }

    // -- recall --------------------------------------------------------------
    proxyTool("recall",
      "Search memories with temporal-priority scoring (0.4 relevance + 0.3 importance + 0.3 recency). Supports FTS5 query syntax.",
      Type.Object({
        query: Type.String({ description: "Search query (FTS5 syntax supported: AND, OR, NOT, quotes for phrases)" }),
        limit: Type.Optional(Type.Number({ description: "Max results to return (default: 10)" })),
      }),
    );

    // -- event ---------------------------------------------------------------
    proxyTool("event",
      "Store a dated or undated event memory",
      Type.Object({
        what: Type.String({ description: "What happened" }),
        date: Type.Optional(Type.String({ description: "When it happened (YYYY-MM-DD or natural language). Omit for undated events." })),
        who: Type.Optional(Type.String({ description: "Who was involved" })),
        where_: Type.Optional(Type.String({ description: "Where it happened" })),
        importance: Type.Optional(Type.Number({ description: "Importance score 0-10 (default: 5)" })),
      }),
    );

    // -- thing ---------------------------------------------------------------
    proxyTool("thing",
      "Store a fact, concept, or object memory",
      Type.Object({
        name: Type.String({ description: "Name of the thing" }),
        detail: Type.String({ description: "Details about the thing" }),
        importance: Type.Optional(Type.Number({ description: "Importance score 0-10 (default: 5)" })),
      }),
    );

    // -- person --------------------------------------------------------------
    proxyTool("person",
      "Store a social memory about a person",
      Type.Object({
        name: Type.String({ description: "Person's name" }),
        detail: Type.String({ description: "Details about the person" }),
        importance: Type.Optional(Type.Number({ description: "Importance score 0-10 (default: 5)" })),
      }),
    );

    // -- place ---------------------------------------------------------------
    proxyTool("place",
      "Store a spatial/location memory",
      Type.Object({
        name: Type.String({ description: "Name of the place" }),
        detail: Type.String({ description: "Details about the place" }),
        importance: Type.Optional(Type.Number({ description: "Importance score 0-10 (default: 5)" })),
      }),
    );

    // -- forget --------------------------------------------------------------
    proxyTool("forget",
      "Delete a memory by its universal ID (E#, U#, T#, P#, L#)",
      Type.Object({
        id: Type.String({ description: "Memory ID to delete (e.g. E42, T7, P3)" }),
      }),
    );

    // -- alter ---------------------------------------------------------------
    proxyTool("alter",
      "Modify fields of an existing memory",
      Type.Object({
        id: Type.String({ description: "Memory ID to modify (e.g. E42, T7, P3)" }),
        field: Type.String({ description: "Field name to change" }),
        value: Type.String({ description: "New value for the field" }),
      }),
    );

    // -- connect -------------------------------------------------------------
    proxyTool("connect",
      "Find 2-3 hop connections between concepts in memory (direct, shared, bridge discovery)",
      Type.Object({
        query: Type.String({ description: "Concept or topic to find connections for" }),
      }),
    );

    // -- cleanup on gateway shutdown -----------------------------------------
    api.on("shutdown", () => {
      if (client) destroyClient(client);
    });

    api.logger.info("memory39 plugin registered");
  },
});
