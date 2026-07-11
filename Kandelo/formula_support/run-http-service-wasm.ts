import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

interface RequestSpec {
  method?: string;
  path: string;
  headers?: Record<string, string>;
  body?: string;
}

interface ServiceSpec {
  port: number;
  requests: RequestSpec[];
  mounts: Record<string, string>;
  uid?: number;
  gid?: number;
  timeout_ms: number;
}

function loadProgram(path: string): ArrayBuffer {
  const bytes = readFileSync(path);
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  );
}

async function main(): Promise<void> {
  const [root, programPath, ...args] = process.argv.slice(2);
  if (!root || !programPath) {
    throw new Error(
      "usage: run-http-service-wasm.ts KANDELO_ROOT PROGRAM [ARGS...]",
    );
  }

  const spec = JSON.parse(
    process.env.KANDELO_FORMULA_HTTP_SERVICE_JSON ?? "",
  ) as ServiceSpec;
  if (
    !Number.isInteger(spec.port) ||
    spec.port <= 0 ||
    spec.requests.length === 0
  ) {
    throw new Error(
      "HTTP service test requires a port and at least one request",
    );
  }

  const moduleUrl = pathToFileURL(
    join(root, "host/src/node-kernel-host.ts"),
  ).href;
  const { NodeKernelHost } = await import(moduleUrl);
  const decoder = new TextDecoder();
  const guestEnv = JSON.parse(
    process.env.KANDELO_FORMULA_GUEST_ENV_JSON ?? "{}",
  ) as Record<string, string>;
  const stderr: string[] = [];
  const host = new NodeKernelHost({
    maxWorkers: 8,
    rootfsImage: "default",
    extraMounts: Object.entries(spec.mounts).map(([mountPoint, hostPath]) => ({
      mountPoint,
      hostPath,
    })),
    onStdout: (_pid: number, data: Uint8Array) =>
      stderr.push(decoder.decode(data)),
    onStderr: (_pid: number, data: Uint8Array) =>
      stderr.push(decoder.decode(data)),
  });

  try {
    await host.init();
    let serviceExited = false;
    let serviceStatus: number | undefined;
    const exit = host
      .spawn(loadProgram(programPath), [programPath, ...args], {
        cwd: guestEnv.KERNEL_CWD ?? process.cwd(),
        env: Object.entries(guestEnv).map(([key, value]) => `${key}=${value}`),
        uid: spec.uid,
        gid: spec.gid,
        stdin: new Uint8Array(),
      })
      .then((status: number) => {
        serviceExited = true;
        serviceStatus = status;
        return status;
      });

    const deadline = Date.now() + spec.timeout_ms;
    const responses: Array<Record<string, unknown>> = [];
    for (const request of spec.requests) {
      let response: Awaited<ReturnType<typeof host.fetchInKernel>> | undefined;
      let lastError: unknown;
      while (Date.now() < deadline) {
        if (serviceExited) {
          throw new Error(
            `service exited with status ${serviceStatus}: ${stderr.join("")}`,
          );
        }
        try {
          response = await host.fetchInKernel(
            spec.port,
            {
              method: request.method ?? "GET",
              url: request.path,
              headers: request.headers ?? { Host: "localhost" },
              body:
                request.body === undefined
                  ? null
                  : new TextEncoder().encode(request.body),
            },
            { timeoutMs: 1_000 },
          );
          break;
        } catch (error) {
          lastError = error;
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      }
      if (!response) {
        throw new Error(
          `service did not answer ${request.path}: ${String(lastError)}\n${stderr.join("")}`,
        );
      }
      responses.push({
        status: response.status,
        headers: response.headers,
        body: Buffer.from(response.body).toString("base64"),
        text: decoder.decode(response.body),
      });
    }

    process.stdout.write(`${JSON.stringify(responses)}\n`);
    void exit;
  } finally {
    await host.destroy().catch(() => {});
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
