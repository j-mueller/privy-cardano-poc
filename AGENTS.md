# Agent Instructions

When building the Haskell backend:

1. Change directory to `src/backend`.
2. Enter and run commands through the Nix shell for this project.

Use this pattern:

```bash
cd src/backend
nix develop ../.. -c cabal build
```

Do not run backend builds outside `src/backend`, and do not run `cabal build` outside the Nix shell.
