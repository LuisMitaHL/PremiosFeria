# 0003 — Drop realtime in favour of polling plus a CDN microcache

Status: Accepted (retroactive — shipped 2026-09-09)
Relates to: `src/lib/api.js` (`startLeaderboardPolling`), `nginx-cdn.conf.example`

## Context

The leaderboard was driven by Supabase Realtime over WebSockets. Leaving the managed platform
(ADR 0001) meant either running a realtime service ourselves — a second stateful component, for
one screen — or finding another way to keep the board fresh.

The leaderboard is the only live surface in the product, and it does not need to be instant:
attendees glance at it between stands. A few seconds of staleness is invisible.

## Decision

Poll every 5 seconds, and refetch on `focus` and `visibilitychange` so a phone coming out of a
pocket is current. Absorb the resulting load in the CDN with a 5-second microcache on `GET` 200s
under `/rest/v1/`, with a herd lock and stale-while-revalidate.

## Consequences

- One less service to run, and no WebSocket to keep alive through a CDN.
- Three hundred phones polling every 5 seconds collapse to roughly one database query per
  window, because the microcache serves the rest.
- Up to 5 seconds of staleness on the board, plus up to 5 more from the cache. Accepted.
- A participant's own balance still updates immediately after a scan, because that value comes
  from the RPC response, not from the cached list.
- The microcache lives in configuration this repository does not deploy. If the CDN is
  misconfigured, the full polling load reaches Postgres. Verified with the `X-Microcache` header
  during deployment.
