# OpenClaw Marketplace

Self-hosted OpenClaw plugin marketplace by Alejandro Quintanar.

## What This Is

A marketplace repo for `openclaw plugins install <plugin> --marketplace <source>`.
Each plugin lives in its own subdirectory with a full OpenClaw native plugin structure.

## Structure

```
openclaw-marketplace/
├── .claude-plugin/
│   └── marketplace.json        # Plugin index — lists all available plugins
├── browser39/                  # Each plugin gets its own directory
│   ├── openclaw.plugin.json    # Plugin manifest (id, configSchema, contracts)
│   ├── package.json            # npm metadata + openclaw.extensions + dependencies
│   └── index.ts                # Plugin entry (definePluginEntry + register)
├── <next-plugin>/
│   └── ...
└── CLAUDE.md
```

## Adding a New Plugin

1. Create a subdirectory: `mkdir <plugin-name>`
2. Add required files inside it:
   - `openclaw.plugin.json` — must have `id` and `configSchema` at minimum
   - `package.json` — must have `openclaw.extensions`, `openclaw.compat`, and all `dependencies`
   - `index.ts` — export `definePluginEntry({ id, register(api) { ... } })`
3. Register in `.claude-plugin/marketplace.json` under the `plugins` array:
   ```json
   {
     "name": "plugin-id",
     "source": "../plugin-id",
     "description": "What it does",
     "author": { "name": "Alejandro Quintanar" },
     "repository": "https://github.com/alejandroqh/<repo>",
     "license": "MIT",
     "keywords": [],
     "category": "tools",
     "tags": []
   }
   ```
4. Run `cd <plugin-name> && npm install` to install dependencies

## Plugin File Reference

### openclaw.plugin.json (required)
```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "description": "Brief description",
  "version": "1.0.0",
  "contracts": {
    "tools": ["tool_name_1", "tool_name_2"]
  },
  "configSchema": {
    "type": "object",
    "additionalProperties": false,
    "properties": {}
  }
}
```

### package.json (required)
```json
{
  "name": "@aquintanar/openclaw-<plugin>",
  "version": "1.0.0",
  "type": "module",
  "openclaw": {
    "extensions": ["./index.ts"],
    "compat": {
      "pluginApi": ">=2026.3.24-beta.2",
      "minGatewayVersion": "2026.3.24-beta.2"
    }
  },
  "dependencies": {}
}
```

### index.ts (required)
```typescript
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { Type } from "@sinclair/typebox";

export default definePluginEntry({
  id: "my-plugin",
  name: "My Plugin",
  description: "What it does",
  register(api) {
    api.registerTool({
      name: "my_tool",
      description: "Tool description",
      parameters: Type.Object({ input: Type.String() }),
      async execute(_id, params) {
        return { content: [{ type: "text", text: `Result: ${params.input}` }] };
      },
    });
  },
});
```

## Installation (end users)

```bash
# From GitHub marketplace
openclaw plugins install browser39 --marketplace https://github.com/alejandroqh/openclaw-marketplace

# List available plugins
openclaw plugins marketplace list https://github.com/alejandroqh/openclaw-marketplace

# Local dev (link, no copy)
openclaw plugins install ./browser39 -l
```

## Constraints

- Plugin sources MUST be relative paths within this repo (OpenClaw security requirement)
- Each plugin MUST have its dependencies in package.json (no implicit deps)
- `@sinclair/typebox` is the standard for parameter schemas — add it to dependencies
- Always import from `openclaw/plugin-sdk/<subpath>` — never monolithic root imports
- Run `npm install` in each plugin directory after cloning

## Categories

Use these for the `category` field in marketplace.json:
- `tools` — Agent tools (browser, search, file ops)
- `channels` — Messaging channels (Slack, Telegram, etc.)
- `providers` — Model/service providers
- `devops` — Infrastructure and deployment
- `utilities` — General-purpose utilities
