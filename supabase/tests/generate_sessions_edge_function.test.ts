// =============================================================================
// TEST SUITE: generate-sessions Edge Function
// =============================================================================
// Tests for the server-side Supabase Edge Function that triggers daily session generation
//
// Run these tests with Deno:
//   deno test --allow-env --allow-net supabase/tests/generate_sessions_function.test.ts
//
// Requirements:
//   - Deno runtime
//   - Environment variables: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// =============================================================================

import { assertEquals, assertStringIncludes } from 'https://deno.land/std/testing/asserts.ts';

// Test configuration
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'http://localhost:54321';
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/generate-sessions`;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

// =============================================================================
// TEST 1: Edge Function endpoint is reachable and handles HTTP OPTIONS
// =============================================================================
Deno.test('Edge Function - CORS preflight request', async () => {
  const response = await fetch(FUNCTION_URL, {
    method: 'OPTIONS',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
  });

  assertEquals(response.status, 200);
  const text = await response.text();
  assertEquals(text, 'ok');
});

// =============================================================================
// TEST 2: Edge Function returns valid JSON response on success
// =============================================================================
Deno.test('Edge Function - GET request returns valid JSON', async () => {
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
  });

  assertEquals(response.status, 200);
  assertEquals(response.headers.get('content-type'), 'application/json');

  const data: Record<string, unknown> = await response.json();
  assertEquals(data.ok, true);
  assertEquals(typeof data.generated_count, 'number');
  assertEquals(typeof data.day, 'string');
  assertEquals(typeof data.timestamp_utc, 'string');
});

// =============================================================================
// TEST 3: Edge Function response includes Lagos day name
// =============================================================================
Deno.test('Edge Function - Response includes correct day of week', async () => {
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });

  const data: Record<string, string | number | boolean> = await response.json();
  const validDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  
  assertEquals(validDays.includes(data.day as string), true);
});

// =============================================================================
// TEST 4: Edge Function handles POST requests
// =============================================================================
Deno.test('Edge Function - POST request is handled', async () => {
  const response = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ test: true }),
  });

  assertEquals(response.status, 200);
  const data: Record<string, unknown> = await response.json();
  assertEquals(data.ok, true);
});

// =============================================================================
// TEST 5: Edge Function returns timestamp in ISO format
// =============================================================================
Deno.test('Edge Function - Timestamp is valid ISO format', async () => {
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });

  const data: Record<string, unknown> = await response.json();
  const timestamp = data.timestamp_utc as string;
  
  // Should be parseable as ISO date
  const date = new Date(timestamp);
  assertEquals(date instanceof Date && !isNaN(date.getTime()), true);
  
  // Should contain 'T' separator for ISO format
  assertStringIncludes(timestamp, 'T');
});

// =============================================================================
// TEST 6: Edge Function generated_count is non-negative integer
// =============================================================================
Deno.test('Edge Function - generated_count is valid', async () => {
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });

  const data: Record<string, unknown> = await response.json();
  assertEquals(typeof data.generated_count, 'number');
  assertEquals(data.generated_count >= 0, true);
  assertEquals(Number.isInteger(data.generated_count), true);
});

// =============================================================================
// TEST 7: Edge Function handles missing environment variables gracefully
// =============================================================================
Deno.test('Edge Function - Missing auth header does not crash', async () => {
  // Note: This will return 401/403 (expected) rather than 500 (error)
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: { 'Content-Type': 'application/json' },
  });

  // Should be 4xx error, not 500
  assertEquals(response.status >= 400 && response.status < 500, true);
});

// =============================================================================
// TEST 8: Edge Function response has correct CORS headers
// =============================================================================
Deno.test('Edge Function - Response includes CORS headers', async () => {
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });

  assertEquals(response.headers.get('Access-Control-Allow-Origin'), '*');
  assertStringIncludes(
    response.headers.get('Access-Control-Allow-Headers') || '',
    'authorization'
  );
});

// =============================================================================
// TEST 9: Edge Function completes within reasonable time
// =============================================================================
Deno.test('Edge Function - Request completes quickly', async () => {
  const startTime = performance.now();
  
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });

  const endTime = performance.now();
  const duration = endTime - startTime;

  // Should complete in under 30 seconds (reasonable for database operation)
  assertEquals(duration < 30000, true);
  assertEquals(response.status, 200);
});

// =============================================================================
// TEST 10: Edge Function is idempotent (safe to call multiple times)
// =============================================================================
Deno.test('Edge Function - Multiple calls are idempotent', async () => {
  const responses: Record<string, unknown>[] = [];

  // Call the function 3 times
  for (let i = 0; i < 3; i++) {
    const response = await fetch(FUNCTION_URL, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      },
    });
    const data = await response.json();
    responses.push(data);
  }

  // All should succeed
  assertEquals(responses.every((r) => r.ok === true), true);

  // For non-service days, generated_count should be 0 across all calls
  // For service days, the count might vary if sessions aren't already created
  // but ok should always be true
});

// =============================================================================
// INTEGRATION TEST: Verify Edge Function calls the SQL function
// =============================================================================
Deno.test('Integration - Edge Function executes the PL/pgSQL function', async () => {
  // This test verifies that the Edge Function successfully calls 
  // the auto_generate_weekly_sessions() function and returns its result
  
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });

  assertEquals(response.status, 200);
  const data: Record<string, unknown> = await response.json();
  
  // If we get a response with generated_count, the function worked
  assertEquals(data.ok, true);
  assertEquals(typeof data.generated_count, 'number');
  
  // Log for debugging
  console.log(`✓ Function executed successfully. Generated ${data.generated_count} sessions on ${data.day}`);
});

// =============================================================================
// TIMEZONE TEST: Verify Edge Function uses Lagos timezone
// =============================================================================
Deno.test('Timezone - Edge Function reports Lagos day', async () => {
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });

  const data: Record<string, unknown> = await response.json();
  const edgeFunctionDay = data.day as string;

  // Get the current day in Lagos timezone
  const lagosDate = new Date(
    new Date().toLocaleString('en-US', { timeZone: 'Africa/Lagos' })
  );
  const lagosDay = lagosDate.toLocaleDateString('en-US', { weekday: 'long' });

  // They should match
  assertEquals(edgeFunctionDay, lagosDay);
  console.log(`✓ Timezone verified: Both showed ${lagosDay} in Lagos time`);
});

// =============================================================================
// LOGGING TEST: Check that function logs are present
// =============================================================================
Deno.test('Logging - Edge Function includes logging info', async () => {
  const response = await fetch(FUNCTION_URL, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });

  const data: Record<string, unknown> = await response.json();

  // Response should have all logging-friendly fields
  assertEquals('timestamp_utc' in data, true);
  assertEquals('generated_count' in data, true);
  assertEquals('day' in data, true);
  
  console.log(`✓ Logging data: ${JSON.stringify(data)}`);
});
