import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

import { rootfsSizeForStagedBytes, validateGuestPath } from "./rootfs-size.ts";

const O_WRONLY = 0x0001;
const O_CREAT = 0x0040;
const O_TRUNC = 0x0200;
const S_IFMT = 0xf000;
const S_IFDIR = 0x4000;

interface PtyConfig {
  env: Record<string, string>;
  inputs: string[];
  rerunInputs?: string[] | null;
  guestFiles?: Record<string, string>;
  guestDirectories?: string[];
  writableGuestDirectories?: string[];
  initialDelayMs: number;
  inputDelayMs: number;
  cols: number;
  rows: number;
}

interface WritableRootfs {
  mkdir(path: string, mode: number): void;
  stat(path: string): { mode: number };
  open(path: string, flags: number, mode: number): number;
  write(
    fd: number,
    data: Uint8Array,
    offset: number | null,
    length: number,
  ): number;
  close(fd: number): void;
}

const delay = (milliseconds: number) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

function createGuestDirectory(rootfs: WritableRootfs, guestPath: string): void {
  const parts = guestPath.split("/").filter(Boolean);
  let current = "";
  for (const part of parts) {
    current += `/${part}`;
    try {
      rootfs.mkdir(current, 0o755);
    } catch (error) {
      if ((rootfs.stat(current).mode & S_IFMT) !== S_IFDIR) throw error;
    }
  }
}

function writeGuestFile(
  rootfs: WritableRootfs,
  guestPath: string,
  bytes: Uint8Array,
): void {
  const parts = guestPath.split("/").filter(Boolean);
  createGuestDirectory(rootfs, `/${parts.slice(0, -1).join("/")}`);

  const fd = rootfs.open(guestPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644);
  try {
    let offset = 0;
    while (offset < bytes.byteLength) {
      const written = rootfs.write(
        fd,
        bytes.subarray(offset),
        null,
        bytes.byteLength - offset,
      );
      if (written <= 0) {
        throw new Error(`short write while staging guest file: ${guestPath}`);
      }
      offset += written;
    }
  } finally {
    rootfs.close(fd);
  }
}

function pathWithin(guestPath: string, guestRoot: string): boolean {
  return guestPath === guestRoot || guestPath.startsWith(`${guestRoot}/`);
}

function writableRootFor(
  guestPath: string,
  writableRoots: readonly string[],
): string | undefined {
  return writableRoots.find((guestRoot) => pathWithin(guestPath, guestRoot));
}

async function main(): Promise<void> {
  const [root, programPath, ...args] = process.argv.slice(2);
  if (!root || !programPath) {
    throw new Error("usage: run-pty-wasm.ts KANDELO_ROOT PROGRAM [ARGS...]");
  }

  const config = JSON.parse(
    process.env.KANDELO_FORMULA_PTY_CONFIG_JSON ?? "{}",
  ) as PtyConfig;
  if (!Array.isArray(config.inputs)) {
    throw new Error(
      "KANDELO_FORMULA_PTY_CONFIG_JSON must contain an inputs array",
    );
  }
  if (config.rerunInputs != null && !Array.isArray(config.rerunInputs)) {
    throw new Error("rerunInputs must be an array when present");
  }

  const guestFiles = config.guestFiles ?? {};
  const guestDirectories = config.guestDirectories ?? [];
  const writableGuestDirectories = config.writableGuestDirectories ?? [];
  if (!Array.isArray(guestDirectories)) {
    throw new Error("guestDirectories must be an array");
  }
  if (!Array.isArray(writableGuestDirectories)) {
    throw new Error("writableGuestDirectories must be an array");
  }

  const moduleUrl = pathToFileURL(
    join(root, "host/src/node-kernel-host.ts"),
  ).href;
  const memoryFsUrl = pathToFileURL(
    join(root, "host/src/vfs/memory-fs.ts"),
  ).href;
  const defaultMountsUrl = pathToFileURL(
    join(root, "host/src/vfs/default-mounts.ts"),
  ).href;
  const [{ NodeKernelHost }, { MemoryFileSystem }, { DEFAULT_MOUNT_SPEC }] =
    await Promise.all([
      import(moduleUrl),
      import(memoryFsUrl),
      import(defaultMountsUrl),
    ]);

  const guestPaths = [
    ...Object.keys(guestFiles),
    ...guestDirectories,
    ...writableGuestDirectories,
  ];
  for (const guestPath of guestPaths) validateGuestPath(guestPath, []);
  for (let i = 0; i < writableGuestDirectories.length; i++) {
    const guestRoot = writableGuestDirectories[i];
    if (guestRoot === "/dev" || guestRoot.startsWith("/dev/")) {
      throw new Error(`writable guest directory overlaps /dev: ${guestRoot}`);
    }
    if (guestRoot === "/proc" || guestRoot.startsWith("/proc/")) {
      throw new Error(`writable guest directory overlaps /proc: ${guestRoot}`);
    }
    for (const otherRoot of writableGuestDirectories.slice(i + 1)) {
      if (
        pathWithin(guestRoot, otherRoot) ||
        pathWithin(otherRoot, guestRoot)
      ) {
        throw new Error(
          `writable guest directories must not overlap: ${guestRoot}, ${otherRoot}`,
        );
      }
    }
  }
  const overlaidRoots = [
    ...DEFAULT_MOUNT_SPEC.filter(
      (mount: { source: string }) => mount.source !== "image",
    ).map((mount: { path: string }) => mount.path),
    "/dev",
    "/proc",
  ];
  for (const guestPath of [...Object.keys(guestFiles), ...guestDirectories]) {
    if (!writableRootFor(guestPath, writableGuestDirectories)) {
      validateGuestPath(guestPath, overlaidRoots);
    }
  }
  for (const guestRoot of writableGuestDirectories) {
    if (overlaidRoots.includes(guestRoot)) {
      throw new Error(
        `writable guest directory conflicts with a runtime mount: ${guestRoot}`,
      );
    }
    if (guestRoot in guestFiles) {
      throw new Error(`guest path is both a file and directory: ${guestRoot}`);
    }
  }
  for (const guestDirectory of guestDirectories) {
    if (guestDirectory in guestFiles) {
      throw new Error(
        `guest path is both a file and directory: ${guestDirectory}`,
      );
    }
  }

  const bytes = readFileSync(programPath);
  const program = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  );
  const guestEnv = config.env ?? {};
  const env = Object.entries(guestEnv).map(([key, value]) => `${key}=${value}`);
  if (!("PATH" in guestEnv)) env.push("PATH=/usr/local/bin:/usr/bin:/bin");

  let writableHostRoot: string | undefined;
  try {
    const stagedFiles = Object.entries(guestFiles)
      .filter(
        ([guestPath]) => !writableRootFor(guestPath, writableGuestDirectories),
      )
      .map(([guestPath, hostPath]) => ({
        guestPath,
        bytes: readFileSync(hostPath),
      }));
    const stagedDirectories = guestDirectories.filter(
      (guestPath) => !writableRootFor(guestPath, writableGuestDirectories),
    );
    let rootfsImage: Uint8Array | undefined;
    if (guestPaths.length > 0) {
      const stagedBytes = stagedFiles.reduce(
        (total, entry) => total + entry.bytes.byteLength,
        0,
      );
      const rootfs = MemoryFileSystem.create(
        new SharedArrayBuffer(rootfsSizeForStagedBytes(stagedBytes)),
      );
      for (const guestDirectory of stagedDirectories) {
        createGuestDirectory(rootfs, guestDirectory);
      }
      for (const entry of stagedFiles) {
        writeGuestFile(rootfs, entry.guestPath, entry.bytes);
      }
      rootfsImage = await rootfs.saveImage();
    }

    const extraMounts: Array<{
      mountPoint: string;
      hostPath: string;
      readonly: boolean;
    }> = [];
    if (writableGuestDirectories.length > 0) {
      // Keep mutable test state off the readonly root image. A single host
      // instance and mount set is reused by both spawns, matching session state.
      writableHostRoot = mkdtempSync(join(tmpdir(), "kandelo-formula-pty-"));
      for (const [index, guestRoot] of writableGuestDirectories.entries()) {
        const hostRoot = join(writableHostRoot, `mount-${index}`);
        mkdirSync(hostRoot, { recursive: true, mode: 0o755 });
        extraMounts.push({
          mountPoint: guestRoot,
          hostPath: hostRoot,
          readonly: false,
        });

        for (const guestDirectory of guestDirectories) {
          if (!pathWithin(guestDirectory, guestRoot)) continue;

          const relativePath = guestDirectory
            .slice(guestRoot.length)
            .replace(/^\/+/, "");
          if (relativePath) {
            mkdirSync(join(hostRoot, relativePath), {
              recursive: true,
              mode: 0o755,
            });
          }
        }
        for (const [guestPath, sourcePath] of Object.entries(guestFiles)) {
          if (!pathWithin(guestPath, guestRoot)) continue;

          const relativePath = guestPath
            .slice(guestRoot.length)
            .replace(/^\/+/, "");
          const destination = join(hostRoot, relativePath);
          mkdirSync(dirname(destination), { recursive: true, mode: 0o755 });
          writeFileSync(destination, readFileSync(sourcePath), { mode: 0o644 });
        }
      }
    }

    const host = new NodeKernelHost({
      maxWorkers: 4,
      rootfsImage,
      extraMounts,
      onPtyOutput: (_pid: number, data: Uint8Array) =>
        process.stdout.write(data),
      onStderr: (_pid: number, data: Uint8Array) => process.stderr.write(data),
    });

    try {
      await host.init();
      const timeoutMs = Number.parseInt(
        guestEnv.TIMEOUT ?? process.env.TIMEOUT ?? "30000",
        10,
      );
      const run = async (inputs: string[]): Promise<number> => {
        const exit = host.spawn(program, [programPath, ...args], {
          cwd: guestEnv.KERNEL_CWD ?? (rootfsImage ? "/" : process.cwd()),
          env,
          pty: true,
          ptyCols: config.cols ?? 100,
          ptyRows: config.rows ?? 30,
          onStarted: async (pid: number) => {
            await delay(config.initialDelayMs ?? 500);
            for (const input of inputs) {
              host.ptyWrite(pid, new TextEncoder().encode(input));
              await delay(config.inputDelayMs ?? 180);
            }
          },
        });
        let timer: ReturnType<typeof setTimeout> | undefined;
        const timeout = new Promise<number>((_resolve, reject) => {
          timer = setTimeout(
            () => reject(new Error(`process timed out after ${timeoutMs}ms`)),
            timeoutMs,
          );
        });
        try {
          return await Promise.race([exit, timeout]);
        } finally {
          if (timer) clearTimeout(timer);
        }
      };

      const firstStatus = await run(config.inputs);
      process.exitCode = firstStatus;
      if (firstStatus === 0 && config.rerunInputs) {
        process.exitCode = await run(config.rerunInputs);
      }
    } finally {
      await host.destroy().catch(() => {});
    }
  } finally {
    if (writableHostRoot) {
      rmSync(writableHostRoot, { recursive: true, force: true });
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
