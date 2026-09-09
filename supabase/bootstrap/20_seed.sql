-- seed.sql — prod pre-seed. Runs from the one-shot `bootstrap` service AFTER
-- GoTrue finishes its own migrations (so auth.users / auth.identities exist).
-- Adapted from seed.txt: same stand UUIDs, same auth UUIDs, same credentials.
-- Idempotent (safe to re-run: bare ON CONFLICT DO NOTHING everywhere, no
-- DELETEs — never wipes prod data). Reward rows use FIXED ids so re-runs
-- conflict instead of duplicating.
--
-- Credenciales (pasar a cada comunidad por canal seguro):
--   cypheranviil@feria.local | Cypher2024*
--   meh@feria.local          | Meh2024*
--   ieee@feria.local         | Ieee2024*
--   aws.umsa@feria.local     | Aws2024*
--   guild@feria.local        | Guild2024*
--   codemiaw@feria.local     | Codecats2024*
--   pancho@feria.local       | Cpc2024*
--   casdasd@feria.local      | Ctrldev2024*
--   microbot@feria.local     | Microbot2024*
--   trateur010@feria.local   | Ciasi2024*

BEGIN;

-- 1. Usuarios de GoTrue (bcrypt via pgcrypto; mismos ids que seed.txt) ------
-- GoTrue >= 2.17x escanea confirmation_token & co. en string no-nulo: las
-- filas insertadas a mano DEBEN llevar '' (no NULL) o /token responde 500.
INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  is_super_admin,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
('ed612341-b062-4de3-bb11-447101783510', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cypheranviil@feria.local', crypt('Cypher2024*', gen_salt('bf')), NOW(), '', '', '', '', false, '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW()),
('ed612342-b062-4de3-bb11-447101783510', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'meh@feria.local', crypt('Meh2024*', gen_salt('bf')), NOW(), '', '', '', '', false, '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW()),
('ed612343-b062-4de3-bb11-447101783510', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ieee@feria.local', crypt('Ieee2024*', gen_salt('bf')), NOW(), '', '', '', '', false, '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW()),
('ed612344-b062-4de3-bb11-447101783510', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'aws.umsa@feria.local', crypt('Aws2024*', gen_salt('bf')), NOW(), '', '', '', '', false, '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW()),
('ed612345-b062-4de3-bb11-447101783510', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'guild@feria.local', crypt('Guild2024*', gen_salt('bf')), NOW(), '', '', '', '', false, '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW()),
('ed612346-b062-4de3-bb11-447101783510', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'codemiaw@feria.local', crypt('Codecats2024*', gen_salt('bf')), NOW(), '', '', '', '', false, '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW()),
('ed612347-b062-4de3-bb11-447101783510', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pancho@feria.local', crypt('Cpc2024*', gen_salt('bf')), NOW(), '', '', '', '', false, '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW()),
('ed612348-b062-4de3-bb11-447101783510', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'casdasd@feria.local', crypt('Ctrldev2024*', gen_salt('bf')), NOW(), '', '', '', '', false, '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW()),
('ed612349-b062-4de3-bb11-447101783510', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'microbot@feria.local', crypt('Microbot2024*', gen_salt('bf')), NOW(), '', '', '', '', false, '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW()),
('ed61234a-b062-4de3-bb11-447101783510', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'trateur010@feria.local', crypt('Ciasi2024*', gen_salt('bf')), NOW(), '', '', '', '', false, '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Identidades email para que el login por correo funcione --------------------
INSERT INTO auth.identities (provider_id, id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at) VALUES
('ed612341-b062-4de3-bb11-447101783510', 'ed612341-b062-4de3-bb11-447101783510', 'ed612341-b062-4de3-bb11-447101783510', format('{"sub":"%s","email":"%s"}', 'ed612341-b062-4de3-bb11-447101783510', 'cypheranviil@feria.local')::jsonb, 'email', NOW(), NOW(), NOW()),
('ed612342-b062-4de3-bb11-447101783510', 'ed612342-b062-4de3-bb11-447101783510', 'ed612342-b062-4de3-bb11-447101783510', format('{"sub":"%s","email":"%s"}', 'ed612342-b062-4de3-bb11-447101783510', 'meh@feria.local')::jsonb, 'email', NOW(), NOW(), NOW()),
('ed612343-b062-4de3-bb11-447101783510', 'ed612343-b062-4de3-bb11-447101783510', 'ed612343-b062-4de3-bb11-447101783510', format('{"sub":"%s","email":"%s"}', 'ed612343-b062-4de3-bb11-447101783510', 'ieee@feria.local')::jsonb, 'email', NOW(), NOW(), NOW()),
('ed612344-b062-4de3-bb11-447101783510', 'ed612344-b062-4de3-bb11-447101783510', 'ed612344-b062-4de3-bb11-447101783510', format('{"sub":"%s","email":"%s"}', 'ed612344-b062-4de3-bb11-447101783510', 'aws.umsa@feria.local')::jsonb, 'email', NOW(), NOW(), NOW()),
('ed612345-b062-4de3-bb11-447101783510', 'ed612345-b062-4de3-bb11-447101783510', 'ed612345-b062-4de3-bb11-447101783510', format('{"sub":"%s","email":"%s"}', 'ed612345-b062-4de3-bb11-447101783510', 'guild@feria.local')::jsonb, 'email', NOW(), NOW(), NOW()),
('ed612346-b062-4de3-bb11-447101783510', 'ed612346-b062-4de3-bb11-447101783510', 'ed612346-b062-4de3-bb11-447101783510', format('{"sub":"%s","email":"%s"}', 'ed612346-b062-4de3-bb11-447101783510', 'codemiaw@feria.local')::jsonb, 'email', NOW(), NOW(), NOW()),
('ed612347-b062-4de3-bb11-447101783510', 'ed612347-b062-4de3-bb11-447101783510', 'ed612347-b062-4de3-bb11-447101783510', format('{"sub":"%s","email":"%s"}', 'ed612347-b062-4de3-bb11-447101783510', 'pancho@feria.local')::jsonb, 'email', NOW(), NOW(), NOW()),
('ed612348-b062-4de3-bb11-447101783510', 'ed612348-b062-4de3-bb11-447101783510', 'ed612348-b062-4de3-bb11-447101783510', format('{"sub":"%s","email":"%s"}', 'ed612348-b062-4de3-bb11-447101783510', 'casdasd@feria.local')::jsonb, 'email', NOW(), NOW(), NOW()),
('ed612349-b062-4de3-bb11-447101783510', 'ed612349-b062-4de3-bb11-447101783510', 'ed612349-b062-4de3-bb11-447101783510', format('{"sub":"%s","email":"%s"}', 'ed612349-b062-4de3-bb11-447101783510', 'microbot@feria.local')::jsonb, 'email', NOW(), NOW(), NOW()),
('ed61234a-b062-4de3-bb11-447101783510', 'ed61234a-b062-4de3-bb11-447101783510', 'ed61234a-b062-4de3-bb11-447101783510', format('{"sub":"%s","email":"%s"}', 'ed61234a-b062-4de3-bb11-447101783510', 'trateur010@feria.local')::jsonb, 'email', NOW(), NOW(), NOW())
ON CONFLICT DO NOTHING;

-- 2. Comunidades (username = email de login; vinculados vía auth_user_id) ----
INSERT INTO communities (id, auth_user_id, username, name, emoji, stand_number, visit_points, activity_points) VALUES
('d0000001-0000-0000-0000-000000000000', 'ed612341-b062-4de3-bb11-447101783510', 'cypheranviil@feria.local', 'CypherAnvil', 'Shield', '1', 10, 25),
('d0000002-0000-0000-0000-000000000000', 'ed612342-b062-4de3-bb11-447101783510', 'meh@feria.local', 'MEH', 'Cpu', '2', 10, 25),
('d0000003-0000-0000-0000-000000000000', 'ed612343-b062-4de3-bb11-447101783510', 'ieee@feria.local', 'IEEE', 'RadioReceiver', '3', 10, 25),
('d0000004-0000-0000-0000-000000000000', 'ed612344-b062-4de3-bb11-447101783510', 'aws.umsa@feria.local', 'AWS', 'Cloud', '4', 10, 25),
('d0000005-0000-0000-0000-000000000000', 'ed612345-b062-4de3-bb11-447101783510', 'guild@feria.local', 'Guild', 'Swords', '5', 10, 25),
('d0000006-0000-0000-0000-000000000000', 'ed612346-b062-4de3-bb11-447101783510', 'codemiaw@feria.local', 'Codecats', 'Cat', '6', 10, 25),
('d0000007-0000-0000-0000-000000000000', 'ed612347-b062-4de3-bb11-447101783510', 'pancho@feria.local', 'CPC', 'Code', '7', 10, 25),
('d0000008-0000-0000-0000-000000000000', 'ed612348-b062-4de3-bb11-447101783510', 'casdasd@feria.local', 'CtrlDev', 'Terminal', '8', 10, 25),
('d0000009-0000-0000-0000-000000000000', 'ed612349-b062-4de3-bb11-447101783510', 'microbot@feria.local', 'Microsoft Umsa', 'LayoutGrid', '9', 10, 25),
('d000000a-0000-0000-0000-000000000000', 'ed61234a-b062-4de3-bb11-447101783510', 'trateur010@feria.local', 'CIASI', 'Database', '10', 10, 25)
ON CONFLICT (id) DO NOTHING;

-- 3. Premios (ids fijos para idempotencia) -----------------------------------
INSERT INTO rewards (id, community_id, name, description, cost, stock, emoji) VALUES
('f0000001-0000-0000-0000-000000000000', 'd0000002-0000-0000-0000-000000000000', 'CuboRubik Dotnet', 'Premio de MEH', 150, 1, 'Box'),
('f0000002-0000-0000-0000-000000000000', 'd0000004-0000-0000-0000-000000000000', 'Polera Community Day XL', 'Premio de la comunidad AWS Umsa', 200, 1, 'Shirt'),
('f0000003-0000-0000-0000-000000000000', 'd0000008-0000-0000-0000-000000000000', '1 mes vps', 'Servicio cloud de CtrlDev', 250, 1, 'Server'),
('f0000004-0000-0000-0000-000000000000', 'd0000009-0000-0000-0000-000000000000', 'Pelotitas Antiestres', 'Premio de Microsoft', 50, 1, 'Circle')
ON CONFLICT (id) DO NOTHING;

COMMIT;
