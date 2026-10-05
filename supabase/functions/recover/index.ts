// Account recovery for a user who lost their master password and has no
// unlocked device. Zero-knowledge is preserved: the function only ever sees
// the recovery *auth* secret (a one-way subkey of the recovery key), never
// the recovery key, vault key or any plaintext.
//
// POST { action: "fetch", email, recoveryAuth }
//   -> { header }   (so the client can unwrap the vault key with its
//                    recovery key and re-wrap it under a new password)
// POST { action: "reset", email, recoveryAuth, newAuthSecret, newHeader,
//        newRecoveryAuthHash }
//   -> { ok: true } (sets the new Supabase password + header)
//
// Deploy: supabase functions deploy recover --no-verify-jwt
import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const generic = () =>
  new Response(JSON.stringify({ error: "invalid recovery" }), { status: 400 });

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response(null, { status: 405 });
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return generic();
  }
  const email = String(body.email ?? "").trim().toLowerCase();
  const recoveryAuth = String(body.recoveryAuth ?? "");
  if (!email || recoveryAuth.length < 40) return generic();

  const { data: userId } = await admin.rpc("user_id_by_email", {
    p_email: email,
  });
  if (!userId) return generic();
  const { data: row } = await admin.from("vault_headers")
    .select("header, recovery_auth_hash").eq("user_id", userId).maybeSingle();
  if (!row?.recovery_auth_hash) return generic();
  if (!timingSafeEqual(await sha256Hex(recoveryAuth), row.recovery_auth_hash)) {
    return generic();
  }

  if (body.action === "fetch") {
    return Response.json({ header: row.header });
  }
  if (body.action === "reset") {
    const newAuthSecret = String(body.newAuthSecret ?? "");
    const newHash = String(body.newRecoveryAuthHash ?? "");
    if (newAuthSecret.length < 40 || !/^[0-9a-f]{64}$/.test(newHash)) {
      return generic();
    }
    const { error: e1 } = await admin.auth.admin.updateUserById(userId, {
      password: newAuthSecret,
    });
    if (e1) return generic();
    const { error: e2 } = await admin.from("vault_headers").update({
      header: body.newHeader,
      recovery_auth_hash: newHash,
      updated_at: new Date().toISOString(),
    }).eq("user_id", userId);
    if (e2) return generic();
    // Revoke every existing session for this user.
    await admin.auth.admin.signOut(userId, "global").catch(() => {});
    return Response.json({ ok: true });
  }
  return generic();
});
