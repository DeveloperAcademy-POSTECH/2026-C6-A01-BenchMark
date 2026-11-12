begin;

create table benchmark_private.oi_apple_tokens (
  identity_id uuid primary key references auth.identities(id) on delete cascade,
  encrypted_token text not null check (length(encrypted_token) between 25 and 6000)
);
alter table benchmark_private.oi_apple_tokens enable row level security;
revoke all on benchmark_private.oi_apple_tokens from public, anon, authenticated;

-- The Edge Function binds Apple's verified code exchange to the authenticated user.
-- Hold membership stable and reject token writes once account deletion has begun.
create function public.oi_store_apple_token(p_user uuid, p_subject text, p_token text) returns void
language plpgsql security definer set search_path='' as $$
declare account uuid; apple_identity uuid;
begin
  select account_id into account from benchmark_private.oi_account_members where auth_user_id=p_user for share;
  if account is null or benchmark_private.oi_account_is_deleting(account) then
    raise exception 'Apple credential storage is unavailable' using errcode='42501';
  end if;
  select id into apple_identity from auth.identities
  where user_id=p_user and provider='apple' and provider_id=p_subject;
  if apple_identity is null then raise exception 'Apple identity mismatch' using errcode='42501'; end if;
  insert into benchmark_private.oi_apple_tokens(identity_id,encrypted_token) values(apple_identity,p_token)
    on conflict(identity_id) do update set encrypted_token=excluded.encrypted_token;
end;
$$;
revoke all on function public.oi_store_apple_token(uuid,text,text) from public, anon, authenticated;
grant execute on function public.oi_store_apple_token(uuid,text,text) to service_role;

create function public.oi_apple_revocation_credentials(p_account uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not benchmark_private.oi_account_is_deleting(p_account) then
    raise exception 'Account deletion has not been prepared' using errcode='42501';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('user_id',i.user_id,'subject',i.provider_id,
    'encrypted_token',t.encrypted_token) order by i.id),'[]'::jsonb)
  from benchmark_private.oi_account_members m join auth.identities i on i.user_id=m.auth_user_id
  left join benchmark_private.oi_apple_tokens t on t.identity_id=i.id
  where m.account_id=p_account and i.provider='apple');
end;
$$;
revoke all on function public.oi_apple_revocation_credentials(uuid) from public, anon, authenticated;
grant execute on function public.oi_apple_revocation_credentials(uuid) to service_role;
notify pgrst,'reload schema';
commit;
