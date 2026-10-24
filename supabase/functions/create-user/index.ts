import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
});

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anon || !service) return json({ error: 'Server configuration missing' }, 500);
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Unauthorized' }, 401);
  const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: 'Unauthorized' }, 401);
  const adminClient = createClient(url, service);
  const { data: actor } = await adminClient.from('profiles').select('role,is_active').eq('id', user.id).maybeSingle();
  if (!actor || actor.role !== 'admin' || actor.is_active !== true) return json({ error: 'Admin role required' }, 403);
  let payload: Record<string, unknown>;
  try { payload = await req.json(); } catch { return json({ error: 'Invalid JSON body' }, 400); }
  const email = String(payload.email ?? '').trim().toLowerCase();
  const password = String(payload.password ?? '');
  const fullName = String(payload.full_name ?? '').trim();
  const role = String(payload.role ?? '');
  const studentNumber = String(payload.student_number ?? '').trim() || null;
  const department = String(payload.department ?? 'قسم معلم حاسوب').trim();
  if (!email || !email.includes('@') || password.length < 8 || !fullName || !['student','teacher','head','admin'].includes(role)) {
    return json({ error: 'أدخل الاسم والبريد وصلاحية صحيحة وكلمة مرور من 8 أحرف على الأقل.' }, 400);
  }
  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email, password, email_confirm: true, user_metadata: { full_name: fullName },
  });
  if (createError || !created.user) return json({ error: createError?.message ?? 'Could not create account' }, 400);
  const { error: profileError } = await adminClient.from('profiles').insert({
    id: created.user.id, full_name: fullName, email, role, student_number: studentNumber, department, is_active: true,
  });
  if (profileError) {
    await adminClient.auth.admin.deleteUser(created.user.id);
    return json({ error: `Profile creation failed: ${profileError.message}` }, 500);
  }
  return json({ id: created.user.id, email, full_name: fullName, role }, 201);
});
