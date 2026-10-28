# Release checklist

- [ ] Install full Xcode and build the app target on the minimum supported macOS.
- [ ] Run automated checks, UI tests and the complete media matrix.
- [ ] Record actual format, performance, memory and package-size measurements.
- [ ] Audit licenses and update `THIRD_PARTY_NOTICES.md`.
- [ ] Build an unsigned `.app` for CI; clearly label it as a development artifact. `.github/workflows/release.yml` creates an explicitly `unsigned` zip and SHA-256 checksum on version tags.
- [ ] For distribution, configure Developer ID signing, Hardened Runtime, notarization and stapling using secrets outside the repository.
- [ ] Verify Gatekeeper, SHA-256 and archive contents before publishing.
- [ ] Update `CHANGELOG.md`, version metadata and release notes.

`scripts/package.sh` accepts a validated `SAKURA_VERSION` (semantic version) and numeric `SAKURA_BUILD`. The release workflow derives these from the version tag and workflow run number; local builds default to `0.1.0` / `1`.
