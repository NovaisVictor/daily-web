#!/usr/bin/env node
// Stands in for the agent-deck CLI. Replies are the captured JSON fixtures in
// this directory; sends are appended to $FAKE_DECK_DIR/sends.jsonl.
import { appendFileSync, existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
const here = path.dirname(new URL(import.meta.url).pathname);
const state = process.env.FAKE_DECK_DIR;
const args = process.argv.slice(2);
const fixture = name => readFileSync(path.join(here, name), 'utf8');
if (args[0] === 'list') process.stdout.write(existsSync(path.join(state, 'list.json')) ? readFileSync(path.join(state, 'list.json'), 'utf8') : fixture('list.json'));
else if (args[0] === 'session' && args[1] === 'output') process.stdout.write(fixture(args.includes('--pane') ? 'output-pane.json' : 'output-response.json'));
else if (args[0] === 'session' && args[1] === 'send') {
  if (existsSync(path.join(state, 'refuse'))) { process.stderr.write('refused\n'); process.exit(1); }
  const text = readFileSync(0, 'utf8');
  appendFileSync(path.join(state, 'sends.jsonl'), JSON.stringify({ args, text }) + '\n');
  process.stdout.write(fixture('send-queued.json'));
} else { process.stderr.write('unexpected command\n'); process.exit(2); }
