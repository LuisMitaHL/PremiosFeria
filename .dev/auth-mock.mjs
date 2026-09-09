// auth-mock.mjs — minimal GoTrue (Supabase Auth) stand-in for the local dev stack.
//
// Zero-dependency Node HTTP service. Verifies a community's plaintext
// username/password (seeded by dev.sh into `communities`) against PostgREST,
// then issues an HS256 JWT carrying {sub: community_id, role: community_admin}
// so PostgREST + the RLS policies behave like production.
//
// Endpoints (supabase-js compatible subset):
//   POST /token?grant_type=password      {email, password}  -> session JSON
//   POST /token?grant_type=refresh_token {refresh_token}    -> session JSON
//   POST /logout                                             -> 204
//   GET  /user                           (Bearer token)     -> user JSON
import http from "node:http";
import crypto from "node:crypto";

const PGRST_URL = process.env.PGRST_URL || "http://rest:3000";
const ANON_KEY = process.env.ANON_KEY || "";
const JWT_SECRET = process.env.JWT_SECRET || "";
const PORT = Number(process.env.PORT || 3001);

const b64 = (b) => Buffer.from(b).toString("base64url");
const sign = (d) => crypto.createHmac("sha256", JWT_SECRET).update(d).digest("base64url");

function issueSession(community) {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + 31536000; // 1 year — dev only
  const header = b64(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payload = b64(
    JSON.stringify({
      iss: "supabase",
      sub: community.id,
      role: "community_admin",
      iat: now,
      exp,
      app_metadata: { provider: "email", providers: ["email"] },
      user_metadata: { community_id: community.id, name: community.name, username: community.username },
    })
  );
  const access_token = `${header}.${payload}.${sign(header + "." + payload)}`;
  return {
    access_token,
    token_type: "bearer",
    expires_in: 31536000,
    expires_at: exp,
    refresh_token: access_token, // mock: refresh token doubles as the JWT
    user: {
      id: community.id,
      aud: "authenticated",
      role: "community_admin",
      email: community.username,
      email_confirmed_at: new Date(now * 1000).toISOString(),
      app_metadata: { provider: "email", providers: ["email"] },
      user_metadata: { community_id: community.id, name: community.name, username: community.username },
      created_at: new Date(now * 1000).toISOString(),
      updated_at: new Date(now * 1000).toISOString(),
    },
  };
}

function verifyJwt(token) {
  if (typeof token !== "string") return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  if (sign(parts[0] + "." + parts[1]) !== parts[2]) return null;
  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

async function lookupCommunity(username) {
  const url = `${PGRST_URL}/communities?username=eq.${encodeURIComponent(username)}&select=id,username,password,name,emoji,stand_number`;
  const res = await fetch(url, {
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` },
  });
  if (!res.ok) return null;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length === 1 ? rows[0] : null;
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => resolve(data));
  });
}

async function handleToken(req, res, query) {
  let grant = new URLSearchParams(query).get("grant_type");
  const raw = await readBody(req);
  let body = {};
  try {
    body = JSON.parse(raw || "{}");
  } catch {
    // GoTrue also accepts form-encoded credentials
    body = Object.fromEntries(new URLSearchParams(raw));
  }

  if (grant === "refresh_token") {
    const claims = verifyJwt(body.refresh_token);
    if (!claims || !claims.sub) {
      return send(res, 400, { error: "invalid_grant", error_description: "Invalid refresh token" });
    }
    const community = await lookupCommunity(claims.user_metadata?.username || "");
    if (!community) {
      return send(res, 400, { error: "invalid_grant", error_description: "Session no longer valid" });
    }
    return send(res, 200, issueSession(community));
  }

  if (grant !== "password") {
    return send(res, 400, { error: "unsupported_grant_type", error_description: "Unsupported grant_type" });
  }

  const email = String(body.email || "");
  const password = String(body.password || "");
  const community = await lookupCommunity(email);
  if (!community || community.password !== password) {
    return send(res, 400, {
      error: "invalid_credentials",
      error_description: "Email address or password is incorrect.",
      msg: "Email address or password is incorrect.",
      code: 400,
    });
  }
  return send(res, 200, issueSession(community));
}

// supabase-js signInAnonymously() POSTs /signup with no credentials.
// Issues an ephemeral user: sub = fresh uuid, role = authenticated.
function issueAnonymousSession() {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + 3600;
  const uid = crypto.randomUUID();
  const header = b64(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payload = b64(
    JSON.stringify({
      iss: "supabase",
      sub: uid,
      role: "authenticated",
      iat: now,
      exp,
      is_anonymous: true,
      app_metadata: { provider: "anonymous", providers: ["anonymous"] },
      user_metadata: {},
    })
  );
  const access_token = `${header}.${payload}.${sign(header + "." + payload)}`;
  const user = {
    id: uid,
    aud: "authenticated",
    role: "authenticated",
    is_anonymous: true,
    app_metadata: { provider: "anonymous", providers: ["anonymous"] },
    user_metadata: {},
    created_at: new Date(now * 1000).toISOString(),
  };
  return { ...user, access_token, token_type: "bearer", expires_in: 3600, expires_at: exp, refresh_token: access_token };
}

async function handleAnonymousSignup(req, res) {
  await readBody(req); // drain
  return send(res, 200, issueAnonymousSession());
}

function send(res, status, obj) {
  const body = obj === undefined ? "" : JSON.stringify(obj);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Expose-Headers": "*",
  });
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const path = url.pathname.replace(/\/+$/, "") || "/";
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
    if (req.method === "POST" && path === "/token") return await handleToken(req, res, url.search);
    if (req.method === "POST" && path === "/signup") return await handleAnonymousSignup(req, res);
    if (req.method === "POST" && path === "/logout") return send(res, 204);
    if (req.method === "GET" && path === "/user") {
      const auth = req.headers.authorization || "";
      const claims = verifyJwt(auth.replace(/^Bearer\s+/i, ""));
      if (!claims?.sub || claims.role !== "community_admin") {
        return send(res, 401, { error: "invalid_token", msg: "Invalid token" });
      }
      const community = await lookupCommunity(claims.user_metadata?.username || "");
      if (!community) return send(res, 401, { error: "invalid_token", msg: "Session no longer valid" });
      return send(res, 200, issueSession(community).user);
    }
    return send(res, 404, { error: "not_found", msg: `No route: ${req.method} ${path}` });
  } catch (err) {
    return send(res, 500, { error: "internal_error", msg: String(err && err.message) });
  }
});

server.listen(PORT, () => console.log(`auth-mock listening on :${PORT}`));
