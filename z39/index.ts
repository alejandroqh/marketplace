// OpenClaw native plugin for z39
// Spawns `z39 mcp` and communicates via MCP JSON-RPC over stdio.

import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { Type } from "@sinclair/typebox";
import { spawn, type ChildProcess } from "node:child_process";
import { createInterface, type Interface as ReadlineInterface } from "node:readline";

const CALL_TIMEOUT_MS = 60_000;

// ---------------------------------------------------------------------------
// MCP JSON-RPC client — talks to `z39 mcp` over stdio
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
    entry.reject(new Error("z39 process exited"));
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

  client.initialized = (async () => {
    await rpcCall(client, "initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "openclaw-z39", version: "1.0.0" },
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
      reject(new Error(`z39 RPC timeout: ${method}`));
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
  id: "z39",
  name: "z39",
  description: "Z3-powered SMT reasoning for AI agents — scheduling, logic, config validation, action safety",

  register(api) {
    const config = api.pluginConfig as { binaryPath?: string };
    const binaryPath = config.binaryPath || "z39";
    const extraArgs: string[] = [];

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

    // -- domain tools --------------------------------------------------------

    proxyTool("z39_schedule",
      "Check whether tasks fit within a time slot given duration, ordering, and overlap constraints. Returns feasibility plus an assignment when feasible.",
      Type.Object({
        tasks: Type.Array(Type.Object({
          name: Type.String({ description: "Task identifier" }),
          duration: Type.Integer({ description: "Task duration in minutes" }),
        })),
        slot_start: Type.Integer({ description: "Slot start (minutes from midnight)" }),
        slot_end: Type.Integer({ description: "Slot end (minutes from midnight)" }),
        constraints: Type.Optional(Type.Array(Type.Record(Type.String(), Type.Unknown()), {
          description: "Ordering/timing constraint objects (before, after, no_overlap, etc.)",
        })),
      }),
    );

    proxyTool("z39_logic",
      "Verify a boolean statement — prove always-true, find counterexamples, check equivalence, consistency, or satisfying assignments.",
      Type.Object({
        description: Type.String({ description: "Human-readable query" }),
        check: Type.Object({
          type: Type.Union([
            Type.Literal("always_true"),
            Type.Literal("equivalent"),
            Type.Literal("find_counterexample"),
            Type.Literal("consistent"),
            Type.Literal("find_satisfying"),
          ]),
          vars: Type.Array(Type.String(), { description: "Variable declarations (e.g. 'x:Bool', 'n:Int')" }),
          condition: Type.String({ description: "SMT-LIB2 formula" }),
        }),
      }),
    );

    proxyTool("z39_config",
      "Validate configuration constraint satisfaction. Supports validate, find_valid, and find_violation modes across bool/int/enum variable types.",
      Type.Object({
        mode: Type.Union([
          Type.Literal("validate"),
          Type.Literal("find_valid"),
          Type.Literal("find_violation"),
        ]),
        variables: Type.Array(Type.Record(Type.String(), Type.Unknown()), {
          description: "Variable declarations (type: bool | int with min/max | enum with choices)",
        }),
        constraints: Type.Array(Type.String(), { description: "SMT-LIB2 constraint expressions" }),
        assignment: Type.Optional(Type.Record(Type.String(), Type.Unknown(), {
          description: "Concrete variable assignment to validate (required for mode=validate)",
        })),
      }),
    );

    proxyTool("z39_safety",
      "Pre-check an action against protected resources (file paths, hosts, commands). Rust-only, no Z3 invocation.",
      Type.Object({
        action: Type.Object({
          kind: Type.Union([
            Type.Literal("file_read"),
            Type.Literal("file_write"),
            Type.Literal("file_delete"),
            Type.Literal("command_exec"),
            Type.Literal("network_request"),
            Type.Literal("send_message"),
          ]),
          target: Type.String({ description: "Target of the action (path, URL, command, etc.)" }),
        }, { additionalProperties: true }),
        protected: Type.Array(Type.String(), { description: "Protected resource patterns" }),
      }),
    );

    // -- low-level SMT tools -------------------------------------------------

    proxyTool("z39_solve",
      "Execute a raw SMT-LIB2 formula and return sat/unsat plus a model if satisfiable. Blocks until the solver finishes.",
      Type.Object({
        formula: Type.String({ description: "SMT-LIB2 source" }),
      }),
    );

    proxyTool("z39_solve_async",
      "Start a long-running SMT-LIB2 solve and return a job_id for polling. Use for formulas that may exceed the blocking solve timeout.",
      Type.Object({
        formula: Type.String({ description: "SMT-LIB2 source" }),
      }),
    );

    proxyTool("z39_job_status",
      "Check the status of an async solve job (running, done, cancelled, errored).",
      Type.Object({
        job_id: Type.String({ description: "Job identifier returned by z39_solve_async" }),
      }),
    );

    proxyTool("z39_job_result",
      "Retrieve the result of a completed async solve job.",
      Type.Object({
        job_id: Type.String({ description: "Job identifier returned by z39_solve_async" }),
      }),
    );

    proxyTool("z39_job_cancel",
      "Cancel an in-progress async solve job.",
      Type.Object({
        job_id: Type.String({ description: "Job identifier returned by z39_solve_async" }),
      }),
    );

    // -- cleanup on gateway shutdown -----------------------------------------
    api.on("shutdown", () => {
      if (client) destroyClient(client);
    });

    api.logger.info("z39 plugin registered");
  },
});
