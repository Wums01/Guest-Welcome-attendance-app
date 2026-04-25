// supabase/functions/evaluate-achievements/index.ts
//
// Idempotently evaluates and unlocks achievements for all members.
// Safe to re-run — will not create duplicates.
// Called: nightly via Dashboard cron + manually after a session closes.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const TIER_THRESHOLDS: Record<string, number> = {
  tier_bronze: 10,
  tier_silver: 25,
  tier_gold: 50,
  tier_platinum: 100,
}

const STREAK_THRESHOLDS: Record<string, number> = {
  streak_4: 4,
  streak_8: 8,
  streak_16: 16,
}

Deno.serve(async () => {
  try {
    const { data: members, error: membersErr } = await supabase
      .from('members')
      .select('id, created_at')

    if (membersErr) throw membersErr

    let unlocked = 0

    for (const member of members ?? []) {
      // ── Total points ────────────────────────────────────────────────
      const { data: ledger } = await supabase
        .from('points_ledger')
        .select('points')
        .eq('member_id', member.id)

      const totalPoints = (ledger ?? []).reduce(
        (sum: number, r: { points: number }) => sum + r.points, 0
      )

      for (const [type, threshold] of Object.entries(TIER_THRESHOLDS)) {
        if (totalPoints >= threshold) {
          const { error } = await supabase
            .from('member_achievements')
            .insert({ member_id: member.id, achievement_type: type })
            .onConflict('member_id, achievement_type')
            .ignore()
          if (!error) unlocked++
        }
      }

      // ── Streak ──────────────────────────────────────────────────────
      const { data: streakData } = await supabase
        .rpc('get_member_streak', { p_member_id: member.id })

      const streak = (streakData as number) ?? 0

      for (const [type, threshold] of Object.entries(STREAK_THRESHOLDS)) {
        if (streak >= threshold) {
          const { error } = await supabase
            .from('member_achievements')
            .insert({ member_id: member.id, achievement_type: type })
            .onConflict('member_id, achievement_type')
            .ignore()
          if (!error) unlocked++
        }
      }

      // ── Perfect month ────────────────────────────────────────────────
      const { data: monthlyData } = await supabase
        .from('sessions')
        .select('id, date')
        .order('date')

      const sessionsByMonth: Record<string, string[]> = {}
      for (const s of monthlyData ?? []) {
        const ym = s.date.slice(0, 7) // "YYYY-MM"
        sessionsByMonth[ym] = sessionsByMonth[ym] ?? []
        sessionsByMonth[ym].push(s.id)
      }

      for (const [ym, sessionIds] of Object.entries(sessionsByMonth)) {
        const { data: attended } = await supabase
          .from('clock_ins')
          .select('session_id')
          .eq('member_id', member.id)
          .eq('status', 'present')
          .in('session_id', sessionIds)

        if ((attended ?? []).length === sessionIds.length && sessionIds.length > 0) {
          const { error } = await supabase
            .from('member_achievements')
            .insert({
              member_id: member.id,
              achievement_type: 'perfect_month',
              metadata: { year_month: ym },
            })
            .onConflict('member_id, achievement_type, (metadata->>\'year_month\')')
            .ignore()
          if (!error) unlocked++
        }
      }

      // ── Church anniversary ───────────────────────────────────────────
      const joinDate = new Date(member.created_at)
      const now = new Date()
      const yearsAttending = now.getFullYear() - joinDate.getFullYear()

      for (const years of [1, 2]) {
        if (yearsAttending >= years) {
          const type = `anniversary_${years}yr`
          const { error } = await supabase
            .from('member_achievements')
            .insert({ member_id: member.id, achievement_type: type })
            .onConflict('member_id, achievement_type')
            .ignore()
          if (!error) unlocked++
        }
      }
    }

    return new Response(
      JSON.stringify({ success: true, unlocked }),
      { headers: { 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    console.error('evaluate-achievements error:', err)
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
})
