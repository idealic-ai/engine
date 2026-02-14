#!/usr/bin/env node
// json-schema-validate — validates a JSON instance against a JSON Schema
// Usage: node validate.js <schema-file> <instance-file>
//        node validate.js --schema-stdin <instance-file>   (schema on stdin)
// Exit 0 = valid, Exit 1 = invalid (errors on stderr)

import Ajv from "ajv";
import addFormats from "ajv-formats";
import { readFileSync } from "fs";

const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);

function usage() {
  console.error("Usage: validate.js <schema-file> <instance-file>");
  console.error("       validate.js --schema-stdin <instance-file>");
  process.exit(2);
}

const args = process.argv.slice(2);
if (args.length < 2) usage();

let schemaJson, instanceJson;

try {
  if (args[0] === "--schema-stdin") {
    // Schema from stdin (piped), instance from file
    const stdinBuf = readFileSync(0, "utf-8");
    schemaJson = JSON.parse(stdinBuf);
    delete schemaJson["$schema"];
    instanceJson = JSON.parse(readFileSync(args[1], "utf-8"));
  } else {
    // Both from files
    schemaJson = JSON.parse(readFileSync(args[0], "utf-8"));
    delete schemaJson["$schema"];
    instanceJson = JSON.parse(readFileSync(args[1], "utf-8"));
  }
} catch (err) {
  console.error(`Error reading input: ${err.message}`);
  process.exit(2);
}

const validate = ajv.compile(schemaJson);
const valid = validate(instanceJson);

if (valid) {
  process.exit(0);
} else {
  // Format errors for human readability
  for (const err of validate.errors) {
    const path = err.instancePath || "(root)";
    console.error(`  ${path}: ${err.message}`);
    if (err.params) {
      const details = Object.entries(err.params)
        .map(([k, v]) => `${k}=${v}`)
        .join(", ");
      if (details) console.error(`    (${details})`);
    }
  }
  process.exit(1);
}
