import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, X-Client-Info, Apikey",
};

const AUTH_SECRET = Deno.env.get("EMISSARY_AUTH_SECRET") || "dev-secret-change-me";
const ADMIN_USERS = Deno.env.get("EMISSARY_ADMIN_USERS") || "johnmetz:strontium17";
const DEMO_USERNAME = Deno.env.get("EMISSARY_DEMO_USERNAME") || "analyst";
const DEMO_PASSWORD = Deno.env.get("EMISSARY_DEMO_PASSWORD") || "demo";

function parseAdminUsers(): Record<string, string> {
  const users: Record<string, string> = {};
  for (const pair of ADMIN_USERS.split(",")) {
    const trimmed = pair.trim();
    if (!trimmed.includes(":")) continue;
    const [username, ...rest] = trimmed.split(":");
    const password = rest.join(":");
    if (username.trim() && password.trim()) {
      users[username.trim()] = password.trim();
    }
  }
  return users;
}

async function hmacSign(message: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(AUTH_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function verifyToken(token: string): Promise<string | null> {
  if (!token) return null;
  const lastDot = token.lastIndexOf(".");
  if (lastDot === -1) return null;
  const username = token.substring(0, lastDot);
  const sig = token.substring(lastDot + 1);
  const expected = await hmacSign(username);
  if (sig !== expected) return null;
  return username;
}

async function createToken(username: string): Promise<string> {
  const sig = await hmacSign(username);
  return `${username}.${sig}`;
}

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const path = url.pathname.replace(/^\/auth/, "");

    if (path === "/login" && req.method === "POST") {
      const { username, password } = await req.json();

      if (!username || !password) {
        return jsonResponse({ detail: "Username and password required" }, 400);
      }

      const adminUsers = parseAdminUsers();
      if (adminUsers[username] && adminUsers[username] === password) {
        const token = await createToken(username);
        return jsonResponse({
          access_token: token,
          token_type: "bearer",
          username,
          is_admin: true,
        });
      }

      if (username === DEMO_USERNAME && password === DEMO_PASSWORD) {
        const token = await createToken(username);
        return jsonResponse({
          access_token: token,
          token_type: "bearer",
          username,
          is_admin: false,
        });
      }

      return jsonResponse({ detail: "Invalid credentials" }, 401);
    }

    if (path === "/me" && req.method === "GET") {
      const emissaryToken = req.headers.get("X-Emissary-Token");
      if (!emissaryToken) {
        return jsonResponse(
          { detail: "Missing or invalid Authorization header" },
          401
        );
      }
      const username = await verifyToken(emissaryToken);
      if (!username) {
        return jsonResponse({ detail: "Invalid or expired token" }, 401);
      }
      const adminUsers = parseAdminUsers();
      return jsonResponse({
        username,
        is_admin: username in adminUsers,
      });
    }

    return jsonResponse({ detail: "Not found" }, 404);
  } catch (err) {
    return jsonResponse(
      { detail: err instanceof Error ? err.message : "Internal server error" },
      500
    );
  }
});
