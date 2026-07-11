import { posix } from "node:path";

const ROOTFS_BLOCK_SIZE = 4096;
const MIN_ROOTFS_SIZE = 2 * 1024 * 1024;
const ROOTFS_HEADROOM = 1024 * 1024;

export function rootfsSizeForStagedBytes(stagedBytes: number): number {
  if (!Number.isSafeInteger(stagedBytes) || stagedBytes < 0) {
    throw new Error(`invalid staged byte count: ${stagedBytes}`);
  }

  const stagedCapacity = stagedBytes * 2 + ROOTFS_HEADROOM;
  if (!Number.isSafeInteger(stagedCapacity)) {
    throw new Error(`staged byte count is too large: ${stagedBytes}`);
  }

  const requested = Math.max(MIN_ROOTFS_SIZE, stagedCapacity);
  return Math.ceil(requested / ROOTFS_BLOCK_SIZE) * ROOTFS_BLOCK_SIZE;
}

export function validateGuestPath(
  guestPath: string,
  overlaidRoots: readonly string[],
): void {
  if (
    guestPath === "/" ||
    !guestPath.startsWith("/") ||
    guestPath.includes("\0") ||
    posix.normalize(guestPath) !== guestPath
  ) {
    throw new Error(
      `guest file path must be absolute and normalized: ${guestPath}`,
    );
  }

  const overlaidRoot = overlaidRoots.find(
    (root) => guestPath === root || guestPath.startsWith(`${root}/`),
  );
  if (overlaidRoot) {
    throw new Error(
      `guest file path is hidden by the ${overlaidRoot} runtime mount: ${guestPath}`,
    );
  }
}
