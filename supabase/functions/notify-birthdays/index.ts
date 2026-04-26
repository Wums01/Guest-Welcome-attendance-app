// supabase/functions/notify-birthdays/index.ts
//
// Sends birthday and anniversary push notifications to all staff devices.
// Called twice daily:
//   - 21:00 UTC for "eve" notifications (tomorrow's birthdays)
//   - 07:00 UTC for "morning" notifications (today's birthdays, Lagos ~8 AM)
//
// POST body (optional): { mode: 'eve' | 'morning' }
// If mode is omitted, determined automatically from current UTC hour.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

function toMMDD(date: Date): string {
  const m = String(date.getUTCMonth() + 1).padStart(2, '0')
  const d = String(date.getUTCDate()).padStart(2, '0')
  return `${m}-${d}`
}

async function getAllStaffTokens(): Promise<string[]> {
  const { data } = await supabase.from('device_tokens').select('token')
  return (data ?? []).map((r: { token: string }) => r.token)
}

async function sendPush(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
) {
  if (tokens.length === 0) return
  await supabase.functions.invoke('send-push', {
    body: { tokens, title, body, data },
  })
}

async function processNotifications(
  mode: 'eve' | 'morning',
  targetMMDD: string,
  year: number,
) {
  const typePrefix = mode === 'eve' ? 'eve' : 'morning'
  const tokens = await getAllStaffTokens()
  if (tokens.length === 0) {
    console.log('No staff tokens registered, skipping push')
    return { birthday: 0, anniversary: 0 }
  }

  const { data: members } = await supabase
    .from('members')
    .select('id, full_name, birthday_md, anniversary_md')

  let birthdayCount = 0
  let anniversaryCount = 0

  for (const m of members ?? []) {
    // Birthday
    if (m.birthday_md === targetMMDD) {
      const notifType = `birthday_${typePrefix}`
      const { error } = await supabase
        .from('birthday_notification_log')
        .insert({ member_id: m.id, notification_type: notifType, year })
        .onConflict('member_id, notification_type, year')
        .ignore()

      if (!error) {
        const title = mode === 'eve'
          ? `Birthday tomorrow: ${m.full_name}`
          : `Birthday today: ${m.full_name}`
        const body = mode === 'eve'
          ? `${m.full_name}'s birthday is tomorrow. Prepare to celebrate!`
          : `${m.full_name} is celebrating their birthday today. Reach out!`
        await sendPush(tokens, title, body, {
          type: 'birthday',
          memberId: m.id,
          route: `/members/${m.id}`,
        })
        birthdayCount++
      }
    }

    // Anniversary (wedding)
    if (m.anniversary_md && m.anniversary_md === targetMMDD) {
      const notifType = `anniversary_${typePrefix}`
      const { error } = await supabase
        .from('birthday_notification_log')
        .insert({ member_id: m.id, notification_type: notifType, year })
        .onConflict('member_id, notification_type, year')
        .ignore()

      if (!error) {
        const title = mode === 'eve'
          ? `Anniversary tomorrow: ${m.full_name}`
          : `Anniversary today: ${m.full_name}`
        const body = mode === 'eve'
          ? `${m.full_name}'s wedding anniversary is tomorrow.`
          : `${m.full_name} is celebrating their wedding anniversary today!`
        await sendPush(tokens, title, body, {
          type: 'anniversary',
          memberId: m.id,
          route: `/members/${m.id}`,
        })
        anniversaryCount++
      }
    }
  }

  return { birthday: birthdayCount, anniversary: anniversaryCount }
}

Deno.serve(async (req) => {
  try {
    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {}
    const now = new Date()
    const utcHour = now.getUTCHours()

    const mode: 'eve' | 'morning' =
      body.mode === 'eve' || body.mode === 'morning'
        ? body.mode
        : utcHour >= 18
        ? 'eve'
        : 'morning'

    const year = now.getUTCFullYear()
    let targetDate: Date

    if (mode === 'eve') {
      targetDate = new Date(Date.UTC(
        now.getUTCFullYear(),
        now.getUTCMonth(),
        now.getUTCDate() + 1,
      ))
    } else {
      targetDate = new Date(Date.UTC(
        now.getUTCFullYear(),
        now.getUTCMonth(),
        now.getUTCDate(),
      ))
    }

    const targetMMDD = toMMDD(targetDate)
    const result = await processNotifications(mode, targetMMDD, year)

    return new Response(
      JSON.stringify({ success: true, mode, targetMMDD, ...result }),
      { headers: { 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    console.error('notify-birthdays error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }
})
