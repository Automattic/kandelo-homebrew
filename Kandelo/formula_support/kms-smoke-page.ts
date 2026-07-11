import { BrowserKernel } from "@host/browser-kernel-host";
import { ABI_VERSION } from "@host/generated/abi";
import { MemoryFileSystem } from "@host/vfs/memory-fs";
import kernelWasmUrl from "@kernel-wasm?url";

interface KmsSmokeRequest {
  argv: string[];
  minPageFlips: number;
  timeoutMs: number;
  vfsUrl: string;
}

interface KmsSmokeResult {
  pageFlips: number;
  width: number;
  height: number;
  lastFrameUs: number;
  exited: boolean;
  exitCode: number | null;
  stdout: string;
  stderr: string;
}

declare global {
  interface Window {
    __kandeloKmsReady: boolean;
    __runKandeloKmsSmoke: (request: KmsSmokeRequest) => Promise<KmsSmokeResult>;
    __cleanupKandeloKmsSmoke: () => Promise<void>;
  }
}

const canvas = document.getElementById("kms") as HTMLCanvasElement;
const decoder = new TextDecoder();
let kernelBytes: ArrayBuffer | null = null;
let activeKernel: BrowserKernel | null = null;

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

async function fetchBytes(url: string, label: string): Promise<ArrayBuffer> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`${label} fetch failed: ${response.status} ${response.statusText}`);
  }
  return response.arrayBuffer();
}

async function cleanup(): Promise<void> {
  const kernel = activeKernel;
  activeKernel = null;
  await kernel?.destroy().catch(() => {});
}

async function runKmsSmoke(request: KmsSmokeRequest): Promise<KmsSmokeResult> {
  if (!kernelBytes) throw new Error("kernel wasm is not loaded");
  if (!Array.isArray(request.argv) || request.argv.length === 0) {
    throw new Error("argv must contain the guest executable path");
  }
  if (!Number.isSafeInteger(request.minPageFlips) || request.minPageFlips < 1) {
    throw new Error(`invalid minimum PAGE_FLIP count: ${request.minPageFlips}`);
  }
  if (!Number.isSafeInteger(request.timeoutMs) || request.timeoutMs < 1) {
    throw new Error(`invalid timeout: ${request.timeoutMs}`);
  }

  await cleanup();
  const vfsBytes = new Uint8Array(await fetchBytes(request.vfsUrl, "formula VFS"));
  MemoryFileSystem.assertImageKernelAbi(vfsBytes, ABI_VERSION, "formula KMS VFS");

  let stdout = "";
  let stderr = "";
  const kernel = new BrowserKernel({
    kernelOwnedFs: true,
    maxWorkers: 2,
    onStdout: (data) => { stdout += decoder.decode(data); },
    onStderr: (data) => { stderr += decoder.decode(data); },
  });
  activeKernel = kernel;

  let exited = false;
  let exitCode: number | null = null;
  try {
    await kernel.initFromImage({
      kernelWasm: kernelBytes,
      vfsImage: vfsBytes,
    });

    // The GL bridge must own the transferred canvas before the guest calls
    // eglCreateContext. Attaching after spawn can race startup and prove only
    // the kernel's page-flip path while leaving the browser canvas blank.
    const statsBuffer = new SharedArrayBuffer(64);
    const stats = new Int32Array(statsBuffer);
    const offscreen = canvas.transferControlToOffscreen();
    kernel.kmsAttachCanvas(1, offscreen, statsBuffer, { mode: "webgl2" });

    const { exit } = await kernel.spawnFromVfs(request.argv[0], request.argv, {
      cwd: "/",
      env: [
        "HOME=/tmp",
        "TMPDIR=/tmp",
        "TERM=xterm-256color",
        "LANG=C.UTF-8",
        "PATH=/usr/local/bin:/usr/bin:/bin",
      ],
      uid: 0,
      gid: 0,
      stdin: new Uint8Array(),
    });
    void exit.then((status) => {
      exited = true;
      exitCode = status;
    });

    const deadline = performance.now() + request.timeoutMs;
    while (performance.now() < deadline) {
      const flips = Atomics.load(stats, 5);
      const width = Atomics.load(stats, 2);
      const height = Atomics.load(stats, 3);
      if (flips >= request.minPageFlips && width > 0 && height > 0) {
        // Allow the compositor to present the latest OffscreenCanvas frame
        // before the Node runner captures the DOM canvas.
        await delay(500);
        break;
      }
      if (exited) break;
      await delay(50);
    }

    return {
      pageFlips: Atomics.load(stats, 5),
      width: Atomics.load(stats, 2),
      height: Atomics.load(stats, 3),
      lastFrameUs: Atomics.load(stats, 6),
      exited,
      exitCode,
      stdout,
      stderr,
    };
  } catch (error) {
    await cleanup();
    throw error;
  }
}

async function init(): Promise<void> {
  kernelBytes = await fetchBytes(kernelWasmUrl, "kernel.wasm");
  window.__runKandeloKmsSmoke = runKmsSmoke;
  window.__cleanupKandeloKmsSmoke = cleanup;
  window.__kandeloKmsReady = true;
}

window.__kandeloKmsReady = false;
void init();
