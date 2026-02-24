# engine-agent

Convention and workspace RPC handlers for directives and skills.

## Purpose

Provides RPC handlers that understand the engine's convention layer:
directive file discovery, sigil reference extraction, reference resolution,
and SKILL.md parsing. These handlers port bash logic from `lib.sh` and
`discover-directives.sh` into structured TypeScript with Zod validation.

Zero database dependency. All handlers operate on the local filesystem
using engine conventions (`.directives/` directories, SKILL.md files).

## Handlers

### agent.directives.discover

Walk-up `.directives/` scanning with pattern filtering. Ports
`discover-directives.sh` logic.

Scans target directories and their ancestors for directive files,
respecting a project root boundary. Checks `.directives/FILENAME` first
(preferred), then falls back to flat `dir/FILENAME` (legacy layout).
Also discovers `CMD_*.md` files in `.directives/commands/` subdirectories.

**Schema:**

```typescript
{
  dirs: string[];             // directories to scan (min 1)
  walkUp?: boolean;           // walk up to root (default: true)
  patterns?: string[];        // filter to specific directive types
  root?: string;              // project root boundary (default: cwd)
}
```

**Response:**

```typescript
{
  files: Array<{
    path: string;     // absolute resolved path to the directive file
    type: "soft" | "hard";
    source: string;   // directory where the file was found
  }>
}
```

**Directive types:**

- Core (always discovered): `AGENTS.md`, `INVARIANTS.md`,
  `ARCHITECTURE.md`, `COMMANDS.md`
- Skill-filtered (only when matching `patterns`): `TESTING.md`,
  `PITFALLS.md`, `CONTRIBUTING.md`, `TEMPLATE.md`, `CHECKLIST.md`

When `patterns` is provided, core directives are always included plus
any skill directives matching the filter. When omitted, all directive
types are discovered.

### agent.directives.dereference

Extract `§CMD_*`, `§FMT_*`, and `§INV_*` references from file content.

Ports the extraction step of `resolve_refs()` from `lib.sh`. Uses a
two-pass filter: (1) strip code fences and backtick spans to avoid
false positives, (2) extract bare sigil references from the cleaned text.

**Schema:**

```typescript
{
  path?: string;      // file to read and dereference
  content?: string;   // raw content to dereference (alternative to path)
}
// At least one of path or content must be provided.
```

**Response:**

```typescript
{
  refs: Array<{
    sigil: string;    // always "§"
    prefix: string;   // "CMD", "FMT", or "INV"
    name: string;     // full name, e.g., "CMD_DEHYDRATE"
    raw: string;      // raw match, e.g., "§CMD_DEHYDRATE"
  }>
}
```

Refs are deduplicated -- each unique reference appears once regardless
of how many times it occurs in the content.

### agent.directives.resolve

Resolve reference names to file paths via walk-up search with engine
fallback.

Ports the resolution step of `resolve_refs()` from `lib.sh`. Given a
list of refs, walks up from `startDir` checking
`.directives/{folder}/{NAME}.md` at each level, then falls back to
`~/.claude/engine/.directives/{folder}/`.

**Schema:**

```typescript
{
  refs: Array<{
    prefix: string;       // "CMD", "FMT", or "INV"
    name: string;         // e.g., "CMD_DEHYDRATE"
  }>;                     // min 1
  startDir: string;       // directory to start walk-up from
  projectRoot?: string;   // boundary for walk-up (default: cwd)
}
```

**Response:**

```typescript
{
  resolved: Array<{
    ref: string;              // e.g., "§CMD_DEHYDRATE"
    path: string | null;      // resolved file path, or null if not found
    searchedDirs: string[];   // directories checked during resolution
  }>
}
```

**Prefix-to-folder mapping:**

| Prefix | Folder |
|---|---|
| `CMD` | `commands/` |
| `FMT` | `formats/` |
| `INV` | `invariants/` |

### agent.skills.parse

Parse a SKILL.md file and extract structured skill data from its YAML
frontmatter and JSON configuration block.

Ports the JSON extraction from `resolve_phase_cmds()` in `lib.sh`.

**Schema:**

```typescript
{
  skillPath: string;   // absolute path to SKILL.md
}
```

**Response:**

```typescript
{
  skill: {
    name: string | null;
    version: string | null;
    description: string | null;
    tier: "protocol" | "utility";
    phases: object[] | null;        // from JSON block
    modes: object | null;           // from JSON block
    templates: {
      plan: string | null;
      log: string | null;
      debrief: string | null;
      request: string | null;
      response: string | null;
    } | null;
    nextSkills: string[] | null;
    directives: string[] | null;
  }
}
```

Frontmatter fields (`name`, `version`, `description`, `tier`) come from
the YAML `---` block. All other fields come from the first ` ```json `
block in the file. If no JSON block exists, those fields are `null`.

**Error codes:**

| Error Code | Meaning |
|---|---|
| `FS_NOT_FOUND` | SKILL.md file does not exist |
| `PARSE_ERROR` | JSON block contains invalid JSON |

### agent.skills.list

Discover available skills from search directories.

Scans default skill directories for subdirectories containing a
`SKILL.md` file. Returns name, path, and tier for each discovered skill.

**Schema:**

```typescript
{
  searchDirs?: string[];   // override default search directories
}
```

**Default search directories:**

1. `~/.claude/skills/`
2. `~/.claude/engine/skills/`
3. `{cwd}/.claude/skills/` (if it exists)

**Response:**

```typescript
{
  skills: Array<{
    name: string;                    // directory name (e.g., "implement")
    path: string;                    // absolute path to SKILL.md
    tier: "protocol" | "utility";    // detected from frontmatter or heuristic
  }>
}
```

Skills are sorted alphabetically by name. When the same skill name
appears in multiple search directories, the first occurrence wins.

## Files

```
src/
  rpc/
    agent-directives-discover.ts
    agent-directives-dereference.ts
    agent-directives-resolve.ts
    agent-skills-parse.ts
    agent-skills-list.ts
  __tests__/
    agent-directives-discover.test.ts
    agent-directives-dereference.test.ts
    agent-directives-resolve.test.ts
    agent-skills.test.ts
```

## Tests

46 tests across 4 test files.
