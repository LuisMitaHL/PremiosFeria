-- 15_extensions.sql — pgcrypto provides gen_random_uuid() (schema defaults)
-- and hmac() (QR signing in 50_rpc.sql). Plain postgres image installs it
-- into `public`, which is exactly what the SECURITY DEFINER functions see
-- (they run with SET search_path = public).
CREATE EXTENSION IF NOT EXISTS pgcrypto;
