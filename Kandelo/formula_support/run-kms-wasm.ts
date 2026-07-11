import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

async function main(): Promise<void> {
  const [root, programPath, argvJson, minPageFlipsText, timeoutMsText] = process.argv.slice(2);
  if (!root || !programPath || !argvJson || !minPageFlipsText || !timeoutMsText) {
    throw new Error(
      "usage: run-kms-wasm.ts <kandelo-root> <program.wasm> <argv-json> <min-page-flips> <timeout-ms>",
    );
  }

  const argv: unknown = JSON.parse(argvJson);
  if (!Array.isArray(argv) || !argv.every((arg) => typeof arg === "string")) {
    throw new Error("KMS program argv must be a JSON string array");
  }
  const minPageFlips = Number.parseInt(minPageFlipsText, 10);
  const timeoutMs = Number.parseInt(timeoutMsText, 10);
  if (!Number.isSafeInteger(minPageFlips) || minPageFlips < 1) {
    throw new Error(`invalid minimum PAGE_FLIP count: ${minPageFlipsText}`);
  }
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1) {
    throw new Error(`invalid timeout: ${timeoutMsText}`);
  }

  const hostModule = pathToFileURL(resolve(root, "host/src/node-kernel-host.ts")).href;
  const { NodeKernelHost } = await import(hostModule);
  const bytes = readFileSync(programPath);
  const program = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const stderr: Uint8Array[] = [];
  const host = new NodeKernelHost({
    maxWorkers: 2,
    onStderr: (_pid: number, data: Uint8Array) => stderr.push(data.slice()),
  });

  let pid: number | null = null;
  try {
    await host.init();

    const statsBuffer = new SharedArrayBuffer(64);
    const stats = new Int32Array(statsBuffer);
    host.kmsAttachStats(1, statsBuffer);

    let exited = false;
    let exitStatus: number | null = null;
    let exitError: Error | null = null;
    const exit = host.spawn(program, argv, {
      onStarted: async (startedPid: number) => {
        pid = startedPid;
      },
    });
    void exit.then(
      (status: number) => {
        exited = true;
        exitStatus = status;
      },
      (error: unknown) => {
        exited = true;
        exitError = error instanceof Error ? error : new Error(String(error));
      },
    );

    const deadline = Date.now() + timeoutMs;
    while (Atomics.load(stats, 5) < minPageFlips) {
      if (exited) {
        const diagnostics = Buffer.concat(stderr).toString("utf8");
        if (exitError) throw exitError;
        throw new Error(`KMS program exited with status ${exitStatus} before PAGE_FLIP evidence${diagnostics ? `: ${diagnostics}` : ""}`);
      }
      if (Date.now() >= deadline) {
        const diagnostics = Buffer.concat(stderr).toString("utf8");
        throw new Error(`timed out waiting for ${minPageFlips} PAGE_FLIPs${diagnostics ? `: ${diagnostics}` : ""}`);
      }
      await new Promise((resolveDelay) => setTimeout(resolveDelay, 25));
    }

    const flips = Atomics.load(stats, 5);
    if (pid === null) throw new Error("KMS program committed frames before reporting its pid");
    await host.terminateProcess(pid, 0);
    await exit;
    process.stdout.write(`kandelo-kms-ok flips=${flips}\n`);
  } finally {
    await host.destroy().catch(() => {});
  }
}

void main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
