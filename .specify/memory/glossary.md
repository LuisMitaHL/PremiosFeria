# Domain Glossary

Specs are written in English; the team speaks Spanish and the UI is in Spanish. This table is
the binding translation. **Use the English term in specs, plans and code; use the Spanish term
in the UI and in commit messages.** Never invent a third name for a concept that already has a
row here.

| English (specs, code) | Spanish (UI, team) | Meaning |
|---|---|---|
| Participant | Participante / Asistente | A fair attendee. Registers with a name only, holds an anonymous session. Stored in `participants`. |
| Stand | Stand / Comunidad | A booth run by a student community. **Stored in the table `communities`** for historical reasons — the table was renamed from `groups` and never renamed again. Treat "stand" and "community" as the same entity. |
| Stand admin | Admin de stand | The person operating a stand, authenticated with the stand's username and password. Not a separate table: the stand *is* the identity (`communities.auth_user_id = communities.id`). |
| Event operator | Operador del evento | The person who deploys and provisions the event. Has no account in the app today; works through CSV files, `psql` and `docker compose`. |
| Scan | Escaneo | One accepted award of points to a participant by a stand. Stored in `scans`. Type is `visit` or `activity`. |
| Visit | Visita | A repeatable scan type. Awards up to 30 points, subject to a 5-minute per-stand cooldown. |
| Activity | Actividad | A once-per-stand scan type. Awards up to 100 points. Enforced by a partial unique index. |
| Points | Puntos | The event currency. Earned by scanning, spent by claiming. Never negative. |
| Reward | Premio | A physical prize offered by a stand, with a point cost and a stock. Stored in `rewards`. |
| Claim | Canje | A participant exchanging points for a reward. Stored in `claimed_rewards`. |
| Fulfilment | Entrega | The physical handover of a claimed reward at the stand. Not modelled in the system today. |
| Rotation window | Ventana de rotación | The 15-second slot a signed QR code is valid for (`epoch / 15`). One window of backward tolerance is accepted. |
| Short code | Código manual | The 6 uppercase hex characters at the head of the HMAC, typed by hand when the camera is unavailable. |
| Leaderboard | Ranking | The public ordering of participants by points. Refreshed by polling every 5 seconds. |
| Signed payload | Payload firmado | The JSON blob a QR encodes: stand id, window, points, type, and the HMAC token that authenticates them. |

## Terms deliberately avoided

- **"Group"** — the original name of `communities`. Do not reintroduce it.
- **"Emoji"** — the column `communities.emoji` and `rewards.emoji` now store **Lucide icon
  names**, not emoji characters. `src/components/DynamicIcon.jsx` keeps a fallback for legacy
  rows. Call it the *icon* in specs; the column name is legacy.
- **"User"** — ambiguous between participant, stand admin and operator. Always name the actor.
- **"Admin"** on its own — say *stand admin* or *event operator*.
