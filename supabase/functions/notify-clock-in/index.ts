// supabase/functions/notify-clock-in/index.ts
//
// Broadcasts a push notification to ALL staff devices when a member checks in.
//
// POST body: { memberName: string, sessionId: string }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

async function getFcmAccessToken(): Promise<string> {
  const sa = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')!)
  const now = Math.floor(Date.now() / 1000)
  const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = btoa(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))
  const pemBody = (sa.private_key as string)
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')
  const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const privateKey = await crypto.subtle.importKey(
    'pkcs8', keyData.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  )
  const signingInput = `${header}.${payload}`
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, new TextEncoder().encode(signingInput))
  const sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  const jwt = `${signingInput}.${sig}`
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })
  const tokenData = await tokenRes.json()
  return tokenData.access_token as string
}

Deno.serve(async (req) => {
  try {
    const { memberName, sessionId } = await req.json() as {
      memberName: string
      sessionId: string
    }

    if (!memberName || !sessionId) {
      return new Response(
        JSON.stringify({ error: 'memberName and sessionId are required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      )
    }

    // Fetch session name
    const { data: session } = await supabase
      .from('sessions')
      .select('name')
      .eq('id', sessionId)
      .maybeSingle()
    const sessionName = session?.name ?? 'a session'

    // Get all registered device tokens
    const { data: rows } = await supabase.from('device_tokens').select('token')
    const tokens = (rows ?? []).map((r: { token: string }) => r.token)

    if (tokens.length === 0) {
      console.log('No device tokens — skipping push')
      return new Response(JSON.stringify({ sent: 0, stale: 0 }), {
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const projectId = Deno.env.get('FCM_PROJECT_ID')!
    const accessToken = await getFcmAccessToken()
    const staleTokens: string[] = []
    let sent = 0

    for (const token of tokens) {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token,
              notification: {
                title: 'Member Checked In',
                body: `${memberName} just checked in for ${sessionName}`,
              },
              data: { type: 'clock_in', route: `/sessions/${sessionId}` },
              android: { priority: 'high', notification: { sound: 'default' } },
              apns: {
                headers: { 'apns-priority': '10' },
                payload: { aps: { sound: 'default' } },
              },
            },
          }),
        },
      )

      if (res.ok) {
        sent++
      } else {
        const err = await res.json().catch(() => ({}))
        const status = err?.error?.status
        const message = (err?.error?.message ?? '') as string
        if (
          status === 'UNREGISTERED' ||
          (status === 'INVALID_ARGUMENT' && message.toLowerCase().includes('not a valid fcm'))
        ) {
          staleTokens.push(token)
        } else {
          console.error('FCM send error for token:', status, message)
        }
      }
    }

    if (staleTokens.length > 0) {
      await supabase.from('device_tokens').delete().in('token', staleTokens)
      console.log(`Removed ${staleTokens.length} stale tokens`)
    }

    console.log(`notify-clock-in: sent=${sent} stale=${staleTokens.length}`)
    return new Response(JSON.stringify({ sent, stale: staleTokens.length }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('notify-clock-in error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }
})
