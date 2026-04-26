// supabase/functions/generate-sessions/index.ts
//
// Edge Function: generate-sessions
//
// Called every day at 23:00 UTC (= 00:00 Africa/Lagos, UTC+1, no DST).
// The underlying SQL function is a no-op on non-service days, so running
// daily is safe and idempotent.
//
// Schedule (set via Supabase Dashboard → Edge Functions → Schedule):
//   Cron:  0 23 * * *   ← every night at 23:00 UTC
//
// The function calls public.auto_generate_weekly_sessions() which:
//   - Checks if today (Lagos time) is Sunday or Wednesday
//   - Creates sessions for all active programs on that day
//   - Is fully idempotent (uses NOT EXISTS guard)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY env vars');
    }

    // Use service role so RLS is bypassed for the INSERT
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data, error } = await supabase.rpc('auto_generate_weekly_sessions');

    if (error) {
      console.error('auto_generate_weekly_sessions RPC error:', error.message);
      return new Response(
        JSON.stringify({ ok: false, error: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const generatedCount: number = (data as Array<{ generated_count: number }>)?.[0]?.generated_count ?? 0;

    const lagosNow = new Date(new Date().toLocaleString('en-US', { timeZone: 'Africa/Lagos' }));
    const dayName = lagosNow.toLocaleDateString('en-US', { weekday: 'long', timeZone: 'Africa/Lagos' });

    console.log(
      `[generate-sessions] ${lagosNow.toISOString()} Lagos — ` +
      `${dayName} — generated ${generatedCount} session(s)`,
    );

    return new Response(
      JSON.stringify({
        ok: true,
        generated_count: generatedCount,
        day: dayName,
        timestamp_utc: new Date().toISOString(),
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );

  } catch (err) {
    console.error('Unexpected error:', err);
    return new Response(
      JSON.stringify({ ok: false, error: String(err) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
