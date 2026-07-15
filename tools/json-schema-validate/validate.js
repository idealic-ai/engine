// Dependency-free JSON Schema validator (draft 2020-12 subset).
// Covers the keywords the engine actually uses for params + proof validation:
// type (incl. type-arrays), required, properties, additionalProperties, items, enum,
// and arbitrary nesting. Errors are written to stderr with the failing path + keyword
// so callers (and tests) can grep for the offending property. Exit 0 = valid, 1 = invalid,
// 2 = usage / malformed input.
'use strict';
const fs = require('fs');

function typeOf(d) {
  if (d === null) return 'null';
  if (Array.isArray(d)) return 'array';
  return typeof d; // object | string | number | boolean
}

function matchesType(data, t) {
  switch (t) {
    case 'object': return typeOf(data) === 'object';
    case 'array': return Array.isArray(data);
    case 'string': return typeof data === 'string';
    case 'number': return typeof data === 'number';
    case 'integer': return typeof data === 'number' && Number.isInteger(data);
    case 'boolean': return typeof data === 'boolean';
    case 'null': return data === null;
    default: return true; // unknown type keyword — don't fail on it
  }
}

function validate(schema, data, path, errors) {
  if (schema === true || schema === undefined || schema === null) return;
  if (schema === false) { errors.push(`${path || '/'}: value not allowed [false]`); return; }

  if (schema.type !== undefined) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((t) => matchesType(data, t))) {
      errors.push(`${path || '/'}: expected type ${types.join('|')} but got ${typeOf(data)} [type]`);
      return; // downstream checks are unreliable once the type is wrong
    }
  }

  if (Array.isArray(schema.enum)) {
    const target = JSON.stringify(data);
    if (!schema.enum.some((v) => JSON.stringify(v) === target)) {
      errors.push(`${path || '/'}: value not in enum [${schema.enum.join(', ')}] [enum]`);
    }
  }

  const isObject = typeOf(data) === 'object';
  if (isObject && (schema.properties || schema.required || schema.additionalProperties !== undefined)) {
    const props = schema.properties || {};
    if (Array.isArray(schema.required)) {
      for (const key of schema.required) {
        if (!(key in data)) {
          errors.push(`${path}/${key}: missing required property '${key}' [required]`);
        }
      }
    }
    for (const key of Object.keys(data)) {
      if (props[key] !== undefined) {
        validate(props[key], data[key], `${path}/${key}`, errors);
      } else if (schema.additionalProperties === false) {
        errors.push(`${path}/${key}: additional property '${key}' not allowed [additionalProperties]`);
      } else if (typeOf(schema.additionalProperties) === 'object') {
        validate(schema.additionalProperties, data[key], `${path}/${key}`, errors);
      }
    }
  }

  if (Array.isArray(data) && schema.items && typeOf(schema.items) === 'object') {
    data.forEach((item, i) => validate(schema.items, item, `${path}/${i}`, errors));
  }
}

function main() {
  const argv = process.argv.slice(2);
  let schemaText, instanceFile;
  if (argv[0] === '--schema-stdin') {
    schemaText = fs.readFileSync(0, 'utf8');
    instanceFile = argv[1];
  } else {
    if (!argv[0]) { process.stderr.write('usage: validate.js <schema> <instance> | --schema-stdin <instance>\n'); process.exit(2); }
    schemaText = fs.readFileSync(argv[0], 'utf8');
    instanceFile = argv[1];
  }
  if (!instanceFile) { process.stderr.write('usage: validate.js <schema> <instance> | --schema-stdin <instance>\n'); process.exit(2); }

  let schema, data;
  try { schema = JSON.parse(schemaText); } catch (e) { process.stderr.write(`invalid schema JSON: ${e.message}\n`); process.exit(2); }
  try { data = JSON.parse(fs.readFileSync(instanceFile, 'utf8')); } catch (e) { process.stderr.write(`invalid instance JSON: ${e.message}\n`); process.exit(2); }

  const errors = [];
  validate(schema, data, '', errors);
  if (errors.length) {
    for (const e of errors) process.stderr.write(e + '\n');
    process.exit(1);
  }
  process.exit(0);
}

main();
