begin;
create function pg_temp.assert_denied(command text) returns void language plpgsql as $$
begin
 begin execute command;exception when insufficient_privilege then return;end;
 raise exception 'Reference catalog unexpectedly permits client write: %',command;
end; $$;
do $$ begin
 if not exists(select 1 from storage.buckets where id='oi-education-reference'
  and public and file_size_limit=1048576 and allowed_mime_types=array['application/json','image/webp'])
 then raise exception 'Public reference bucket contract differs';end if;
 if (select public from storage.buckets where id='oi-story-media') is distinct from false
 then raise exception 'User media must stay private';end if;
end $$;
set local role anon;
select pg_temp.assert_denied($q$insert into storage.objects(bucket_id,name) values('oi-education-reference','synthetic.json')$q$);
reset role;
insert into auth.users(id) values('e3780000-0000-4000-8000-000000000091');
set local role authenticated;
select set_config('request.jwt.claim.sub','e3780000-0000-4000-8000-000000000091',true);
select pg_temp.assert_denied($q$insert into storage.objects(bucket_id,name) values('oi-education-reference','synthetic.json')$q$);
do $$ begin
 begin update storage.buckets set public=false where id='oi-education-reference';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$ begin
 if (select public from storage.buckets where id='oi-education-reference') is distinct from true
 then raise exception 'Authenticated user changed reference bucket settings';end if;
end $$;
rollback;
