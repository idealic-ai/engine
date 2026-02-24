/**
 * FS RPC Command Registry — side-effect barrel file.
 *
 * Importing this module registers all fs.* RPC handlers into the shared dispatch map.
 * Each import below triggers a top-level `registerCommand()` call in the imported file.
 *
 * Entry point: daemon.ts imports this once at startup.
 * Adding a new RPC: create the handler file, add an import line here.
 *
 * Namespaces:
 *   fs.paths.*  — path normalization and resolution
 *   fs.files.*  — file read/write operations
 */

// fs.paths.* RPCs
import "./fs-paths-resolve.js";

// fs.files.* RPCs
import "./fs-files-read.js";
import "./fs-files-append.js";
import "./fs-files-stat.js";

// fs.dirs.* RPCs
import "./fs-dirs-list.js";
