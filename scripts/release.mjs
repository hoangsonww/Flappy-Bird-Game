#!/usr/bin/env node
/**
 * Derive the next release from Conventional Commits.
 *
 * No third-party release tooling: this reads the git history since the last
 * `v*` tag, picks the bump, and renders grouped release notes. Deterministic,
 * dependency-free, and easy to run locally:
 *
 *   node scripts/release.mjs            # print a human summary
 *   node scripts/release.mjs --json     # machine-readable, used by CI
 *   node scripts/release.mjs --notes    # just the markdown body
 *
 * Bump rules
 *   BREAKING CHANGE / `type!:`  → major
 *   feat                        → minor
 *   fix, perf, revert           → patch
 *   anything else               → no release unless something above appeared
 */

import { execSync } from 'node:child_process';

const RECORD = '\x1e';
const FIELD = '\x1f';

const SECTIONS = [
  ['feat', '✨ Features'],
  ['fix', '🐛 Fixes'],
  ['perf', '⚡ Performance'],
  ['refactor', '♻️ Refactoring'],
  ['docs', '📚 Documentation'],
  ['test', '✅ Tests'],
  ['build', '📦 Build'],
  ['ci', '🤖 CI'],
  ['chore', '🧹 Chores'],
];

const git = (command) => execSync(command, { encoding: 'utf8' }).trim();

function lastTag() {
  try {
    return git('git describe --tags --abbrev=0 --match "v*"');
  } catch {
    return null;
  }
}

function commitsSince(tag) {
  const range = tag ? `${tag}..HEAD` : 'HEAD';
  const raw = git(`git log ${range} --no-merges --pretty=format:%H${FIELD}%s${FIELD}%b${RECORD}`);
  if (!raw) return [];

  return raw
    .split(RECORD)
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [hash, subject, body = ''] = entry.split(FIELD);
      const match = /^(\w+)(\(([^)]+)\))?(!)?:\s*(.+)$/.exec(subject ?? '');
      return {
        hash: (hash ?? '').slice(0, 7),
        type: match?.[1] ?? 'other',
        scope: match?.[3] ?? null,
        breaking: Boolean(match?.[4]) || /BREAKING[ -]CHANGE/.test(body),
        description: match?.[5] ?? subject ?? '',
      };
    });
}

function nextVersion(current, commits) {
  const [major, minor, patch] = current.replace(/^v/, '').split('.').map(Number);

  if (commits.some((commit) => commit.breaking)) return `${major + 1}.0.0`;
  if (commits.some((commit) => commit.type === 'feat')) return `${major}.${minor + 1}.0`;
  if (commits.some((commit) => ['fix', 'perf', 'revert'].includes(commit.type))) {
    return `${major}.${minor}.${patch + 1}`;
  }
  return null;
}

function renderNotes(version, previous, commits) {
  const lines = [`## v${version}`, ''];

  const breaking = commits.filter((commit) => commit.breaking);
  if (breaking.length > 0) {
    lines.push('### ⚠️ Breaking changes', '');
    for (const commit of breaking) {
      lines.push(`- ${commit.scope ? `**${commit.scope}:** ` : ''}${commit.description} (${commit.hash})`);
    }
    lines.push('');
  }

  for (const [type, heading] of SECTIONS) {
    const matching = commits.filter((commit) => commit.type === type && !commit.breaking);
    if (matching.length === 0) continue;
    lines.push(`### ${heading}`, '');
    for (const commit of matching) {
      lines.push(`- ${commit.scope ? `**${commit.scope}:** ` : ''}${commit.description} (${commit.hash})`);
    }
    lines.push('');
  }

  if (previous) {
    const repo = process.env.GITHUB_REPOSITORY ?? 'hoangsonww/Flappy-Bird-Game';
    lines.push(`**Full changelog:** https://github.com/${repo}/compare/${previous}...v${version}`, '');
  }

  return lines.join('\n');
}

const previous = lastTag();
const current = previous ?? 'v0.0.0';
const commits = commitsSince(previous);
const version = nextVersion(current, commits);

const result = {
  previousTag: previous,
  version,
  shouldRelease: Boolean(version),
  commitCount: commits.length,
  notes: version ? renderNotes(version, previous, commits) : '',
};

if (process.argv.includes('--json')) {
  console.log(JSON.stringify(result, null, 2));
} else if (process.argv.includes('--notes')) {
  console.log(result.notes);
} else {
  console.log(`Previous tag : ${previous ?? '(none)'}`);
  console.log(`Commits      : ${commits.length}`);
  console.log(`Next version : ${version ?? '(no release-worthy changes)'}`);
  if (version) console.log(`\n${result.notes}`);
}
