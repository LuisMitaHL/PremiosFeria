# 0006 — The statistics area may exceed the Chromium 83 floor

Status: Accepted
Relates to: `specs/031-event-statistics/spec.md`, `vite.config.js`, `package.json`

## Context

ADR 0005 sets Chromium 83 as the compatibility floor for the whole application, because attendees
run old or de-Googled Android browsers and an attendee whose browser cannot run the app cannot
participate at all. That reasoning is about the attendee's phone and the stand's device.

Spec 031 adds an event-statistics area. It is reachable only by the event operator, who works from
a laptop at the organisation desk, and it is opened after the fair — not by attendees, not on the
stand's tablet, and not on the critical path of any scan. Charting libraries routinely depend on
runtime APIs newer than Chromium 83, and the team chose to accept reduced rendering there rather
than hand-draw every figure.

## Decision

The participant and stand surfaces keep the Chromium 83 floor unchanged. The event-statistics
area is allowed to use a rendering dependency whose runtime exceeds that floor; on Chromium 83 it
may render partially or not at all, and the operator sees a statement that the browser is
unsupported. The dependency is loaded only when the statistics area is opened, so it is never
part of what an attendee or a stand downloads.

This ADR accepts the exclusion required by the constitution (principle VII) for that area and no
other. It records a decision, not a permission to lower the floor elsewhere.

## Consequences

- The build target stays `chrome83`; the exclusion is about runtime behaviour in one lazily
  loaded area, not about changing what the toolchain emits for shared code.
- New syntax or Web APIs newer than Chromium 83 remain forbidden in every surface a participant or
  a stand can load.
- The charting dependency must be loaded only when the statistics area is opened. If it ever leaks
  into the initial bundle, every attendee pays for a screen only the operator uses and this
  decision no longer holds.
- An operator who insists on Chromium 83 cannot read statistics. The acceptance is explicit: the
  operator's environment is a current laptop, and the fairness of the trade is that the
  constrained audience is never asked to run this code.
