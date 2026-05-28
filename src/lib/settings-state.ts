export function isLibrarySourceSaveDisabled(
  inputPath: string,
  savedPath: string,
  isSaving: boolean,
): boolean {
  const nextPath = inputPath.trim();
  return isSaving || nextPath.length === 0 || nextPath === savedPath.trim();
}
