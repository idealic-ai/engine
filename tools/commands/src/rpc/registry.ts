/**
 * Commands registry — self-registering barrel file.
 *
 * Importing this file registers all commands.* RPC handlers.
 * The daemon imports this at startup alongside db/fs/agent registries.
 */
import "./commands-effort-start.js";
import "./commands-efforts-resume.js";
import "./commands-log-append.js";
