import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { createGuestOutput } from "../guest-output.ts";

const encoder = new TextEncoder();

test("keeps guest stdout and stderr on separate process streams by default", () => {
  const stdout: Uint8Array[] = [];
  const stderr: Uint8Array[] = [];
  const output = createGuestOutput(
    undefined,
    { write: (data) => stdout.push(new Uint8Array(data)) },
    { write: (data) => stderr.push(new Uint8Array(data)) },
  );

  output.onStdout(encoder.encode("guest stdout\n"));
  output.onStderr(encoder.encode("guest stderr\n"));
  output.close();

  assert.equal(Buffer.concat(stdout).toString(), "guest stdout\n");
  assert.equal(Buffer.concat(stderr).toString(), "guest stderr\n");
});

test("writes only guest callbacks to one ordered sink when requested", () => {
  const directory = mkdtempSync(join(tmpdir(), "kandelo-guest-output-"));
  const outputPath = join(directory, "guest-output");
  const stdout: Uint8Array[] = [];
  const stderr: Uint8Array[] = [];

  try {
    const output = createGuestOutput(
      outputPath,
      { write: (data) => stdout.push(new Uint8Array(data)) },
      { write: (data) => stderr.push(new Uint8Array(data)) },
    );
    output.onStdout(encoder.encode("first\n"));
    output.onStderr(encoder.encode("second\n"));
    output.onStdout(encoder.encode("third\n"));
    output.close();
    output.close();

    assert.equal(readFileSync(outputPath, "utf8"), "first\nsecond\nthird\n");
    assert.deepEqual(stdout, []);
    assert.deepEqual(stderr, []);
    assert.throws(
      () => output.onStderr(encoder.encode("late\n")),
      /guest output sink is closed/,
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
