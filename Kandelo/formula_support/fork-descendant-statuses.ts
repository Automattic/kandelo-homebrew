export interface ExpectedForkDescendants {
  count: number;
  statusCounts: ReadonlyMap<number, number>;
}

function validateExitStatus(status: unknown, index: number): number {
  if (
    !Number.isInteger(status) ||
    (status as number) < 0 ||
    (status as number) > 255
  ) {
    throw new Error(
      `invalid expected fork descendant status at index ${index}: ${String(status)}`,
    );
  }
  return status as number;
}

function statusCounts(statuses: readonly number[]): Map<number, number> {
  const counts = new Map<number, number>();
  for (const status of statuses) {
    counts.set(status, (counts.get(status) ?? 0) + 1);
  }
  return counts;
}

export function parseExpectedForkDescendants(
  countValue: string | undefined,
  statusesJson: string | undefined,
): ExpectedForkDescendants {
  if (statusesJson !== undefined) {
    if (countValue !== undefined) {
      throw new Error(
        "expected fork descendant count and statuses cannot both be set",
      );
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(statusesJson);
    } catch {
      throw new Error(
        `invalid expected fork descendant statuses JSON: ${statusesJson}`,
      );
    }
    if (!Array.isArray(parsed) || parsed.length === 0) {
      throw new Error(
        "expected fork descendant statuses must be a nonempty array",
      );
    }
    const statuses = parsed.map(validateExitStatus);
    return { count: statuses.length, statusCounts: statusCounts(statuses) };
  }

  const value = countValue ?? "0";
  const count = Number(value);
  if (
    !/^(0|[1-9]\d*)$/.test(value) ||
    !Number.isSafeInteger(count) ||
    count < 0
  ) {
    throw new Error(`invalid expected fork descendant count: ${value}`);
  }
  return {
    count,
    statusCounts: count === 0 ? new Map() : new Map([[0, count]]),
  };
}

export function validateForkDescendantStatuses(
  expected: ExpectedForkDescendants,
  descendantPids: ReadonlySet<number>,
  descendantExitStatuses: ReadonlyMap<number, number>,
): void {
  if (
    descendantPids.size !== expected.count ||
    descendantExitStatuses.size !== expected.count
  ) {
    throw new Error(
      `fork descendant count mismatch: expected ${expected.count}, ` +
        `observed ${descendantPids.size}, exited ${descendantExitStatuses.size}`,
    );
  }

  const observedCounts = statusCounts([...descendantExitStatuses.values()]);
  const statuses = new Set([
    ...expected.statusCounts.keys(),
    ...observedCounts.keys(),
  ]);
  const mismatches = [...statuses]
    .sort((left, right) => left - right)
    .filter(
      (status) =>
        (expected.statusCounts.get(status) ?? 0) !==
        (observedCounts.get(status) ?? 0),
    )
    .map(
      (status) =>
        `${status}: expected ${expected.statusCounts.get(status) ?? 0}, ` +
        `observed ${observedCounts.get(status) ?? 0}`,
    );
  if (mismatches.length > 0) {
    const observed = [...descendantExitStatuses]
      .sort(([left], [right]) => left - right)
      .map(([pid, status]) => `${pid}:${status}`)
      .join(", ");
    throw new Error(
      `fork descendant status mismatch (${mismatches.join("; ")}); ` +
        `processes ${observed || "none"}`,
    );
  }
}
