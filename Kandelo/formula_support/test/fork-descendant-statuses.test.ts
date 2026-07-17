import assert from "node:assert/strict";
import test from "node:test";

import {
  createForkDescendantTracker,
  parseExpectedForkDescendants,
  validateForkDescendantStatuses,
} from "../fork-descendant-statuses.ts";

test("parses the default all-zero descendant contract", () => {
  const expected = parseExpectedForkDescendants("2", undefined);

  assert.equal(expected.count, 2);
  assert.deepEqual([...expected.statusCounts], [[0, 2]]);
});

test("parses an exact descendant status multiset", () => {
  const expected = parseExpectedForkDescendants(undefined, "[143,0,143]");

  assert.equal(expected.count, 3);
  assert.deepEqual(
    [...expected.statusCounts],
    [
      [143, 2],
      [0, 1],
    ],
  );
});

test("rejects conflicting and malformed descendant status contracts", () => {
  assert.throws(
    () => parseExpectedForkDescendants("2", "[0,143]"),
    /count and statuses cannot both be set/,
  );
  assert.throws(
    () => parseExpectedForkDescendants(undefined, "not-json"),
    /invalid expected fork descendant statuses JSON/,
  );
  for (const value of ["{}", "[]", "[0,-1]", "[0,256]", "[0,1.5]"]) {
    assert.throws(() => parseExpectedForkDescendants(undefined, value));
  }
  for (const value of ["-1", "01", "1.5", "9007199254740992"]) {
    assert.throws(() => parseExpectedForkDescendants(value, undefined));
  }
});

test("accepts an exact descendant status multiset independent of pid order", () => {
  const expected = parseExpectedForkDescendants(undefined, "[0,143]");

  assert.doesNotThrow(() =>
    validateForkDescendantStatuses(
      expected,
      new Set([102, 101]),
      new Map([
        [102, 143],
        [101, 0],
      ]),
    ),
  );
});

test("rejects missing, extra, and unexpected descendant statuses", () => {
  const expected = parseExpectedForkDescendants(undefined, "[0,143]");

  assert.throws(
    () =>
      validateForkDescendantStatuses(
        expected,
        new Set([101]),
        new Map([[101, 0]]),
      ),
    /count mismatch: expected 2, observed 1, exited 1/,
  );
  assert.throws(
    () =>
      validateForkDescendantStatuses(
        expected,
        new Set([101, 102, 103]),
        new Map([
          [101, 0],
          [102, 143],
          [103, 0],
        ]),
      ),
    /count mismatch: expected 2, observed 3, exited 3/,
  );
  assert.throws(
    () =>
      validateForkDescendantStatuses(
        expected,
        new Set([101, 102]),
        new Map([
          [101, 0],
          [102, 139],
        ]),
      ),
    /status mismatch.*139: expected 0, observed 1.*143: expected 1, observed 0/,
  );
});

test("tracks fork spawns through their exit before validating", async () => {
  const expected = parseExpectedForkDescendants("1", undefined);
  const tracker = createForkDescendantTracker();

  tracker.onProcessEvent({ kind: "spawn", pid: 100 });
  tracker.onProcessEvent({ kind: "spawn", pid: 101, ppid: 100 });
  tracker.onProcessEvent({ kind: "exec", pid: 101 });
  const waiting = tracker.waitFor(expected, Date.now() + 1_000);
  setTimeout(
    () => tracker.onProcessEvent({ kind: "exit", pid: 101, exitStatus: 0 }),
    0,
  );

  await assert.doesNotReject(waiting);
});

test("bounds the wait while an observed descendant remains active", async () => {
  const expected = parseExpectedForkDescendants("1", undefined);
  const tracker = createForkDescendantTracker();
  tracker.onProcessEvent({ kind: "spawn", pid: 101, ppid: 100 });

  await assert.rejects(
    tracker.waitFor(expected, Date.now()),
    /timed out waiting for 1 fork descendant\(s\); observed 1, active 101/,
  );
});
