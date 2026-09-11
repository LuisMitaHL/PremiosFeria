# Architecture Decision Records

One file per decision, numbered, never renumbered. A decision that is later reversed is not
deleted: it is marked `Superseded by NNNN` and the new ADR explains why.

Write an ADR when a choice constrains future work, is expensive to reverse, or will make someone
ask why on earth it is done this way six months from now. Do not write one for choices a spec
already covers.

Records 0001 to 0005 are **retroactive**: the decisions were made and shipped before this
project adopted spec-driven development, and were reconstructed from the commit history and the
code. They are recorded so the reasoning survives. From 0006 onwards, ADRs are written as part of
the work that needs them.

| # | Decision | Status |
|---|---|---|
| [0001](0001-self-hosted-stack.md) | Leave Supabase Cloud for a minimal self-hosted stack | Accepted |
| [0002](0002-own-auth-service.md) | Replace GoTrue with a zero-dependency auth service | Accepted |
| [0003](0003-polling-over-realtime.md) | Drop realtime in favour of polling plus a CDN microcache | Accepted |
| [0004](0004-business-rules-in-postgres.md) | Keep every game rule in Postgres RPC | Accepted |
| [0005](0005-chromium-83-target.md) | Target Chromium 83 as the compatibility floor | Accepted |
| [0006](0006-statistics-browser-floor.md) | Let the event-statistics area exceed the Chromium 83 floor | Accepted |
