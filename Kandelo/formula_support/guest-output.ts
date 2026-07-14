import { closeSync, openSync, writeSync } from "node:fs";

interface ByteWriter {
  write(data: Uint8Array): unknown;
}

export interface GuestOutput {
  onStdout(data: Uint8Array): void;
  onStderr(data: Uint8Array): void;
  close(): void;
}

function writeAll(fd: number, data: Uint8Array): void {
  let offset = 0;
  while (offset < data.byteLength) {
    const written = writeSync(
      fd,
      data,
      offset,
      data.byteLength - offset,
      null,
    );
    if (written <= 0) throw new Error("short write to guest output sink");
    offset += written;
  }
}

export function createGuestOutput(
  outputPath: string | undefined,
  stdout: ByteWriter = process.stdout,
  stderr: ByteWriter = process.stderr,
): GuestOutput {
  const outputFd = outputPath ? openSync(outputPath, "w") : undefined;
  let closed = false;

  const write = (fallback: ByteWriter, data: Uint8Array): void => {
    if (closed) throw new Error("guest output sink is closed");
    if (outputFd === undefined) {
      fallback.write(data);
      return;
    }
    writeAll(outputFd, data);
  };

  return {
    onStdout: (data) => write(stdout, data),
    onStderr: (data) => write(stderr, data),
    close: () => {
      if (closed) return;
      closed = true;
      if (outputFd !== undefined) closeSync(outputFd);
    },
  };
}
