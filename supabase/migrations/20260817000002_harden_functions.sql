-- Trigger helper functions must not be callable through the PostgREST RPC
-- surface (flagged by Supabase security advisors).
revoke execute on function public.handle_new_user() from anon, authenticated, public;
revoke execute on function public.set_updated_at() from anon, authenticated, public;
