import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed." });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse(401, { error: "Authentication required." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("Supabase function environment is incomplete.");
    return jsonResponse(500, { error: "Crew provisioning is not configured." });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const token = authorization.slice("Bearer ".length);
  const { data: actorData, error: actorError } =
    await adminClient.auth.getUser(token);
  if (actorError || !actorData.user) {
    return jsonResponse(401, { error: "Invalid session." });
  }

  const { data: membership, error: membershipError } = await adminClient
    .from("profiles")
    .select("id")
    .eq("id", actorData.user.id)
    .eq("role", "admin")
    .eq("access_blocked", false)
    .maybeSingle();
  if (membershipError) {
    console.error("Could not verify crew provisioning permissions:", membershipError);
    return jsonResponse(500, { error: "Could not verify administrator access." });
  }
  if (!membership) {
    return jsonResponse(403, { error: "Administrator access required." });
  }

  let body: { municipalId?: unknown; fullName?: unknown; password?: unknown };
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { error: "Request body must be valid JSON." });
  }

  const municipalId = String(body.municipalId ?? "").trim().toUpperCase();
  const fullName = String(body.fullName ?? "").trim();
  const password = String(body.password ?? "");
  if (!/^[A-Z0-9-]{3,30}$/.test(municipalId)) {
    return jsonResponse(400, {
      error: "Municipal ID must contain 3-30 letters, numbers, or hyphens.",
    });
  }
  if (fullName.length < 2 || fullName.length > 100) {
    return jsonResponse(400, { error: "Enter a valid full name." });
  }
  if (password.length < 8) {
    return jsonResponse(400, { error: "Password must be at least 8 characters." });
  }

  const { data: existingProfile, error: existingProfileError } =
    await adminClient
      .from("profiles")
      .select("id")
      .eq("municipal_id", municipalId)
      .maybeSingle();
  if (existingProfileError) {
    console.error("Could not check Municipal ID availability:", existingProfileError);
    return jsonResponse(500, { error: "Could not verify Municipal ID availability." });
  }
  if (existingProfile) {
    return jsonResponse(409, { error: "This Municipal ID already has a profile." });
  }

  const email = `${municipalId.toLowerCase()}@crew.drainrank.com`;
  const { data: created, error: createError } =
    await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName, role: "crew" },
    });
  if (createError || !created.user) {
    const conflict = createError?.code === "email_exists";
    return jsonResponse(conflict ? 409 : 400, {
      error: conflict ? "This Municipal ID already has an account." : createError?.message,
    });
  }

  const { data: profile, error: profileError } = await adminClient
    .from("profiles")
    .update({
      role: "crew",
      municipal_id: municipalId,
      full_name: fullName,
      access_blocked: false,
    })
    .eq("id", created.user.id)
    .select("id")
    .maybeSingle();
  if (profileError || !profile) {
    const { error: rollbackError } =
      await adminClient.auth.admin.deleteUser(created.user.id);
    if (rollbackError) {
      console.error("Crew account rollback failed:", rollbackError);
    }
    console.error("Could not update crew profile:", profileError);
    return jsonResponse(500, { error: "Could not finish creating the crew account." });
  }

  return jsonResponse(201, {
    municipalId,
    userId: created.user.id,
    message: "Crew account created successfully.",
  });
});

function jsonResponse(status: number, body: Record<string, string>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
