const unresolvedPlaceholderPattern = /^__VITE_[A-Z0-9_]+__$/;

export function resolveRuntimeEnv(
  placeholder: string,
  viteValue?: string
): string {
  if (unresolvedPlaceholderPattern.test(placeholder)) {
    return viteValue ?? placeholder;
  }

  return placeholder;
}
