# 0005 — Target Chromium 83 as the compatibility floor

Status: Accepted (retroactive — shipped 2026-03-06)
Relates to: `vite.config.js`, `package.json` (`browserslist`)

## Context

The audience is students at a Bolivian university fair, on their own phones. A visible share of
them run old or de-Googled Android browsers — Bromite in particular, whose last release is based
on Chromium 83. An attendee whose browser cannot run the app cannot participate at all: there is
no desk to fall back to.

## Decision

Set `build.target` and `build.cssTarget` to `chrome83`, declare `chrome >= 83` and
`chromeAndroid >= 83` in `browserslist`, and enable `modulePreload.polyfill`.

No legacy bundle is shipped. Chromium 83 already supports native ES modules, dynamic `import()`
and `import.meta`, so the only requirement is that the toolchain stop emitting newer syntax.

## Consequences

- Language and Web API features newer than Chromium 83 are unavailable, including several that
  modern tooling emits by default. New dependencies must be checked against this floor.
- Introducing something newer requires an ADR that accepts excluding those attendees.
- No SystemJS or legacy bundle means no size penalty for the majority on current browsers.
