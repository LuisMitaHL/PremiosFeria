// server.mjs — prod auth service (zero dependencies).
// Replaces GoTrue with a supabase-js compatible subset speaking USERNAME auth:
//   POST /token?grant_type=password      {email|username, password} -> session
//   POST /token?grant_type=refresh_token {refresh_token}            -> session (rotated)
//   POST /signup                         (empty body)                -> anon session
//   POST /logout                                                     -> 204
//   GET  /user                           (Bearer)                    -> user object
//   GET  /health                                                      -> version
//
// Passwords are verified inside Postgres (stand_login RPC does the bcrypt
// compare via pgcrypto); plaintext passwords never touch disk or logs here.
// JWTs are HS256 with JWT_SECRET, role is always `authenticated` (RLS keys
// off auth.uid(), never the role) — same trust model as the GoTrue setup.
//
// Env: PGRST_URL, ANON_KEY, JWT_SECRET (>=32 chars, fatal otherwise),
//   ACCESS_TTL=43200, REFRESH_TTL=7776000, RATE_LIMIT_MAX=20,
//   RATE_LIMIT_WINDOW=300, PORT=9999.
import http from "node:http";
import crypto from "node:crypto";

const PGRST_URL = process.env.PGRST_URL || "http://rest:3000";
const ANON_KEY = process.env.ANON_KEY || "";
const JWT_SECRET = process.env.JWT_SECRET || "";
const PORT = Number(process.env.PORT || 9999);
const ACCESS_TTL = Number(process.env.ACCESS_TTL || 43200); // 12h
const REFRESH_TTL = Number(process.env.REFRESH_TTL || 7776000); // 90d
const RATE_MAX = Number(process.env.RATE_LIMIT_MAX || 20);
const RATE_WINDOW = Number(process.env.RATE_LIMIT_WINDOW || 300); // seconds

if (Buffer.byteLength(JWT_SECRET, "utf8") < 32) {
  console.error("fatal: JWT_SECRET must be >= 32 chars");
  process.exit(1);
}

const b64 = (b) => Buffer.from(b).toString("base64url");
const sign = (d) => crypto.createHmac("sha256", JWT_SECRET).update(d).digest("base64url");

function mint({ sub, role = "authenticated", ttl, extra = {} }) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payload = b64(JSON.stringify({ iss: "premiosferia", sub, role, iat: now, exp: now + ttl, ...extra }));
  return { token: `${header}.${payload}.${sign(header + "." + payload)}`, iat: now, exp: now + ttl };
}

function verify(token) {
  if (typeof token !== "string") return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  let sig;
  try {
    sig = sign(parts[0] + "." + parts[1]);
  } catch {
    return null;
  }
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(parts[2]))) return null;
  try {
    const claims = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    if (typeof claims.exp !== "number" || claims.exp * 1000 < Date.now()) return null;
    return claims;
  } catch {
    return null;
  }
}

// --- brute-force guard: sliding window per ip+username (in-memory) ---------
const attempts = new Map(); // key -> number[]
function rateLimited(key) {
  const now = Date.now();
  const cutoff = now - RATE_WINDOW * 1000;
  const hits = (attempts.get(key) || []).filter((t) => t > cutoff);
  hits.push(now);
  attempts.set(key, hits);
  if (attempts.size > 10000) attempts.clear();
  return hits.length > RATE_MAX;
}

// --- PostgREST helpers ------------------------------------------------------
async function rpcStandLogin(username, password) {
  const res = await fetch(`${PGRST_URL}/rpc/stand_login`, {
    method: "POST",
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_username: username, p_password: password }),
  });
  if (!res.ok) throw new Error(`stand_login rpc: ${res.status}`);
  const rows = await res.json();
  return Array.isArray(rows) && rows.length === 1 ? rows[0] : null;
}

async function communityById(id) {
  const res = await fetch(`${PGRST_URL}/communities?id=eq.${encodeURIComponent(id)}&select=id,username,name`, {
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` },
  });
  if (!res.ok) return null;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length === 1 ? rows[0] : null;
}

// --- sessions ---------------------------------------------------------------
function adminSession(community) {
  const access = mint({ sub: community.id, ttl: ACCESS_TTL, extra: { user_metadata: { community_id: community.id, name: community.name, username: community.username } } });
  const refresh = mint({ sub: community.id, ttl: REFRESH_TTL, extra: { type: "refresh", user_metadata: { community_id: community.id } } });
  return toSession(community, access, refresh);
}

function toSession(community, access, refresh) {
  const nowIso = new Date(access.iat * 1000).toISOString();
  return {
    access_token: access.token,
    token_type: "bearer",
    expires_in: ACCESS_TTL,
    expires_at: access.exp,
    refresh_token: refresh.token,
    user: {
      id: community.id,
      aud: "authenticated",
      role: "authenticated",
      email: community.username,
      email_confirmed_at: nowIso,
      app_metadata: { provider: "username", providers: ["username"] },
      user_metadata: { community_id: community.id, name: community.name, username: community.username },
      created_at: nowIso,
      updated_at: nowIso,
    },
  };
}

function anonSession() {
  const uid = crypto.randomUUID();
  const access = mint({ sub: uid, ttl: ACCESS_TTL, extra: { is_anonymous: true, app_metadata: { provider: "anonymous", providers: ["anonymous"] }, user_metadata: {} } });
  const refresh = mint({ sub: uid, ttl: REFRESH_TTL, extra: { type: "refresh", is_anonymous: true } });
  const nowIso = new Date(access.iat * 1000).toISOString();
  return {
    access_token: access.token,
    token_type: "bearer",
    expires_in: ACCESS_TTL,
    expires_at: access.exp,
    refresh_token: refresh.token,
    user: {
      id: uid,
      aud: "authenticated",
      role: "authenticated",
      is_anonymous: true,
      app_metadata: { provider: "anonymous", providers: ["anonymous"] },
      user_metadata: {},
      created_at: nowIso,
      updated_at: nowIso,
    },
  };
}

// --- http -------------------------------------------------------------------
function send(res, status, obj) {
  const body = obj === undefined ? "" : JSON.stringify(obj);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Expose-Headers": "*",
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => resolve(data));
  });
}

const invalidCredentials = (res) =>
  send(res, 400, { error: "invalid_credentials", error_description: "Credenciales incorrectas.", msg: "Credenciales incorrectas.", code: 400 });

async function handleToken(req, res, query, ip) {
  const grant = new URLSearchParams(query).get("grant_type");
  const raw = await readBody(req);
  let body = {};
  try {
    body = JSON.parse(raw || "{}");
  } catch {
    body = Object.fromEntries(new URLSearchParams(raw));
  }

  if (grant === "refresh_token") {
    const claims = verify(body.refresh_token);
    if (!claims?.sub) return send(res, 400, { error: "invalid_grant", error_description: "Invalid refresh token" });
    if (claims.is_anonymous) return send(res, 200, anonSessionFor(claims.sub));
    const community = await communityById(claims.sub).catch(() => null);
    if (!community) return send(res, 400, { error: "invalid_grant", error_description: "Session no longer valid" });
    return send(res, 200, adminSession(community));
  }

  if (grant !== "password") {
    return send(res, 400, { error: "unsupported_grant_type", error_description: "Unsupported grant_type" });
  }

  const username = String(body.username ?? body.email ?? "").trim();
  const password = String(body.password ?? "");
  if (!username || !password) return invalidCredentials(res);
  if (rateLimited(`${ip}|${username.toLowerCase()}`)) {
    return send(res, 429, { error: "rate_limited", error_description: "Demasiados intentos. Espera unos minutos.", code: 429 });
  }
  let community = null;
  try {
    community = await rpcStandLogin(username, password);
  } catch {
    return send(res, 500, { error: "internal_error", error_description: "Auth backend unavailable", code: 500 });
  }
  if (!community) return invalidCredentials(res);
  return send(res, 200, adminSession(community));
}

// Refresh for anonymous sessions keeps the same sub (no DB lookup needed).
function anonSessionFor(uid) {
  const access = mint({ sub: uid, ttl: ACCESS_TTL, extra: { is_anonymous: true, app_metadata: { provider: "anonymous", providers: ["anonymous"] }, user_metadata: {} } });
  const refresh = mint({ sub: uid, ttl: REFRESH_TTL, extra: { type: "refresh", is_anonymous: true } });
  const nowIso = new Date(access.iat * 1000).toISOString();
  const user = { id: uid, aud: "authenticated", role: "authenticated", is_anonymous: true, app_metadata: { provider: "anonymous", providers: ["anonymous"] }, user_metadata: {}, created_at: nowIso, updated_at: nowIso };
  return { access_token: access.token, token_type: "bearer", expires_in: ACCESS_TTL, expires_at: access.exp, refresh_token: refresh.token, user };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const ip = (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || req.socket.remoteAddress || "unknown";
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": req.headers["access-control-request-headers"] || "*",
      "Access-Control-Max-Age": "86400",
    });
    return res.end();
  }
  try {
    if (req.method === "POST" && path === "/token") return await handleToken(req, res, url.search, ip);
    if (req.method === "POST" && path === "/signup") {
      await readBody(req);
      return send(res, 200, anonSession());
    }
    if (req.method === "POST" && path === "/logout") return send(res, 204);
    if (req.method === "GET" && path === "/user") {
      const claims = verify((req.headers.authorization || "").replace(/^Bearer\s+/i, ""));
      if (!claims?.sub) return send(res, 401, { error: "invalid_token", msg: "Invalid token" });
      if (claims.is_anonymous) {
        const nowIso = new Date().toISOString();
        return send(res, 200, { id: claims.sub, aud: "authenticated", role: "authenticated", is_anonymous: true, app_metadata: { provider: "anonymous", providers: ["anonymous"] }, user_metadata: {}, created_at: nowIso, updated_at: nowIso });
      }
      const community = await communityById(claims.sub).catch(() => null);
      if (!community) return send(res, 401, { error: "invalid_token", msg: "Session no longer valid" });
      return send(res, 200, adminSession(community).user);
    }
    if (req.method === "GET" && path === "/health") {
      return send(res, 200, { version: "1.0.0", name: "premiosferia-auth", description: "Username auth for PremiosFeria" });
    }
    return send(res, 404, { error: "not_found", msg: `No route: ${req.method} ${path}` });
  } catch {
    return send(res, 500, { error: "internal_error", msg: "Unexpected error" });
  }
});

server.listen(PORT, () => console.log(`premiosferia-auth listening on :${PORT}`));
