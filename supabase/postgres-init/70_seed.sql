-- 70_seed.sql — runs ONCE at Postgres init (empty ./data/db only).
-- Reads operator CSVs mounted at /seed (see db volumes in docker-compose.yml):
--   stands.csv   header: user,pw,name            (OPTIONAL)
--   rewards.csv  header: stand,name,description,cost,stock,emoji (OPTIONAL,
--                header-only allowed for "stands only")
-- Both inputs are optional. An empty ./seed is the normal case for a brand-new
-- fair: no stands are loaded, only the organiser account (71) is created, and
-- every stand is then created from the panel. A file that is present but
-- malformed still aborts loudly, because a half-seeded fair is worse than a
-- refused boot.
-- Reseed = down + rm -rf ./data/db + up.
--
-- Identity model (no GoTrue): stands log in with bare usernames against
-- communities.password_hash (bcrypt). communities.auth_user_id = own id, so
-- both app session paths resolve (user_metadata.community_id from the JWT,
-- and the communities-by-auth_user_id fallback).
-- Rows with blank user/pw are ignored; blank names / bad costs abort loudly.

BEGIN;

-- 0. Staging ---------------------------------------------------------------
CREATE TEMP TABLE stage_stands (
  user_ TEXT,
  pw_   TEXT,
  name_ TEXT
) ON COMMIT DROP;
-- \copy is client-side, so SQL cannot test for the file. A backtick \set asks the
-- shell and \if skips the load when the operator supplied nothing.
\set stands_file `test -f /seed/stands.csv && echo true || echo false`
\if :stands_file
\copy stage_stands FROM '/seed/stands.csv' WITH (FORMAT csv, HEADER true)
\endif

CREATE TEMP TABLE stage_rewards (
  stand_       TEXT,
  name_        TEXT,
  description_ TEXT,
  cost_        TEXT,
  stock_       TEXT,
  emoji_       TEXT
) ON COMMIT DROP;
\set rewards_file `test -f /seed/rewards.csv && echo true || echo false`
\if :rewards_file
\copy stage_rewards FROM '/seed/rewards.csv' WITH (FORMAT csv, HEADER true)
\endif

-- 1. Communities (username = bare login name; bcrypt hash via pgcrypto) ------
INSERT INTO communities (username, name, password_hash)
-- btrim on the password too: dev's csv-seed.mjs trims every field, and a padded
-- value here would store a hash of the padding while the stand types the visible
-- password. Same input must hash the same in both paths.
SELECT btrim(user_), NULLIF(btrim(name_), ''), crypt(btrim(pw_), gen_salt('bf', 12))
FROM stage_stands
WHERE NULLIF(btrim(user_), '') IS NOT NULL
  AND NULLIF(btrim(pw_), '') IS NOT NULL
ON CONFLICT (username) DO NOTHING;

-- Link each stand to its own id (auth_user_id = JWT sub for stand sessions).
UPDATE communities SET auth_user_id = id WHERE auth_user_id IS NULL;

-- 2. Rewards (stand = username of the owning community) -----------------------
INSERT INTO rewards (community_id, name, description, cost, stock, emoji)
SELECT c.id,
       NULLIF(btrim(r.name_), ''),
       NULLIF(btrim(r.description_), ''),
       NULLIF(btrim(r.cost_), '')::int,
       COALESCE(NULLIF(btrim(r.stock_), '')::int, 0),
       COALESCE(NULLIF(btrim(r.emoji_), ''), 'Gift')
FROM stage_rewards r
JOIN communities c ON c.username = btrim(r.stand_)
WHERE NULLIF(btrim(r.stand_), '') IS NOT NULL
  AND NULLIF(btrim(r.name_), '') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM rewards w
                  WHERE w.community_id = c.id
                    AND w.name = NULLIF(btrim(r.name_), ''))
ON CONFLICT DO NOTHING;

COMMIT;
