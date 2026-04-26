// supabase/functions/follow-up-reminders/index.ts
//
// Sends FCM push notifications for follow-up actions due today.
// Called daily at 07:00 UTC (8 AM Lagos time).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

Deno.serve(async () => {
  try {
    const now = new Date()
    const todayISO = now.toISOString().slice(0, 10) // "YYYY-MM-DD"

    const { data: dueActions, error } = await supabase
      .from('member_follow_up_actions')
      .select('id, member_id, action_type, members(full_name)')
      .gte('scheduled_follow_up_at', `${todayISO}T00:00:00Z`)
      .lte('scheduled_follow_up_at', `${todayISO}T23:59:59Z`)
      .not('action_type', 'in', '("returned","transferred_out")')

    if (error) throw error

    if (!dueActions || dueActions.length === 0) {
      return new Response(JSON.stringify({ success: true, sent: 0 }), {
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const { data: tokenRows } = await supabase
      .from('device_tokens')
      .select('token')
    const tokens = (tokenRows ?? []).map((r: { token: string }) => r.token)

    if (tokens.length === 0) {
      return new Response(
        JSON.stringify({ success: true, sent: 0, reason: 'no_tokens' }),
        { headers: { 'Content-Type': 'application/json' } },
      )
    }

    let sent = 0
    for (const action of dueActions) {
      const memberName =
        (action.members as { full_name: string } | null)?.full_name ??
        'Unknown'
      await supabase.functions.invoke('send-push', {
        body: {
          tokens,
          title: 'Follow-up due today',
          body: `${memberName} — ${action.action_type.replace(/_/g, ' ')}`,
          data: {
            type: 'follow_up',
            memberId: action.member_id,
            route: '/home',
          },
        },
      })
      sent++
    }

    return new Response(JSON.stringify({ success: true, sent }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('follow-up-reminders error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }
})
