/**
 * Agent RPC Command Registry — side-effect barrel file.
 *
 * Importing this module registers all agent.* RPC handlers into the shared dispatch map.
 * Each import below triggers a top-level `registerCommand()` call in the imported file.
 *
 * Entry point: daemon.ts imports this once at startup.
 * Adding a new RPC: create the handler file, add an import line here.
 *
 * Namespaces:
 *   agent.directives.*  — directive discovery, dereferencing, resolution
 *   agent.skills.*      — SKILL.md parsing and skill listing
 */

// agent.directives.* RPCs
import "./agent-directives-discover.js";
import "./agent-directives-dereference.js";
import "./agent-directives-resolve.js";

// agent.skills.* RPCs
import "./agent-skills-parse.js";
import "./agent-skills-list.js";

// agent.messages.* RPCs
import "./agent-messages-ingest.js";
