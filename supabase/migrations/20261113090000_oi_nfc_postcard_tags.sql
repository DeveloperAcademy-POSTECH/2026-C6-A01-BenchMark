-- #291: NFC tags on campus carry only a tag ID. Operators link each tag to a story here,
-- so a locked tag can be pointed at another story or retired without rewriting it.
begin;

create table benchmark_private.oi_nfc_tags (
  tag_id text primary key check (tag_id ~ '^[a-z0-9-]{1,40}$'),
  story_id uuid references public.oi_stories(id) on delete set null,
  active boolean not null default true,
  -- Where the tag is installed, for operators only. Never returned to the public.
  note text not null default '' check (char_length(note) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table benchmark_private.oi_nfc_tags enable row level security;
revoke all on benchmark_private.oi_nfc_tags from public,anon,authenticated;
create index oi_nfc_tags_story_idx on benchmark_private.oi_nfc_tags(story_id);

-- Public lookup used by the App Clip and the full app. Returns a story ID only while the tag is
-- active and the story is publicly readable under the same rules as the anonymous story policies.
create function public.oi_nfc_postcard(p_tag text) returns uuid
language sql stable security definer set search_path='' as $$
  select s.id from benchmark_private.oi_nfc_tags t
  join public.oi_stories s on s.id=t.story_id
  where t.tag_id=p_tag and t.active and s.status='published'
    and not benchmark_private.oi_content_restricted(s.user_id)
    and not benchmark_private.oi_account_is_deleting(s.user_id);
$$;
revoke all on function public.oi_nfc_postcard(text) from public;
grant execute on function public.oi_nfc_postcard(text) to anon,authenticated;

-- Operator: create or update a tag. A null story keeps the tag but shows nothing.
create function public.oi_operator_set_nfc_tag(p_tag text, p_story uuid, p_active boolean, p_note text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare previous uuid; saved benchmark_private.oi_nfc_tags;
begin
  perform benchmark_private.oi_actor();
  if not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
  if p_tag is null or p_tag !~ '^[a-z0-9-]{1,40}$' or p_active is null
    or char_length(coalesce(p_note,'')) > 200 then
    raise exception 'Invalid tag' using errcode='22023'; end if;
  if p_story is not null and not exists(select 1 from public.oi_stories where id=p_story) then
    raise exception 'Story unavailable' using errcode='PT404'; end if;
  select story_id into previous from benchmark_private.oi_nfc_tags where tag_id=p_tag for update;
  insert into benchmark_private.oi_nfc_tags(tag_id,story_id,active,note)
    values(p_tag,p_story,p_active,coalesce(btrim(p_note),''))
    on conflict(tag_id) do update set story_id=excluded.story_id,active=excluded.active,note=excluded.note,updated_at=now()
    returning * into saved;
  if coalesce(p_story,previous) is not null then
    insert into benchmark_private.oi_audit(actor_id,action,target_id)
      values(auth.uid(),'nfc_tag:'||case when p_active and p_story is not null then 'link' else 'unlink' end,coalesce(p_story,previous));
  end if;
  return jsonb_build_object('tag_id',saved.tag_id,'story_id',saved.story_id,'active',saved.active,'note',saved.note,'updated_at',saved.updated_at);
end;
$$;
revoke all on function public.oi_operator_set_nfc_tag(text,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.oi_operator_set_nfc_tag(text,uuid,boolean,text) to authenticated;

-- Operator: every tag with the linked story's title and status, so a broken link is visible.
create function public.oi_operator_nfc_tags() returns jsonb
language plpgsql volatile security definer set search_path='' as $$
begin
  perform benchmark_private.oi_actor();
  if not benchmark_private.oi_is_operator() then raise exception 'Operator required' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('tag_id',t.tag_id,'story_id',t.story_id,'active',t.active,'note',t.note,
      'updated_at',t.updated_at,'story_title',s.title,'story_status',s.status) order by t.tag_id)
    from benchmark_private.oi_nfc_tags t left join public.oi_stories s on s.id=t.story_id
  ),'[]'::jsonb);
end;
$$;
revoke all on function public.oi_operator_nfc_tags() from public,anon,authenticated;
grant execute on function public.oi_operator_nfc_tags() to authenticated;

-- Postcard back (A): rendered by the app next to the front and uploaded as
-- card/<card_snapshot_id>-back.png. Sharing the reviewed snapshot ID means approving a card publishes
-- its matching back, and replacing the card retires the old back. The file is optional so stories
-- submitted by older app versions keep working; readers fall back to drawing the text themselves.
create function benchmark_private.oi_story_card_back_path(owner_id uuid, story_id uuid, snapshot_id uuid)
returns text language sql immutable strict set search_path='' as $$
  select owner_id::text||'/'||story_id::text||'/card/'||snapshot_id::text||'-back.png';
$$;
revoke all on function benchmark_private.oi_story_card_back_path(uuid,uuid,uuid) from public;
grant execute on function benchmark_private.oi_story_card_back_path(uuid,uuid,uuid) to anon,authenticated;

create policy oi_story_card_back_read on storage.objects for select to anon,authenticated using (
  bucket_id='oi-story-media' and (storage.foldername(name))[3]='card'
  and metadata->>'mimetype'='image/png' and exists (
    select 1 from public.oi_stories s
    where s.id::text=(storage.foldername(name))[2]
      and (s.status='published' or (s.status<>'deleted' and s.user_id=(select benchmark_private.oi_account_id())))
      and name=benchmark_private.oi_story_card_back_path(s.storage_owner_id,s.id,s.card_snapshot_id)
  )
);

notify pgrst,'reload schema';
commit;
