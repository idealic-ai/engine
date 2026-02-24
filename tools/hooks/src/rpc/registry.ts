/**
 * hooks.* RPC Command Registry — side-effect barrel file.
 *
 * 4 core hook handlers + 11 stubs = 15 Claude Code hook events.
 */

import "./hooks-session-start.js";
import "./hooks-pre-tool-use.js";
import "./hooks-post-tool-use.js";
import "./hooks-user-prompt.js";
import "./hooks-post-tool-use-failure.js";
import "./hooks-permission-request.js";
import "./hooks-notification.js";
import "./hooks-subagent-start.js";
import "./hooks-subagent-stop.js";
import "./hooks-stop.js";
import "./hooks-teammate-idle.js";
import "./hooks-task-completed.js";
import "./hooks-pre-compact.js";
import "./hooks-session-end.js";
import "./hooks-fleet-start.js";
