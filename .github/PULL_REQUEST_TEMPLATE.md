## What does this change?

<!-- One or two sentences. What is different after this PR? -->

## Why?

<!-- The problem, the bug report, or the itch this scratches. -->

## Type of change

- [ ] 🐛 Bug fix
- [ ] ✨ New feature
- [ ] ♻️ Refactor
- [ ] 📚 Documentation
- [ ] 🤖 Build / CI
- [ ] ⚠️ Breaking change

## How was it tested?

<!-- Commands you ran and what you saw. Screenshots or a clip for gameplay changes. -->

```bash
# e.g.
make test          # Swift unit tests
make api-test      # backend, in-memory driver
make api-test-pg   # backend, against Postgres
make smoke         # end-to-end against a running API
```

## Checklist

- [ ] The commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) — the release version is derived from them
- [ ] `make check` passes locally
- [ ] New Swift files were added by re-running `make xcodegen` (never by hand-editing the `.pbxproj`)
- [ ] Backend changes are reflected in `backend/openapi/openapi.yaml` and covered by tests
- [ ] Documentation under `docs/` is updated if behaviour changed
- [ ] The game still runs with **no backend at all**

## Screenshots

<!-- `make media` regenerates img/screens from the simulator. -->
