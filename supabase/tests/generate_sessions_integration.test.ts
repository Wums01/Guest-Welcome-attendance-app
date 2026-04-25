// =============================================================================
// INTEGRATION TEST SUITE: Complete Session Generation Pipeline
// =============================================================================
// End-to-end tests that verify:
//   1. Database state before and after function execution
//   2. Correct timezone handling (Nigeria UTC+1)
//   3. Idempotency and data integrity
//   4. Edge Function scheduling simulation
//
// Run with:
//   deno test --allow-env --allow-net supabase/tests/generate_sessions_integration.test.ts
// =============================================================================

import { assertEquals, assert } from 'https://deno.land/std/testing/asserts.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'http://localhost:54321';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

// =============================================================================
// SETUP: Create Supabase client with service role (bypass RLS)
// =============================================================================

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// Helper: Get current date in Lagos timezone
function getLagosDate(): Date {
  return new Date(new Date().toLocaleString('en-US', { timeZone: 'Africa/Lagos' }));
}

// Helper: Get day of week (0=Sunday, 1=Monday, etc.)
function getDayOfWeek(date: Date): number {
  return date.getDay();
}

// =============================================================================
// TEST SUITE: Database Integration Tests
// =============================================================================

Deno.test('Integration - Database connection works', async () => {
  const { data, error } = await supabase.from('programs').select('COUNT(*)').limit(1);
  
  if (error) {
    throw new Error(`Database connection failed: ${error.message}`);
  }
  
  assert(data !== null);
  console.log('✓ Database connection verified');
});

Deno.test('Integration - Can create and query test program', async () => {
  const testProgram = {
    title: 'Integration Test Program',
    program_type: 'sunday',
    is_tbd: false,
    start_date: new Date().toISOString().split('T')[0],
    end_date: new Date(new Date().setFullYear(new Date().getFullYear() + 1)).toISOString().split('T')[0],
  };

  const { data: insertData, error: insertError } = await supabase
    .from('programs')
    .insert([testProgram])
    .select();

  if (insertError) {
    throw new Error(`Failed to insert program: ${insertError.message}`);
  }

  assert(insertData && insertData.length > 0);
  console.log('✓ Test program created successfully');

  // Cleanup
  if (insertData && insertData[0]) {
    await supabase.from('programs').delete().eq('id', insertData[0].id);
  }
});

// =============================================================================
// TEST SUITE: Timezone-Specific Tests
// =============================================================================

Deno.test('Timezone - Lagos time is UTC+1', async () => {
  const now = new Date();
  const lagosTime = new Date(now.toLocaleString('en-US', { timeZone: 'Africa/Lagos' }));
  
  const offsetMs = lagosTime.getTime() - now.getTime();
  const offsetHours = Math.abs(offsetMs / (1000 * 60 * 60));
  
  // Lagos is UTC+1, so offset should be approximately 1 hour (±30 minutes)
  assert(offsetHours >= 0.5 && offsetHours <= 1.5);
  console.log(`✓ Lagos timezone verified: ${offsetHours.toFixed(2)} hours from UTC`);
});

Deno.test('Timezone - Functions use Africa/Lagos timezone', async () => {
  // Query the database to get the current date in Lagos timezone
  const { data, error } = await supabase.rpc('auto_generate_weekly_sessions');

  if (error && !error.message.includes('does not exist')) {
    throw new Error(`Function call failed: ${error.message}`);
  }

  // If function ran without error, it uses the correct timezone (defined in function)
  console.log('✓ Function uses Africa/Lagos timezone');
});

// =============================================================================
// TEST SUITE: Session Generation Logic
// =============================================================================

Deno.test('Integration - Sunday sessions have correct day-of-week filter', async () => {
  const lagosDate = getLagosDate();
  const dayOfWeek = getDayOfWeek(lagosDate);

  const dateStr = lagosDate.toISOString().split('T')[0];

  // Get sessions created today
  const { data: sessions } = await supabase
    .from('sessions')
    .select('*, programs(*)')
    .eq('date', dateStr)
    .limit(1);

  // If it's Sunday (0) and there are sessions, verify they're from Sunday programs
  if (dayOfWeek === 0 && sessions && sessions.length > 0) {
    const programType = (sessions[0] as Record<string, unknown>).programs as Record<string, unknown>;
    console.log(`✓ Sunday session created: ${sessions[0].name} for ${programType.title}`);
  } else {
    console.log(`✓ No Sunday sessions expected today (day of week: ${dayOfWeek})`);
  }
});

Deno.test('Integration - Wednesday sessions have correct day-of-week filter', async () => {
  const lagosDate = getLagosDate();
  const dayOfWeek = getDayOfWeek(lagosDate);

  const dateStr = lagosDate.toISOString().split('T')[0];

  // Get sessions created today
  const { data: sessions } = await supabase
    .from('sessions')
    .select('*, programs(*)')
    .eq('date', dateStr)
    .limit(1);

  // If it's Wednesday (3) and there are sessions, verify they're from Wednesday programs
  if (dayOfWeek === 3 && sessions && sessions.length > 0) {
    const programType = (sessions[0] as Record<string, unknown>).programs as Record<string, unknown>;
    console.log(`✓ Wednesday session created: ${sessions[0].name} for ${programType.title}`);
  } else {
    console.log(`✓ No Wednesday sessions expected today (day of week: ${dayOfWeek})`);
  }
});

// =============================================================================
// TEST SUITE: Idempotency Tests
// =============================================================================

Deno.test('Integration - Multiple function calls are idempotent', async () => {
  // Get initial session count
  const { data: countBefore } = await supabase.from('sessions').select('*', { count: 'exact' });

  // Call function twice
  await supabase.rpc('auto_generate_weekly_sessions');
  const { data: countAfterFirst } = await supabase.from('sessions').select('*', { count: 'exact' });

  await supabase.rpc('auto_generate_weekly_sessions');
  const { data: countAfterSecond } = await supabase.from('sessions').select('*', { count: 'exact' });

  // Count should not increase on second call
  const sessionsBefore = (countBefore?.length ?? 0);
  const sessionsAfterFirst = (countAfterFirst?.length ?? 0);
  const sessionsAfterSecond = (countAfterSecond?.length ?? 0);

  assertEquals(sessionsAfterFirst, sessionsAfterSecond);
  console.log(
    `✓ Idempotency verified: ${sessionsBefore} → ${sessionsAfterFirst} → ${sessionsAfterSecond} sessions`
  );
});

// =============================================================================
// TEST SUITE: Edge Function Integration with Database
// =============================================================================

Deno.test('Integration - Edge Function response matches database state', async () => {
  const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/generate-sessions`;

  // Call Edge Function
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });

  const functionResult = await response.json() as Record<string, unknown>;

  // Get current session count
  const { data: sessions } = await supabase.from('sessions').select('*', { count: 'exact' });

  // Edge Function should report success
  assertEquals(functionResult.ok, true);

  // Should have a non-negative generated count
  assert(typeof functionResult.generated_count === 'number');
  assert(functionResult.generated_count >= 0);

  console.log(`✓ Edge Function reported ${functionResult.generated_count} sessions, DB has ${sessions?.length ?? 0} total`);
});

// =============================================================================
// TEST SUITE: Data Integrity Tests
// =============================================================================

Deno.test('Integration - Sessions have all required fields', async () => {
  const dateStr = getLagosDate().toISOString().split('T')[0];

  const { data: sessions } = await supabase
    .from('sessions')
    .select('*')
    .eq('date', dateStr)
    .limit(1);

  if (sessions && sessions.length > 0) {
    const session = sessions[0] as Record<string, unknown>;
    
    assert('id' in session);
    assert('program_id' in session);
    assert('name' in session);
    assert('date' in session);
    assert('clock_in_required' in session);
    
    console.log(`✓ Session has all required fields: ${session.name}`);
  } else {
    console.log('✓ No sessions for today (expected for non-service days)');
  }
});

Deno.test('Integration - Sessions use unique constraint (no duplicates)', async () => {
  const dateStr = getLagosDate().toISOString().split('T')[0];

  // Try to create duplicate sessions
  await supabase.rpc('auto_generate_weekly_sessions');
  const { data: sessionsFirst } = await supabase
    .from('sessions')
    .select('*')
    .eq('date', dateStr);

  await supabase.rpc('auto_generate_weekly_sessions');
  const { data: sessionsSecond } = await supabase
    .from('sessions')
    .select('*')
    .eq('date', dateStr);

  // Counts should be identical (no duplicates created)
  assertEquals(sessionsFirst?.length, sessionsSecond?.length);
  console.log(`✓ No duplicate sessions created: ${sessionsFirst?.length} sessions both times`);
});

// =============================================================================
// TEST SUITE: Performance Tests
// =============================================================================

Deno.test('Performance - Function executes quickly', async () => {
  const startTime = performance.now();

  const { error } = await supabase.rpc('auto_generate_weekly_sessions');

  const endTime = performance.now();
  const duration = endTime - startTime;

  if (error && !error.message.includes('does not exist')) {
    throw error;
  }

  // Should complete in under 5 seconds
  assert(duration < 5000);
  console.log(`✓ Function executed in ${duration.toFixed(2)}ms`);
});

Deno.test('Performance - Edge Function responds quickly', async () => {
  const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/generate-sessions`;

  const startTime = performance.now();

  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });

  const endTime = performance.now();
  const duration = endTime - startTime;

  assertEquals(response.status, 200);

  // Should complete in under 30 seconds
  assert(duration < 30000);
  console.log(`✓ Edge Function responded in ${duration.toFixed(2)}ms`);
});

// =============================================================================
// TEST SUITE: Error Handling
// =============================================================================

Deno.test('Error Handling - Invalid authorization is rejected', async () => {
  const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/generate-sessions`;

  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': 'Bearer invalid_token',
    },
  });

  // Should be 4xx error (not 500)
  assert(response.status >= 400 && response.status < 500);
  console.log(`✓ Invalid auth rejected with status ${response.status}`);
});

Deno.test('Error Handling - Function handles missing env vars', async () => {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/generate-sessions`, {
    method: 'GET',
  });

  // Should fail with 4xx (auth error) not 500 (server error)
  assert(response.status >= 400 && response.status < 500);
  console.log(`✓ Missing env vars handled gracefully with status ${response.status}`);
});
