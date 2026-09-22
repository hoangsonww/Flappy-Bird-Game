#!/usr/bin/env tsx
/**
 * Structural validation of `openapi/openapi.yaml` without a network dependency.
 *
 * Checks:
 *  - the document parses and declares OpenAPI 3.1;
 *  - every `$ref` resolves inside the document;
 *  - every operation has a summary, an operationId (unique) and ≥1 response;
 *  - every tag used is declared in the top-level `tags` list.
 *
 *   npm run openapi:validate
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

const here = path.dirname(fileURLToPath(import.meta.url));
const specPath = path.resolve(here, '..', 'openapi', 'openapi.yaml');

interface Spec {
  openapi?: string;
  info?: { title?: string; version?: string };
  tags?: Array<{ name: string }>;
  paths?: Record<string, Record<string, unknown>>;
  components?: Record<string, Record<string, unknown>>;
}

const errors: string[] = [];
const spec = parse(readFileSync(specPath, 'utf8')) as Spec;

if (!spec.openapi?.startsWith('3.1')) errors.push(`Expected OpenAPI 3.1, found ${spec.openapi}`);
if (!spec.info?.title) errors.push('info.title is missing');
if (!spec.info?.version) errors.push('info.version is missing');
if (!spec.paths || Object.keys(spec.paths).length === 0) errors.push('No paths declared');

// ── $ref resolution ──────────────────────────────────────────────────────────
function resolve(ref: string): boolean {
  if (!ref.startsWith('#/')) return false;
  let node: unknown = spec;
  for (const segment of ref.slice(2).split('/')) {
    if (typeof node !== 'object' || node === null) return false;
    node = (node as Record<string, unknown>)[segment.replace(/~1/g, '/').replace(/~0/g, '~')];
    if (node === undefined) return false;
  }
  return true;
}

function walk(node: unknown, pointer: string): void {
  if (Array.isArray(node)) {
    node.forEach((child, index) => walk(child, `${pointer}/${index}`));
    return;
  }
  if (typeof node !== 'object' || node === null) return;

  for (const [key, value] of Object.entries(node as Record<string, unknown>)) {
    if (key === '$ref' && typeof value === 'string' && !resolve(value)) {
      errors.push(`Unresolved $ref "${value}" at ${pointer}`);
    }
    walk(value, `${pointer}/${key}`);
  }
}

walk(spec, '#');

// ── Operation hygiene ────────────────────────────────────────────────────────
const HTTP_METHODS = new Set(['get', 'put', 'post', 'delete', 'patch', 'head', 'options', 'trace']);
const declaredTags = new Set((spec.tags ?? []).map((tag) => tag.name));
const operationIds = new Map<string, string>();
let operationCount = 0;

for (const [pathKey, operations] of Object.entries(spec.paths ?? {})) {
  for (const [method, operation] of Object.entries(operations)) {
    if (!HTTP_METHODS.has(method)) continue;
    operationCount += 1;

    const op = operation as {
      summary?: string;
      operationId?: string;
      tags?: string[];
      responses?: Record<string, unknown>;
    };
    const label = `${method.toUpperCase()} ${pathKey}`;

    if (!op.summary) errors.push(`${label}: missing summary`);
    if (!op.operationId) {
      errors.push(`${label}: missing operationId`);
    } else if (operationIds.has(op.operationId)) {
      errors.push(
        `${label}: operationId "${op.operationId}" already used by ${operationIds.get(op.operationId)}`,
      );
    } else {
      operationIds.set(op.operationId, label);
    }
    if (!op.responses || Object.keys(op.responses).length === 0) {
      errors.push(`${label}: no responses documented`);
    }
    for (const tag of op.tags ?? []) {
      if (!declaredTags.has(tag)) errors.push(`${label}: undeclared tag "${tag}"`);
    }
    if ((op.tags ?? []).length === 0) errors.push(`${label}: no tags`);
  }
}

// ── Report ───────────────────────────────────────────────────────────────────
if (errors.length > 0) {
  console.error(`\n✖ openapi.yaml has ${errors.length} problem(s):\n`);
  for (const error of errors) console.error(`  • ${error}`);
  console.error('');
  process.exit(1);
}

console.log(
  `✓ openapi.yaml is valid — ${Object.keys(spec.paths ?? {}).length} paths, ` +
    `${operationCount} operations, ${Object.keys(spec.components?.schemas ?? {}).length} schemas.`,
);
