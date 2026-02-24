/**
 * Master RPC Registry — imports all namespace registries.
 *
 * Daemon imports this single file to populate the dispatch map
 * with handlers from all namespaces.
 */

// Namespace registries — each triggers side-effect registerCommand() calls
import "../../db/src/rpc/registry.js";
import "../../hooks/src/rpc/registry.js";
import "../../ai/src/rpc/registry.js";
import "../../search/src/rpc/registry.js";
import "../../fs/src/rpc/registry.js";
import "../../agent/src/rpc/registry.js";
import "../../commands/src/rpc/registry.js";
