create role anon nologin;
create role authenticated nologin;
create schema auth;
create schema storage;
create schema benchmark_private;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
grant usage on schema auth,storage to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,owner_id text,metadata jsonb,unique(bucket_id,name));
alter table storage.objects enable row level security;
grant select,insert,update,delete on storage.objects to anon,authenticated;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1];
$$;

-- Test-only Vault API stub for a stock local PostgreSQL. This deliberately does
-- not implement encryption or secure randomness; tests cover role boundaries,
-- named-secret creation/reuse and getter contracts, never Vault cryptography.
-- Production uses the installed Supabase Vault and pgcrypto functions instead.
create schema vault;
create schema extensions;
create table vault.secrets(id uuid primary key default gen_random_uuid(), name text unique,
  secret text not null, description text not null default '');
create view vault.decrypted_secrets as select id, name, secret as decrypted_secret from vault.secrets;
create function vault.create_secret(new_secret text, new_name text default null,
  new_description text default '', new_key_id uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare secret_id uuid;
begin
  insert into vault.secrets(name,secret,description) values(new_name,new_secret,new_description) returning id into secret_id;
  return secret_id;
end;
$$;
create function extensions.gen_random_bytes(integer) returns bytea
language sql volatile as $$ select decode(repeat('ab', $1), 'hex'); $$;
