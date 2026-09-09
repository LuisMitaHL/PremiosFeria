-- 20_seed.sql — CSV-driven prod seed. No hardcoded accounts here.
-- Operator mounts ./seed/ (see docker-compose.yml bootstrap volumes):
--   stands.csv   header: user,pw,name
--   rewards.csv  header: stand,name,description,cost,stock,emoji  (optional)
-- bootstrap.sh skips this file when /seed/stands.csv is unreadable.
--
-- Staging via \copy (client-side read of the mount) + INSERT..SELECT so
-- bcrypt hashing (crypt) and id linking happen in pure SQL. Idempotent:
-- users/identities/communities keyed on email/username, rewards guarded by
-- WHERE NOT EXISTS (same stand+name). No DELETEs — never wipes prod data.
-- Rows with blank user/pw are ignored; CHECK violations abort loudly
-- (psql runs with ON_ERROR_STOP=1).

BEGIN;

-- 0. Staging ---------------------------------------------------------------
CREATE TEMP TABLE stage_stands (
  user_ TEXT,
  pw_   TEXT,
  name_ TEXT
) ON COMMIT DROP;
\copy stage_stands FROM '/seed/stands.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE stage_rewards (
  stand_       TEXT,
  name_        TEXT,
  description_ TEXT,
  cost_        TEXT,
  stock_       TEXT,
  emoji_       TEXT
) ON COMMIT DROP;
-- rewards.csv is optional (bootstrap.sh sets HAS_REWARDS); a header-only
-- file seeds nothing.
\if :HAS_REWARDS
\copy stage_rewards FROM '/seed/rewards.csv' WITH (FORMAT csv, HEADER true)
\endif

-- 1. GoTrue users (bcrypt via pgcrypto) -------------------------------------
-- Tokens must be '' not NULL (GoTrue >= 2.17x scans them into Go strings).
INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  is_super_admin,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
SELECT gen_random_uuid(),
       '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated',
       btrim(user_), crypt(pw_, gen_salt('bf')), NOW(),
       '', '', '', '', false,
       '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW()
FROM stage_stands
WHERE NULLIF(btrim(user_), '') IS NOT NULL
  AND NULLIF(pw_, '') IS NOT NULL
ON CONFLICT DO NOTHING;

-- 2. Email identities (login by email needs these) ---------------------------
INSERT INTO auth.identities (
  provider_id, id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
)
SELECT u.id::text, u.id, u.id,
       format('{"sub":"%s","email":"%s"}', u.id, u.email)::jsonb,
       'email', NOW(), NOW(), NOW()
FROM auth.users u
JOIN (SELECT DISTINCT btrim(user_) AS email FROM stage_stands
      WHERE NULLIF(btrim(user_), '') IS NOT NULL) s ON s.email = u.email
ON CONFLICT DO NOTHING;

-- 3. Communities (username = login email, linked via auth_user_id) ------------
INSERT INTO communities (auth_user_id, username, name)
SELECT u.id, u.email, NULLIF(btrim(s.name_), '')
FROM (SELECT DISTINCT ON (btrim(user_)) btrim(user_) AS email, name_
      FROM stage_stands
      WHERE NULLIF(btrim(user_), '') IS NOT NULL
        AND NULLIF(pw_, '') IS NOT NULL) s
JOIN auth.users u ON u.email = s.email
ON CONFLICT (username) DO NOTHING;

-- 4. Rewards (stand = login email of the owning community) --------------------
\if :HAS_REWARDS
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
\endif

COMMIT;
