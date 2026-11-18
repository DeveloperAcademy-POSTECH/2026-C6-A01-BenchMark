begin;

-- The authenticated inbox takes an account-membership lock in oi_actor().
-- PostgREST runs STABLE RPCs in READ ONLY transactions even for POST requests.
-- Preserve that lock and every authorization check; allow POST to use READ WRITE.
do $drift$
begin
  if not exists (
    select 1 from pg_proc
    where oid='public.oi_story_continuations(uuid,boolean,timestamptz,uuid,uuid[])'::regprocedure
      and md5(btrim(prosrc,E' \n\r\t'))='b7c004e3c32c7f85bfe126e6c60e8e2f'
      and provolatile in ('s','v') and prosecdef
      and prorettype='jsonb'::regtype
      and prolang=(select oid from pg_language where lanname='plpgsql')
      and proconfig=array['search_path=""']::text[]
  ) then
    raise exception 'Continuation transaction mode drift requires review';
  end if;
end; $drift$;

alter function public.oi_story_continuations(uuid,boolean,timestamptz,uuid,uuid[]) volatile;

notify pgrst,'reload schema';
commit;
