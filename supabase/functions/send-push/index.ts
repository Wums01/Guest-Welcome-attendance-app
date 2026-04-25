// supabase/functions/send-push/index.ts
//
// Shared helper: sends FCM push notifications to a list of device tokens.
// Automatically removes stale tokens from the database.
//
// POST body: { tokens: string[], title: string, body: string, data?: Record<string, string> }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

// Returns a short-lived OAuth2 access token for FCM HTTP v1 API
async function getFcmAccessToken(): Promise<string> {
  const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')!
  const sa = JSON.parse(serviceAccountJson)

  const now = Math.floor(Date.now() / 1000)
  const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = btoa(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))

  // Sign the JWT with the private key using Web Crypto
  const pemKey = sa.private_key as string
  const pemBody = pemKey
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')
  const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const privateKey = await crypto.subtle.importKey(
    'pkcs8', keyData.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign']
  )
  const signingInput = `${header}.${payload}`
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', privateKey,
    new TextEncoder().encode(signingInput)
  )
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
    const { tokens, title, body, data } = await req.json() as {
      tokens: string[]
      title: string
      body: string
      data?: Record<string, string>
    }

    if (!tokens || tokens.length === 0) {
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
              notification: { title, body },
              data: data ?? {},
            },
          }),
        }
      )

      if (res.ok) {
        sent++
      } else {
        const err = await res.json()
        const status = err?.error?.status
        if (status === 'UNREGISTERED' || status === 'INVALID_ARGUMENT') {
          staleTokens.push(token)
        } else {
          console.error('FCM send error:', err)
        }
      }
    }

    // Remove stale tokens
    if (staleTokens.length > 0) {
      await supabase.from('device_tokens').delete().in('token', staleTokens)
      console.log(`Removed ${staleTokens.length} stale FCM tokens`)
    }

    return new Response(JSON.stringify({ sent, stale: staleTokens.length }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('send-push error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }
})
