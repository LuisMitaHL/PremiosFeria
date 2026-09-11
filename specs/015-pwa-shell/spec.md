# Spec 015 — PWA shell

| | |
|---|---|
| **Status** | Implemented |
| **Branch** | `015-pwa-shell` |
| **Actors** | Participant |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

The application is delivered to phones its authors have never seen, over a network they do not
control, in a hall where the signal is whatever it is. There is nothing to download from a store
and nothing to install in the usual sense: an attendee opens a link and is playing.

This spec covers the shell that makes that true — what makes the app installable, how it loads
when the network is poor, and the compatibility floor that decides who can use it at all. It is
the least visible part of the system and the one that decides whether an attendee participates or
stands there with a blank screen.

## 2. Scope

**In scope**

- Installing the app to a phone's home screen: its name, its icon, how it presents itself.
- Loading quickly and reliably on a poor connection.
- Getting a new version to a device that already has one.
- The browser floor the application supports, and why.
- How addresses are formed.

**Out of scope**

- Working offline in any meaningful sense. Every action worth taking needs the server; see the
  business rules.
- Anything a screen does. The other specs own those.
- The infrastructure that serves the files. Spec 026 documents it.

## 3. User scenarios

### 3.1 An attendee installs it

**Given** an attendee who has been given the link
**When** they add it to their home screen
**Then** it appears with the product's name and icon, and opens like an application rather than a
web page with browser furniture around it.

### 3.2 A poor connection

**Given** a hall where the network is congested
**When** an attendee opens the app for the second time
**Then** it appears immediately, because the shell is already on the device, and only the data has
to travel.

### 3.3 A new version during the event

**Given** a correction deployed mid-fair
**When** an attendee next opens the app
**Then** they get the new version without being told to clear anything or reinstall.

### 3.4 An old phone

**Given** an attendee on an old or de-Googled Android browser
**When** they open the app
**Then** it works. It was built for their browser deliberately.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | The application MUST be installable to a phone's home screen. | Must |
| R2 | The installed application MUST show the product's name, as settled by spec 016. | Must |
| R3 | The installed application MUST have an icon, and every icon it declares MUST exist in the format declared. | Must |
| R4 | The installed application MUST open without browser furniture. | Must |
| R5 | The application's own files MUST be served from the device after the first visit, so a second opening does not wait on the network for them. | Must |
| R6 | A newly deployed version MUST reach a device that already has one, without the attendee doing anything unusual. | Must |
| R7 | The application MUST run on the browser floor recorded in ADR 0005, and MUST NOT ship syntax or interfaces newer than it. | Must |
| R8 | The application MUST NOT present itself as working offline when it cannot. | Must |
| R9 | Every address the application uses MUST survive being opened directly, refreshed, and shared. | Must |
| R10 | Nothing stored on the device MUST include a secret, a credential, or another attendee's data. | Must |
| R11 | An exception while rendering MUST NOT leave the attendee on a blank page; the shell MUST say what happened and offer a way back. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Installable | Yes | An attendee who adds it to the home screen does not have to find the link again, and the app gets the full screen for a QR scanner that needs it. |
| Offline | Not supported | Scanning, the leaderboard, the catalogue and every claim need the server. A shell that loads offline into a screen that cannot do anything is worse than one that says the network is gone. What caching buys here is speed, not independence. |
| Updates | Applied automatically | A correction deployed mid-fair has to reach three hundred phones with no way to tell anyone. Asking attendees to reinstall is not an option. |
| Browser floor | Chromium 83 | A visible share of the audience is on old or de-Googled Android browsers. An attendee whose browser cannot run the app cannot participate at all, and there is no desk to fall back to. See ADR 0005. |
| Addresses | Must survive being opened and shared | Someone will send a link to a friend, and someone will refresh mid-fair. An address that only works if you arrived by tapping is an address that fails on the day. |
| What is stored on the device | Nothing that matters | Session state and a cached shell. A shared or borrowed phone must not carry anything that identifies or authorises somebody else. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour |
|---|---|
| The network is unavailable on first visit | Nothing loads, and the browser says so. Nothing can be done about this |
| The network is unavailable on a later visit | The shell appears; anything needing the server fails clearly rather than hanging |
| A new version is deployed while the app is open | It is picked up the next time the app opens, without a reinstall |
| An icon is declared in a format that is not present | It is a defect: the icon must exist in the declared format |
| An address is opened directly rather than navigated to | It resolves to the right screen |
| The app is refreshed mid-session | The attendee stays where they were, still signed in |
| A phone runs a browser older than the floor | Not supported, and stated as such rather than failing mysteriously |
| The app is opened on a shared phone | Nothing from a previous attendee is exposed |

## 7. Security and integrity

- **Cached files are files, not decisions (R10).** What the device holds is the application shell.
  Nothing that authorises anything may be cached, and no attendee's data may be served from
  another attendee's device.
- **The bundle is public.** Everything shipped here is readable by anyone. Nothing in it may be
  secret; the values it carries are a public address and a publishable key by design.
- **Automatic updating is a distribution channel (R6).** It is how a correction reaches the fair,
  and it is also how a mistake would. That is a reason for the quality gates to be real, not a
  reason to make updates manual.
- **The compatibility floor is an availability property (R7).** Shipping syntax the floor does not
  understand does not degrade the experience — it produces a blank screen for that attendee, and
  they cannot participate at all.

## 8. Acceptance criteria

- [ ] The application can be added to a phone's home screen.
- [ ] The installed application shows the product name and an icon.
- [ ] Every icon declared exists in the declared format.
- [ ] The installed application opens without browser furniture.
- [ ] A second visit renders the shell without waiting on the network for it.
- [ ] A newly deployed version reaches a device that already has one, without a reinstall.
- [ ] The application runs on the browser floor.
- [ ] The build emits nothing newer than the floor.
- [x] Any address can be opened directly, refreshed and shared.
- [x] Nothing cached or stored on the device is a secret or another attendee's data.

## 9. Open questions

None.

## 10. As-built notes

| Requirement | Implemented in |
|---|---|
| R1, R4 | `vite.config.js` — the PWA plugin with a `standalone` manifest. |
| R2 | The manifest declares "Community Quest", the name spec 016 settled on. The English subtitle it used to carry was the last piece of an earlier rebrand. |
| R5 | The plugin's precache covers the built JavaScript, CSS, HTML and images. |
| R6 | `registerType: 'autoUpdate'`. |
| R7 | `build.target` and `build.cssTarget` are `chrome83`, `modulePreload.polyfill` is on, and `browserslist` states the floor. |
| R9 | Addresses use a fragment (`HashRouter`, `src/main.jsx`), so any address survives a direct open without server cooperation — and `nginx.conf` also serves the application for unknown paths. |
| R10 | Only the current participant's identifier is kept on the device, as a display cache; the authority is the session. |

**R11 was added after the fact, and it was a real hole.** Every screen already caught the
failures of its own reads, but nothing caught an exception thrown *while React was rendering*:
React unmounts the whole tree and what is left is a white page. An attendee in the middle of a fair
has no way of knowing that reloading fixes it, and nothing on screen says so. `ErrorBoundary`
wraps the application outside the session provider, on purpose — if what fails to render is the
session itself, the net has to still be up. Verified by breaking date formatting mid-render: the
screen showed the message and the button, and the button recovered the dashboard with its points
intact.

**Known deviations**

- **R3 is now met.** The manifest declared `/icon-192.png` and `/icon-512.png` and the page declared
  an apple touch icon in the same format, while `public/` has only SVGs — three files that have
  never existed since the manifest was written. All three now name what is actually served.
- **The manifest link is gone from the page.** It pointed at `/manifest.json` while the plugin
  emits `manifest.webmanifest` and injects its own link, so the hand-written one could only ever
  be wrong. Deleting it is the fix; adding a second correct link would have left two.
- The font requested as `.woff2` now asks for the `.ttf` that is actually there.
- A "Comunity Quest" typo in the page description, which is what an installing browser reads.
- R9 is met by using fragments in addresses, which produces addresses of the form `/#/dashboard`.
  The server already serves the application for unknown paths, so the fragment is belt and braces
  — and it is what makes every address look like a fragment of the home page.
- Spec 025 adds a fifth destination to a navigation bar built for four, which this shell has to
  keep legible on a narrow phone.

The first four were corrected by spec 016.

## 11. References

- ADR 0005 — the Chromium 83 floor and why it exists.
- Constitution: V (secrets never reach the client), VII (the compatibility target).
- Glossary: *Participant*.
- Spec 016 — `naming-and-hygiene-cleanup`, which fixes the icons, the manifest link and the font.
- Spec 025 — `participant-activity-progress`, which adds the fifth navigation destination.
- Spec 026 — `project-documentation`, which documents how this is served.
