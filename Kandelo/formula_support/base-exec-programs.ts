export type BinaryResolver = (relativePath: string) => string;

export function addDefaultBaseExecPrograms(
  execPrograms: Record<string, string>,
  resolveBinary: BinaryResolver,
): Record<string, string> {
  if (!Object.hasOwn(execPrograms, "/bin/sh")) {
    execPrograms["/bin/sh"] = resolveBinary("programs/dash.wasm");
  }
  return execPrograms;
}
