// OpenClaw native plugin for repo39
// Spawns `repo39 mcp` and communicates via MCP JSON-RPC over stdio.

import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { Type } from "@sinclair/typebox";
import { spawn, type ChildProcess } from "node:child_process";
import { createInterface, type Interface as ReadlineInterface } from "node:readline";

const CALL_TIMEOUT_MS = 60_000;

// ---------------------------------------------------------------------------
// MCP JSON-RPC client — talks to `repo39 mcp` over stdio
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
    entry.reject(new Error("repo39 process exited"));
  }
  client.pending.clear();
  if (client.proc.exitCode === null) {
    client.proc.kill();
  }
}

function createMcpClient(binaryPath: string): McpClient {
  const args = ["mcp"];

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
      clientInfo: { name: "openclaw-repo39", version: "1.0.0" },
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
      reject(new Error(`repo39 RPC timeout: ${method}`));
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
  id: "repo39",
  name: "repo39",
  description: "Token-optimized repository explorer for AI agents — trees, symbols, deps, diffs, and search",

  register(api) {
    const config = api.pluginConfig as { binaryPath?: string };
    const binaryPath = config.binaryPath || "repo39";

    let client: McpClient | null = null;
    let clientCreating = false;

    function getClient(): McpClient {
      if (!client || client.proc.exitCode !== null) {
        if (clientCreating) return client!;
        clientCreating = true;
        client = createMcpClient(binaryPath);
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

    // -- tree ----------------------------------------------------------------
    proxyTool("repo39_tree",
      "List directory tree with formatting options (depth, sorting, file info)",
      Type.Object({
        path: Type.String({ description: "Directory path to list" }),
        depth: Type.Optional(Type.Number({ description: "Max depth to traverse" })),
        show: Type.Optional(Type.String({ description: "Show filters: f=files, d=dirs, h=hidden, c=compact, a=all" })),
        sort: Type.Optional(Type.String({ description: "Sort by: name, size, modified, created, type" })),
        limit: Type.Optional(Type.Number({ description: "Max entries per folder" })),
        glob: Type.Optional(Type.String({ description: "Filename glob filter" })),
        info: Type.Optional(Type.String({ description: "Info columns: s=size, m=modified, c=created, g=git, t=type" })),
      }),
    );

    // -- identify ------------------------------------------------------------
    proxyTool("repo39_identify",
      "Detect project type(s) with confidence scores (languages, frameworks, non-code categories)",
      Type.Object({
        path: Type.String({ description: "Directory path to identify" }),
      }),
    );

    // -- map -----------------------------------------------------------------
    proxyTool("repo39_map",
      "Extract code symbols (functions, structs, classes) with line numbers. Supports 13 languages.",
      Type.Object({
        path: Type.String({ description: "Directory or file path to map" }),
        calls: Type.Optional(Type.Boolean({ description: "Include intra-file call graph (default: false)" })),
        glob: Type.Optional(Type.String({ description: "Filename glob filter" })),
        depth: Type.Optional(Type.Number({ description: "Max directory depth" })),
      }),
    );

    // -- deps ----------------------------------------------------------------
    proxyTool("repo39_deps",
      "List dependencies from manifest files (Cargo.toml, package.json, pyproject.toml, go.mod, Gemfile, etc.)",
      Type.Object({
        path: Type.String({ description: "Directory path to scan for manifests" }),
      }),
    );

    // -- changes -------------------------------------------------------------
    proxyTool("repo39_changes",
      "Compact git log of recent file changes, or branch diff with 'branch..HEAD' syntax",
      Type.Object({
        path: Type.String({ description: "Repository path" }),
        ref: Type.Optional(Type.String({ description: "Git ref or range (e.g. 'main..HEAD'). Defaults to recent changes." })),
      }),
    );

    // -- search --------------------------------------------------------------
    proxyTool("repo39_search",
      "Token-compact content search (literal or regex, with context lines and file filtering)",
      Type.Object({
        path: Type.String({ description: "Directory path to search" }),
        pattern: Type.String({ description: "Search pattern (literal by default)" }),
        regex: Type.Optional(Type.Boolean({ description: "Treat pattern as regex (default: false)" })),
        glob: Type.Optional(Type.String({ description: "Filename glob filter" })),
        context: Type.Optional(Type.Number({ description: "Lines of context around matches" })),
      }),
    );

    // -- review --------------------------------------------------------------
    proxyTool("repo39_review",
      "Symbol-level diff vs a git ref (default: HEAD~1). Shows what changed at the function/struct level.",
      Type.Object({
        path: Type.String({ description: "Repository path" }),
        ref: Type.Optional(Type.String({ description: "Git ref to diff against (default: HEAD~1)" })),
      }),
    );

    // -- summary -------------------------------------------------------------
    proxyTool("repo39_summary",
      "One-shot repo orientation: combines identify + deps + map + changes into a single compact output",
      Type.Object({
        path: Type.String({ description: "Repository path" }),
      }),
    );

    // -- cleanup on gateway shutdown -----------------------------------------
    api.on("shutdown", () => {
      if (client) destroyClient(client);
    });

    api.logger.info("repo39 plugin registered");
  },
});
