# Repository guidance

Read [README.md](README.md) for the package, consumer, verification, and release contracts. [sources.lock.json](sources.lock.json) pins the source/configuration inputs; [RELEASE.md](RELEASE.md) describes the published package. Build and integration scripts live in `scripts/`; `smoke/` is the actual Rust consumer check.

Preserve the Windows x64/MSVC static-CRT contract, compatible libgit2 binding range, native backends, and all three Cargo build-script overrides. Keep source hashes, file manifests, corresponding source assets, and license notices intact. Generated Cargo configuration contains absolute local paths and must be regenerated after relocation. Do not add a silent native-source compilation fallback or claim byte-identical output across changing toolchains.

For producer/integration changes, follow the build and relocated-package smoke checks in README and [.github/workflows/release.yml](.github/workflows/release.yml). Compilation alone does not prove HTTPS behavior, absence of native consumer builds, or relocation. Authenticated SSH is not covered by the public smoke test. Documentation-only changes need link, factual consistency, and diff checks; report unrun runtime checks and do not bypass CI.

Source, build-option, package-content, or integration-script changes require the release revision discipline in README. Keep documentation-only maintenance separate from tagging/publishing a new binary package.

## Independent architecture and review

Start each delegated architect, advisor, and reviewer with empty conversation context (`fork_turns="none"` with `spawn_agent`, or the host's equivalent). Provide only the concrete question, repository path and relevant revisions, scope, constraints, and raw evidence locations. Keep the brief focused on the actual topic; omit the author's reasoning, preferred verdict, and earlier agents' conclusions.

Each agent independently inspects the relevant scripts and contracts and reports its own evidence, conclusions, and uncertainty. The final reviewer must be separate from the implementer and design advisor, remain read-only, and inspect the final diff at the named revision. Disclose unavailable independent review rather than presenting self-review as independent.
