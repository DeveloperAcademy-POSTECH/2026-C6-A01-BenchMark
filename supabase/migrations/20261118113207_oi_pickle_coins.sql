begin;

-- Private balances are changed only by the authenticated, audited operations below.
create table benchmark_private.oi_pickle_wallets (
  account_id uuid primary key references public.oi_profiles(id) on delete cascade,
  balance bigint not null default 0 check (balance>=0),
  updated_at timestamptz not null default clock_timestamp()
);
create table benchmark_private.oi_pickle_ledger (
  id bigint generated always as identity primary key,
  account_id uuid not null references public.oi_profiles(id) on delete cascade,
  event_key text not null unique,
  reason text not null check (reason in ('signup','certificate','collection','plant','outfit')),
  delta integer not null,
  created_at timestamptz not null default clock_timestamp(),
  check ((reason in ('signup','certificate','collection') and delta>0)
    or (reason in ('plant','outfit') and delta<=0))
);
create index oi_pickle_ledger_account on benchmark_private.oi_pickle_ledger(account_id,id desc);
create table benchmark_private.oi_pickle_unlimited_accounts (
  account_id uuid primary key references public.oi_profiles(id) on delete cascade
);
create table benchmark_private.oi_pickle_collection_rewards (
  account_id uuid not null references public.oi_profiles(id) on delete cascade,
  story_id uuid not null,
  credited boolean not null,
  primary key(account_id,story_id)
);
-- Story IDs intentionally survive collection removal and deletion of another author's story.
create table benchmark_private.oi_pickle_plant_receipts (
  story_id uuid primary key references public.oi_stories(id) on delete cascade,
  account_id uuid not null references public.oi_profiles(id) on delete cascade,
  cost integer not null check(cost in (0,30))
);
create table benchmark_private.oi_farmer_shop_catalog (
  item_key text primary key,
  character text not null check(character in ('kyu','cumber')),
  slot text not null check(slot in ('top','bottom','shoes','hat','accessory','set')),
  item_id text not null,
  check(item_key=character||':'||slot||':'||item_id)
);
create table benchmark_private.oi_farmer_owned_items (
  account_id uuid not null references public.oi_profiles(id) on delete cascade,
  item_key text not null references benchmark_private.oi_farmer_shop_catalog(item_key),
  acquired_at timestamptz not null default clock_timestamp(),
  primary key(account_id,item_key)
);
create table benchmark_private.oi_farmer_purchase_operations (
  operation_id uuid primary key,
  account_id uuid not null references public.oi_profiles(id) on delete cascade,
  item_key text not null references benchmark_private.oi_farmer_shop_catalog(item_key)
);

do $$ declare name text; begin
  foreach name in array array['oi_pickle_wallets','oi_pickle_ledger','oi_pickle_unlimited_accounts',
    'oi_pickle_collection_rewards','oi_pickle_plant_receipts','oi_farmer_shop_catalog','oi_farmer_owned_items','oi_farmer_purchase_operations'] loop
    execute format('alter table benchmark_private.%I enable row level security',name);
    execute format('revoke all on benchmark_private.%I from public,anon,authenticated,service_role',name);
  end loop;
end; $$;

-- The catalogue is the app's existing FarmerWardrobe.json wearable inventory.
insert into benchmark_private.oi_farmer_shop_catalog(item_key,character,slot,item_id) values
  ('kyu:top:kyu-3916-2673','kyu','top','kyu-3916-2673'),
  ('kyu:top:kyu-3916-2718','kyu','top','kyu-3916-2718'),
  ('kyu:top:kyu-3916-2693','kyu','top','kyu-3916-2693'),
  ('kyu:top:kyu-3916-2703','kyu','top','kyu-3916-2703'),
  ('kyu:top:kyu-3916-2698','kyu','top','kyu-3916-2698'),
  ('kyu:top:kyu-3916-2683','kyu','top','kyu-3916-2683'),
  ('kyu:top:kyu-4165-4910','kyu','top','kyu-4165-4910'),
  ('kyu:top:kyu-3916-2738','kyu','top','kyu-3916-2738'),
  ('kyu:top:kyu-3916-2678','kyu','top','kyu-3916-2678'),
  ('kyu:top:kyu-3916-2733','kyu','top','kyu-3916-2733'),
  ('kyu:top:kyu-3916-2688','kyu','top','kyu-3916-2688'),
  ('kyu:top:kyu-3916-2713','kyu','top','kyu-3916-2713'),
  ('kyu:top:kyu-3916-2728','kyu','top','kyu-3916-2728'),
  ('kyu:top:kyu-3916-2723','kyu','top','kyu-3916-2723'),
  ('kyu:top:kyu-3916-2708','kyu','top','kyu-3916-2708'),
  ('kyu:top:kyu-4146-4855','kyu','top','kyu-4146-4855'),
  ('kyu:top:kyu-4146-4865','kyu','top','kyu-4146-4865'),
  ('kyu:top:kyu-4146-4875','kyu','top','kyu-4146-4875'),
  ('kyu:top:kyu-4146-4885','kyu','top','kyu-4146-4885'),
  ('kyu:bottom:kyu-3921-3222','kyu','bottom','kyu-3921-3222'),
  ('kyu:bottom:kyu-3921-3227','kyu','bottom','kyu-3921-3227'),
  ('kyu:bottom:kyu-3921-3237','kyu','bottom','kyu-3921-3237'),
  ('kyu:bottom:kyu-3921-3242','kyu','bottom','kyu-3921-3242'),
  ('kyu:bottom:kyu-3921-3232','kyu','bottom','kyu-3921-3232'),
  ('kyu:bottom:kyu-3921-3247','kyu','bottom','kyu-3921-3247'),
  ('kyu:bottom:kyu-3921-3267','kyu','bottom','kyu-3921-3267'),
  ('kyu:bottom:kyu-3921-3252','kyu','bottom','kyu-3921-3252'),
  ('kyu:bottom:kyu-3921-3272','kyu','bottom','kyu-3921-3272'),
  ('kyu:bottom:kyu-3921-3277','kyu','bottom','kyu-3921-3277'),
  ('kyu:bottom:kyu-3921-3282','kyu','bottom','kyu-3921-3282'),
  ('kyu:bottom:kyu-3921-3257','kyu','bottom','kyu-3921-3257'),
  ('kyu:bottom:kyu-3921-3262','kyu','bottom','kyu-3921-3262'),
  ('kyu:set:kyu-3921-3777','kyu','set','kyu-3921-3777'),
  ('kyu:set:kyu-3921-3787','kyu','set','kyu-3921-3787'),
  ('kyu:shoes:kyu-4175-6339','kyu','shoes','kyu-4175-6339'),
  ('kyu:shoes:kyu-4148-5650','kyu','shoes','kyu-4148-5650'),
  ('kyu:shoes:kyu-3921-3448','kyu','shoes','kyu-3921-3448'),
  ('kyu:shoes:kyu-3921-3473','kyu','shoes','kyu-3921-3473'),
  ('kyu:shoes:kyu-3921-3491','kyu','shoes','kyu-3921-3491'),
  ('kyu:shoes:kyu-3921-3503','kyu','shoes','kyu-3921-3503'),
  ('kyu:shoes:kyu-3921-3518','kyu','shoes','kyu-3921-3518'),
  ('kyu:shoes:kyu-3921-3533','kyu','shoes','kyu-3921-3533'),
  ('kyu:shoes:kyu-3921-3548','kyu','shoes','kyu-3921-3548'),
  ('kyu:shoes:kyu-3921-3563','kyu','shoes','kyu-3921-3563'),
  ('kyu:shoes:kyu-3921-3578','kyu','shoes','kyu-3921-3578'),
  ('kyu:shoes:kyu-3921-3593','kyu','shoes','kyu-3921-3593'),
  ('kyu:shoes:kyu-3921-3608','kyu','shoes','kyu-3921-3608'),
  ('kyu:accessory:kyu-3927-3847','kyu','accessory','kyu-3927-3847'),
  ('kyu:accessory:kyu-3927-3837','kyu','accessory','kyu-3927-3837'),
  ('kyu:accessory:kyu-3927-3959','kyu','accessory','kyu-3927-3959'),
  ('kyu:accessory:kyu-3927-3972','kyu','accessory','kyu-3927-3972'),
  ('kyu:accessory:kyu-4173-5343','kyu','accessory','kyu-4173-5343'),
  ('kyu:accessory:kyu-3927-3899','kyu','accessory','kyu-3927-3899'),
  ('kyu:accessory:kyu-3927-3911','kyu','accessory','kyu-3927-3911'),
  ('kyu:accessory:kyu-3927-3923','kyu','accessory','kyu-3927-3923'),
  ('kyu:accessory:kyu-3927-3984','kyu','accessory','kyu-3927-3984'),
  ('kyu:accessory:kyu-3927-3867','kyu','accessory','kyu-3927-3867'),
  ('kyu:accessory:kyu-3927-3935','kyu','accessory','kyu-3927-3935'),
  ('kyu:accessory:kyu-3927-3947','kyu','accessory','kyu-3927-3947'),
  ('kyu:accessory:kyu-4165-4960','kyu','accessory','kyu-4165-4960'),
  ('kyu:accessory:kyu-4165-4972','kyu','accessory','kyu-4165-4972'),
  ('kyu:accessory:kyu-4165-4984','kyu','accessory','kyu-4165-4984'),
  ('kyu:accessory:kyu-4165-4996','kyu','accessory','kyu-4165-4996'),
  ('cumber:top:cumber-4148-5140','cumber','top','cumber-4148-5140'),
  ('cumber:top:cumber-4148-5185','cumber','top','cumber-4148-5185'),
  ('cumber:top:cumber-4148-5160','cumber','top','cumber-4148-5160'),
  ('cumber:top:cumber-4148-5170','cumber','top','cumber-4148-5170'),
  ('cumber:top:cumber-4148-5165','cumber','top','cumber-4148-5165'),
  ('cumber:top:cumber-4148-5150','cumber','top','cumber-4148-5150'),
  ('cumber:top:cumber-4148-5175','cumber','top','cumber-4148-5175'),
  ('cumber:top:cumber-4148-5205','cumber','top','cumber-4148-5205'),
  ('cumber:top:cumber-4148-5145','cumber','top','cumber-4148-5145'),
  ('cumber:top:cumber-4148-5200','cumber','top','cumber-4148-5200'),
  ('cumber:top:cumber-4148-5155','cumber','top','cumber-4148-5155'),
  ('cumber:top:cumber-4148-5180','cumber','top','cumber-4148-5180'),
  ('cumber:top:cumber-4148-5195','cumber','top','cumber-4148-5195'),
  ('cumber:top:cumber-4148-5190','cumber','top','cumber-4148-5190'),
  ('cumber:top:cumber-4148-5210','cumber','top','cumber-4148-5210'),
  ('cumber:top:cumber-4148-5225','cumber','top','cumber-4148-5225'),
  ('cumber:top:cumber-4148-5220','cumber','top','cumber-4148-5220'),
  ('cumber:top:cumber-4148-5215','cumber','top','cumber-4148-5215'),
  ('cumber:top:cumber-4148-5230','cumber','top','cumber-4148-5230'),
  ('cumber:bottom:cumber-4148-5061','cumber','bottom','cumber-4148-5061'),
  ('cumber:bottom:cumber-4148-5071','cumber','bottom','cumber-4148-5071'),
  ('cumber:bottom:cumber-4148-5081','cumber','bottom','cumber-4148-5081'),
  ('cumber:bottom:cumber-4148-5076','cumber','bottom','cumber-4148-5076'),
  ('cumber:bottom:cumber-4148-5066','cumber','bottom','cumber-4148-5066'),
  ('cumber:bottom:cumber-4148-5086','cumber','bottom','cumber-4148-5086'),
  ('cumber:bottom:cumber-4148-5106','cumber','bottom','cumber-4148-5106'),
  ('cumber:bottom:cumber-4148-5091','cumber','bottom','cumber-4148-5091'),
  ('cumber:bottom:cumber-4148-5111','cumber','bottom','cumber-4148-5111'),
  ('cumber:bottom:cumber-4148-5116','cumber','bottom','cumber-4148-5116'),
  ('cumber:bottom:cumber-4148-5121','cumber','bottom','cumber-4148-5121'),
  ('cumber:bottom:cumber-4148-5096','cumber','bottom','cumber-4148-5096'),
  ('cumber:bottom:cumber-4148-5101','cumber','bottom','cumber-4148-5101'),
  ('cumber:set:cumber-4148-5128','cumber','set','cumber-4148-5128'),
  ('cumber:shoes:cumber-4148-5672','cumber','shoes','cumber-4148-5672'),
  ('cumber:shoes:cumber-4148-5661','cumber','shoes','cumber-4148-5661'),
  ('cumber:shoes:cumber-4148-5007','cumber','shoes','cumber-4148-5007'),
  ('cumber:shoes:cumber-4148-5012','cumber','shoes','cumber-4148-5012'),
  ('cumber:shoes:cumber-4148-5017','cumber','shoes','cumber-4148-5017'),
  ('cumber:shoes:cumber-4148-5022','cumber','shoes','cumber-4148-5022'),
  ('cumber:shoes:cumber-4148-5027','cumber','shoes','cumber-4148-5027'),
  ('cumber:shoes:cumber-4148-5032','cumber','shoes','cumber-4148-5032'),
  ('cumber:shoes:cumber-4148-5037','cumber','shoes','cumber-4148-5037'),
  ('cumber:shoes:cumber-4148-5042','cumber','shoes','cumber-4148-5042'),
  ('cumber:shoes:cumber-4148-5047','cumber','shoes','cumber-4148-5047'),
  ('cumber:accessory:cumber-4148-5237','cumber','accessory','cumber-4148-5237'),
  ('cumber:accessory:cumber-4148-5250','cumber','accessory','cumber-4148-5250'),
  ('cumber:accessory:cumber-4148-5256','cumber','accessory','cumber-4148-5256'),
  ('cumber:accessory:cumber-4148-5261','cumber','accessory','cumber-4148-5261'),
  ('cumber:accessory:cumber-4148-5266','cumber','accessory','cumber-4148-5266'),
  ('cumber:accessory:cumber-4148-5271','cumber','accessory','cumber-4148-5271'),
  ('cumber:accessory:cumber-4148-5278','cumber','accessory','cumber-4148-5278'),
  ('cumber:accessory:cumber-4148-5288','cumber','accessory','cumber-4148-5288'),
  ('cumber:accessory:cumber-4148-5293','cumber','accessory','cumber-4148-5293'),
  ('cumber:accessory:cumber-4148-5298','cumber','accessory','cumber-4148-5298'),
  ('kyu:set:legacy-classic','kyu','set','legacy-classic'),
  ('kyu:set:legacy-casual','kyu','set','legacy-casual');

create function benchmark_private.oi_pickle_unlimited(p_account uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from benchmark_private.oi_pickle_unlimited_accounts where account_id=p_account);
$$;

-- Lazy creation avoids granting another signup bonus to a temporary identity used only as a merge proof.
create function benchmark_private.oi_ensure_pickle_wallet(p_account uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  insert into benchmark_private.oi_pickle_wallets(account_id,balance) values(p_account,10) on conflict do nothing;
  if found then
    insert into benchmark_private.oi_pickle_ledger(account_id,event_key,reason,delta)
      values(p_account,'signup:'||p_account::text,'signup',10);
  end if;
end;
$$;

create function benchmark_private.oi_pickle_apply(p_account uuid,p_event text,p_reason text,p_delta integer)
returns boolean language plpgsql security definer set search_path='' as $$
declare current_balance bigint; actual_delta integer:=p_delta; previous benchmark_private.oi_pickle_ledger;
begin
  perform benchmark_private.oi_ensure_pickle_wallet(p_account);
  select balance into current_balance from benchmark_private.oi_pickle_wallets where account_id=p_account for update;
  select * into previous from benchmark_private.oi_pickle_ledger where event_key=p_event;
  if found then
    if previous.account_id<>p_account or previous.reason<>p_reason then
      raise exception 'pickle_coin_event_conflict' using errcode='PT409';
    end if;
    return false;
  end if;
  if p_delta<0 and benchmark_private.oi_pickle_unlimited(p_account) then actual_delta:=0; end if;
  if current_balance+actual_delta<0 then
    raise exception 'pickle_coins_insufficient' using errcode='PT402';
  end if;
  insert into benchmark_private.oi_pickle_ledger(account_id,event_key,reason,delta)
    values(p_account,p_event,p_reason,actual_delta);
  update benchmark_private.oi_pickle_wallets set balance=balance+actual_delta,updated_at=clock_timestamp()
    where account_id=p_account;
  return true;
end;
$$;

create function benchmark_private.oi_pickle_wallet_json(p_account uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('account_id',p_account,'balance',w.balance,
    'unlimited',benchmark_private.oi_pickle_unlimited(p_account),'plant_cost',30,'outfit_cost',3,
    'owned_items',coalesce((select jsonb_agg(item_key order by item_key)
      from benchmark_private.oi_farmer_owned_items where account_id=p_account),'[]'::jsonb))
  from benchmark_private.oi_pickle_wallets w where w.account_id=p_account;
$$;

create function public.oi_pickle_wallet() returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor();
begin
  perform benchmark_private.oi_ensure_pickle_wallet(actor);
  return benchmark_private.oi_pickle_wallet_json(actor);
end;
$$;
create function public.oi_farmer_inventory() returns jsonb
language sql security invoker set search_path='' as $$ select public.oi_pickle_wallet(); $$;

create function public.oi_purchase_farmer_item(p_item text,p_operation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); previous benchmark_private.oi_farmer_purchase_operations; purchased boolean:=false;
begin
  if p_operation is null or p_item is null or not exists(select 1 from benchmark_private.oi_farmer_shop_catalog
      where item_key=p_item and item_id not in ('legacy-classic','legacy-casual')) then
    raise exception 'invalid_farmer_shop_item' using errcode='22023';
  end if;
  perform benchmark_private.oi_ensure_pickle_wallet(actor);
  perform 1 from benchmark_private.oi_pickle_wallets where account_id=actor for update;
  select * into previous from benchmark_private.oi_farmer_purchase_operations where operation_id=p_operation;
  if found and (previous.account_id<>actor or previous.item_key<>p_item) then
    raise exception 'farmer_purchase_operation_conflict' using errcode='PT409';
  end if;
  if not exists(select 1 from benchmark_private.oi_farmer_owned_items where account_id=actor and item_key=p_item) then
    perform benchmark_private.oi_pickle_apply(actor,'outfit:'||actor::text||':'||p_item,'outfit',-3);
    insert into benchmark_private.oi_farmer_owned_items(account_id,item_key) values(actor,p_item);
    purchased:=true;
  end if;
  insert into benchmark_private.oi_farmer_purchase_operations values(p_operation,actor,p_item) on conflict do nothing;
  if not exists(select 1 from benchmark_private.oi_farmer_purchase_operations
      where operation_id=p_operation and account_id=actor and item_key=p_item) then
    raise exception 'farmer_purchase_operation_conflict' using errcode='PT409';
  end if;
  return jsonb_build_object('item',p_item,'purchased',purchased,'wallet',benchmark_private.oi_pickle_wallet_json(actor));
end;
$$;

-- Preserve existing worn items and both legacy presets. No retroactive debit.
insert into benchmark_private.oi_farmer_owned_items(account_id,item_key)
select o.account_id,c.item_key from benchmark_private.oi_farmer_outfits o
cross join lateral jsonb_each_text(o.outfit->'slots') s
join benchmark_private.oi_farmer_shop_catalog c
  on c.character=o.outfit->>'character' and c.slot=s.key and c.item_id=s.value on conflict do nothing;

create or replace function benchmark_private.oi_save_farmer_outfit(p_outfit jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor();
begin
  if not benchmark_private.oi_valid_farmer_outfit(p_outfit) then
    raise exception 'invalid_farmer_outfit' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_each_text(p_outfit->'slots') s where not exists(
    select 1 from benchmark_private.oi_farmer_shop_catalog c where c.character=p_outfit->>'character'
      and c.slot=s.key and c.item_id=s.value and (c.item_id in ('legacy-classic','legacy-casual')
        or exists(select 1 from benchmark_private.oi_farmer_owned_items i where i.account_id=actor and i.item_key=c.item_key)))) then
    raise exception 'farmer_item_not_owned' using errcode='PT403';
  end if;
  insert into benchmark_private.oi_farmer_outfits(account_id,outfit) values(actor,p_outfit)
    on conflict(account_id) do update set outfit=excluded.outfit,updated_at=now();
  return benchmark_private.oi_read_farmer_outfit();
end;
$$;

-- Existing canonical accounts receive their one-time welcome balance.
do $$ declare account uuid; begin
  for account in select distinct account_id from benchmark_private.oi_account_members loop
    perform benchmark_private.oi_ensure_pickle_wallet(account);
  end loop;
end; $$;
-- Past collections are durable no-repeat markers, not newly earned rewards.
insert into benchmark_private.oi_pickle_collection_rewards(account_id,story_id,credited)
select user_id,story_id,false from public.oi_collections;
insert into benchmark_private.oi_pickle_plant_receipts(story_id,account_id,cost)
select id,user_id,0 from public.oi_stories where status='published';

-- Delegate the existing audited continuation/mutation implementation without duplicating its source.
do $$ declare definition text:=pg_get_functiondef('benchmark_private.oi_mutate_internal(text,jsonb,text)'::regprocedure);
  anchor constant text:='FUNCTION benchmark_private.oi_mutate_internal(';
begin
  if (select md5(btrim(prosrc,E' \n\r\t')) from pg_proc where oid='benchmark_private.oi_mutate_internal(text,jsonb,text)'::regprocedure)
      not in ('ffac8db414a94f3f567895082c3698a4','f43fb11cc735b30c3ddd66c727a1374b')
    or length(definition)-length(replace(definition,anchor,''))<>length(anchor)
    or strpos(definition,'benchmark_private.oi_mutate_continuation_base(action,payload,moderation_step)')=0 then
    raise exception 'Pickle coin mutation drift requires review';
  end if;
  execute replace(definition,anchor,'FUNCTION benchmark_private.oi_mutate_pickle_base(');
end; $$;

create or replace function benchmark_private.oi_mutate_internal(action text,payload jsonb,moderation_step text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid; result jsonb; target uuid; owner_id uuid; reward integer:=0; cost integer:=0;
begin
  if action='review_story' and payload->>'status'='published' then
    raise exception 'The author must plant the reviewed story' using errcode='PT426';
  end if;
  result:=benchmark_private.oi_mutate_pickle_base(action,payload,moderation_step);
  if action='collect' then
    actor:=benchmark_private.oi_actor(); target:=(result->>'id')::uuid;
    select user_id into owner_id from public.oi_stories where id=target;
    if owner_id<>actor then
      insert into benchmark_private.oi_pickle_collection_rewards(account_id,story_id,credited)
        values(actor,target,true) on conflict do nothing;
      if found then
        perform benchmark_private.oi_pickle_apply(actor,'collect:'||actor::text||':'||target::text,'collection',1);
        reward:=1;
      end if;
    end if;
    perform benchmark_private.oi_ensure_pickle_wallet(actor);
    result:=result||jsonb_build_object('coin_reward',reward,'wallet',benchmark_private.oi_pickle_wallet_json(actor));
  elsif (action='submit_story' and moderation_step='publish')
    or (action='review_story' and payload->>'status'='published') then
    actor:=(result->>'user_id')::uuid; target:=(result->>'id')::uuid;
    insert into benchmark_private.oi_pickle_plant_receipts(story_id,account_id,cost)
      values(target,actor,case when benchmark_private.oi_pickle_unlimited(actor) then 0 else 30 end) on conflict do nothing;
    if found then
      perform benchmark_private.oi_pickle_apply(actor,'plant:'||target::text,'plant',-30);
      if not benchmark_private.oi_pickle_unlimited(actor) then cost:=30; end if;
    end if;
    perform benchmark_private.oi_ensure_pickle_wallet(actor);
    result:=result||jsonb_build_object('coin_cost',cost,'wallet',benchmark_private.oi_pickle_wallet_json(actor));
  end if;
  return result;
end;
$$;

create function benchmark_private.oi_merge_pickle_accounts(p_target uuid,p_source uuid) returns void
language plpgsql security definer set search_path='' as $$
declare source_balance bigint;
begin
  perform 1 from benchmark_private.oi_pickle_wallets where account_id in(p_target,p_source) order by account_id for update;
  select balance into source_balance from benchmark_private.oi_pickle_wallets where account_id=p_source;
  if found then
    insert into benchmark_private.oi_pickle_wallets(account_id,balance) values(p_target,source_balance)
      on conflict(account_id) do update set balance=oi_pickle_wallets.balance+excluded.balance,updated_at=clock_timestamp();
    update benchmark_private.oi_pickle_ledger set account_id=p_target where account_id=p_source;
    delete from benchmark_private.oi_pickle_wallets where account_id=p_source;
  end if;
  insert into benchmark_private.oi_pickle_collection_rewards(account_id,story_id,credited)
    select p_target,story_id,credited from benchmark_private.oi_pickle_collection_rewards where account_id=p_source
    on conflict(account_id,story_id) do update set credited=oi_pickle_collection_rewards.credited or excluded.credited;
  delete from benchmark_private.oi_pickle_collection_rewards where account_id=p_source;
  insert into benchmark_private.oi_farmer_owned_items(account_id,item_key,acquired_at)
    select p_target,item_key,acquired_at from benchmark_private.oi_farmer_owned_items where account_id=p_source on conflict do nothing;
  delete from benchmark_private.oi_farmer_owned_items where account_id=p_source;
  update benchmark_private.oi_farmer_purchase_operations set account_id=p_target where account_id=p_source;
  update benchmark_private.oi_pickle_plant_receipts set account_id=p_target where account_id=p_source;
  insert into benchmark_private.oi_pickle_unlimited_accounts(account_id)
    select p_target from benchmark_private.oi_pickle_unlimited_accounts where account_id=p_source on conflict do nothing;
  delete from benchmark_private.oi_pickle_unlimited_accounts where account_id=p_source;
end;
$$;

do $$ declare definition text:=pg_get_functiondef('public.oi_merge_accounts(text,uuid,uuid,uuid,uuid,uuid,uuid,boolean)'::regprocedure);
  anchor constant text:='  cutover:=clock_timestamp();';
  counts constant text:='      ''stories'',(select count(*) from public.oi_stories where user_id in(target_account,source_account)),';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor)
    or length(definition)-length(replace(definition,counts,''))<>length(counts) then
    raise exception 'Pickle coin account merge drift requires review';
  end if;
  definition:=replace(definition,anchor,'  perform benchmark_private.oi_merge_pickle_accounts(target_account,source_account);'||chr(10)||anchor);
  definition:=replace(definition,counts,$new$      'pickle_state',(select jsonb_agg(jsonb_build_array(account_id,balance,updated_at) order by account_id)
        from benchmark_private.oi_pickle_wallets where account_id in(target_account,source_account)),
$new$||counts);
  execute definition;
end; $$;

do $$ declare fn regprocedure; begin
  for fn in select oid::regprocedure from pg_proc where pronamespace='benchmark_private'::regnamespace
    and (proname like 'oi_pickle_%' or proname in ('oi_ensure_pickle_wallet','oi_mutate_pickle_base','oi_merge_pickle_accounts')) loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',fn);
  end loop;
end; $$;
revoke all on function benchmark_private.oi_mutate_internal(text,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function public.oi_pickle_wallet(),public.oi_farmer_inventory(),public.oi_purchase_farmer_item(text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.oi_pickle_wallet(),public.oi_farmer_inventory(),public.oi_purchase_farmer_item(text,uuid) to authenticated;



-- New AI-only reward verification shares the existing private evidence storage
-- and deletion lifecycle. Retired writing-grant intake/review RPCs stay retired.
alter table public.oi_evidence_requests
  add column coin_verification boolean not null default false,
  add column coin_consent_version integer check(coin_consent_version is null or coin_consent_version=1),
  add column coin_analysis_started_at timestamptz;
create table benchmark_private.oi_coin_evidence_quota (
  account_id uuid primary key references public.oi_profiles(id) on delete cascade,
  window_started_at timestamptz not null,
  attempts integer not null
);
create table benchmark_private.oi_coin_certificate_claims (
  evidence_id uuid primary key references public.oi_evidence_requests(id) on delete cascade,
  sha256 text not null unique check(sha256 ~ '^[0-9a-f]{64}$'),
  semantic_digest text check(semantic_digest is null or semantic_digest ~ '^[0-9a-f]{64}$'),
  reference_digest text unique check(reference_digest is null or reference_digest ~ '^[0-9a-f]{64}$')
);
create index oi_coin_certificate_claims_semantic on benchmark_private.oi_coin_certificate_claims(semantic_digest);
alter table benchmark_private.oi_coin_evidence_quota enable row level security;
alter table benchmark_private.oi_coin_certificate_claims enable row level security;
revoke all on benchmark_private.oi_coin_evidence_quota,benchmark_private.oi_coin_certificate_claims from public,anon,authenticated,service_role;

-- Unknown historical certificate identity must be resolved before a deployment
-- can honestly promise one reward per distinct certificate.
do $$ declare request record; begin
  if exists(select 1 from public.oi_evidence_requests e left join benchmark_private.oi_evidence_fingerprints f
      on f.evidence_id=e.id where e.status='approved' and (f.evidence_id is null
        or f.semantic_digest is null or f.submitted_at is distinct from e.submitted_at)) then
    raise exception 'Approved evidence needs verified fingerprints before PickleCoin backfill';
  end if;
  for request in select e.id,e.user_id,f.sha256,f.semantic_digest from public.oi_evidence_requests e
      join benchmark_private.oi_evidence_fingerprints f on f.evidence_id=e.id where e.status='approved'
      order by e.reviewed_at nulls last,e.created_at,e.id loop
    if not exists(select 1 from benchmark_private.oi_coin_certificate_claims c
      where c.sha256=request.sha256 or (request.semantic_digest is not null and c.semantic_digest=request.semantic_digest)) then
      insert into benchmark_private.oi_coin_certificate_claims values(request.id,request.sha256,request.semantic_digest,null);
      perform benchmark_private.oi_pickle_apply(request.user_id,'certificate:'||request.id::text,'certificate',30);
    end if;
  end loop;
end; $$;

create function public.oi_start_coin_evidence(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); request public.oi_evidence_requests;
begin
  if p_id is null then raise exception 'Evidence ID required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('coin-request-account:'||actor::text,506));
  perform benchmark_private.oi_ensure_pickle_wallet(actor);
  select * into request from public.oi_evidence_requests where id=p_id;
  if found then
    if request.user_id<>actor or not request.coin_verification then
      raise exception 'Evidence request unavailable' using errcode='42501';
    end if;
    return to_jsonb(request);
  end if;
  if (select count(*) from public.oi_evidence_requests where user_id=actor and coin_verification
      and (created_at>statement_timestamp()-interval '1 minute' or status in ('draft','pending')))>=10 then
    raise exception 'Too many certificate requests' using errcode='PT429';
  end if;
  insert into public.oi_evidence_requests(id,user_id,storage_owner_id,coin_verification)
    values(p_id,actor,auth.uid(),true) on conflict do nothing;
  select * into request from public.oi_evidence_requests where id=p_id;
  if request.user_id<>actor or not request.coin_verification then
    raise exception 'Evidence request unavailable' using errcode='42501';
  end if;
  return to_jsonb(request);
end;
$$;

create function public.oi_submit_coin_evidence(p_id uuid,p_object_path text,p_consent_version integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); request public.oi_evidence_requests;
begin
  select * into request from public.oi_evidence_requests where id=p_id and user_id=actor and coin_verification for update;
  if not found then raise exception 'Evidence request unavailable' using errcode='42501'; end if;
  if p_consent_version is distinct from 1 then raise exception 'Certificate AI consent required' using errcode='22023'; end if;
  if request.status='pending' and request.object_path=p_object_path then return to_jsonb(request); end if;
  if request.status<>'draft' or p_object_path is null
    or not starts_with(p_object_path,request.storage_owner_id::text||'/'||request.id::text||'/')
    or cardinality(string_to_array(p_object_path,'/'))<>3
    or split_part(p_object_path,'/',3) in ('','.','..') or p_object_path ~ '[[:cntrl:]]'
    or position(chr(92) in p_object_path)>0
    or not exists(select 1 from storage.objects o where o.bucket_id='oi-evidence' and o.name=p_object_path
      and o.metadata->>'mimetype' in ('image/jpeg','image/png','application/pdf')) then
    raise exception 'Upload a certificate before submitting' using errcode='22023';
  end if;
  update public.oi_evidence_requests set status='pending',object_path=p_object_path,
    coin_consent_version=1,submitted_at=clock_timestamp() where id=p_id returning * into request;
  return to_jsonb(request);
end;
$$;

-- New insert-only uploads are limited to a new coin-verification draft. All
-- older intake paths and replacement of existing objects remain denied.
drop policy oi_retired_evidence_no_insert on storage.objects;
create policy oi_retired_evidence_no_insert on storage.objects as restrictive for insert to anon,authenticated
with check(bucket_id is distinct from 'oi-evidence' or exists(
  select 1 from public.oi_evidence_requests e where e.coin_verification and e.status='draft'
    and e.user_id=(select benchmark_private.oi_account_id())
    and e.storage_owner_id::text=(storage.foldername(name))[1]
    and e.id::text=(storage.foldername(name))[2]
    and cardinality(string_to_array(name,'/'))=3));

create function public.oi_cancel_coin_evidence(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); request public.oi_evidence_requests;
begin
  if p_id is null then raise exception 'Evidence ID required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('coin-request-account:'||actor::text,506));
  -- Reserve a cancelled ID even when the start response was lost before the
  -- request existed. A late start/submit cannot revive this user's operation.
  if not exists(select 1 from public.oi_evidence_requests where id=p_id) then
    perform public.oi_start_coin_evidence(p_id);
  end if;
  select * into request from public.oi_evidence_requests where id=p_id for update;
  if request.user_id<>actor or not request.coin_verification then
    raise exception 'Evidence request unavailable' using errcode='42501';
  end if;
  if request.status in ('draft','pending') then
    update public.oi_evidence_requests set status='rejected',review_note='certificate_cancelled',
      reviewed_at=clock_timestamp(),reviewer_id=null where id=p_id returning * into request;
  end if;
  perform benchmark_private.oi_ensure_pickle_wallet(actor);
  return jsonb_build_object('request',to_jsonb(request),'wallet',benchmark_private.oi_pickle_wallet_json(actor),
    'duplicate',request.review_note='duplicate_certificate','credited',false);
end;
$$;

create function benchmark_private.oi_coin_evidence_actor(p_user uuid,p_session uuid) returns uuid
language plpgsql security definer set search_path='' as $$
begin
  if current_setting('role',true) is distinct from 'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;
  if p_user is null or p_session is null or not exists(select 1 from auth.sessions where id=p_session and user_id=p_user) then
    raise exception 'Sign in again' using errcode='PT401';
  end if;
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user,'session_id',p_session,'role','authenticated')::text,true);
  return benchmark_private.oi_actor();
end;
$$;

create function public.oi_prepare_coin_evidence(p_user uuid,p_session uuid,p_request uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_coin_evidence_actor(p_user,p_session);
  request public.oi_evidence_requests; clock timestamptz:=clock_timestamp();
begin
  select * into request from public.oi_evidence_requests where id=p_request and user_id=actor for update;
  if not found or not request.coin_verification or request.status<>'pending'
    or request.coin_consent_version is distinct from 1 or request.object_path is null or request.submitted_at is null then
    raise exception 'Certificate request unavailable' using errcode='PT409';
  end if;
  if request.coin_analysis_started_at>clock-interval '120 seconds' then
    raise exception 'coin_evidence_analysis_in_progress' using errcode='PT409';
  end if;
  insert into benchmark_private.oi_coin_evidence_quota as quota values(actor,clock,1)
    on conflict(account_id) do update set
      window_started_at=case when quota.window_started_at<=clock-interval '1 minute' then clock else quota.window_started_at end,
      attempts=case when quota.window_started_at<=clock-interval '1 minute' then 1 else quota.attempts+1 end
    where quota.attempts<5 or quota.window_started_at<=clock-interval '1 minute';
  if not found then raise exception 'Too many certificate analysis attempts' using errcode='PT429'; end if;
  update public.oi_evidence_requests set coin_analysis_started_at=clock where id=p_request returning * into request;
  return to_jsonb(request);
end;
$$;

create function public.oi_coin_evidence_review(p_user uuid,p_session uuid,p_request uuid,p_object_path text,
  p_submitted_at timestamptz,p_sha256 text,p_semantic_digest text,p_decision text,p_reason text,
  p_secondary_digest text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_coin_evidence_actor(p_user,p_session);
  request public.oi_evidence_requests; duplicate boolean:=false; credited boolean:=false; lock_key bigint;
begin
  if p_decision is null or p_decision not in ('approved','rejected','needs_review')
    or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$'
    or (p_semantic_digest is not null and p_semantic_digest !~ '^[0-9a-f]{64}$')
    or (p_secondary_digest is not null and p_secondary_digest !~ '^[0-9a-f]{64}$')
    or (p_decision='approved' and p_semantic_digest is null) or length(coalesce(p_reason,''))>2000 then
    raise exception 'Invalid certificate review decision' using errcode='22023';
  end if;
  select * into request from public.oi_evidence_requests where id=p_request and user_id=actor for update;
  if not found or not request.coin_verification or request.coin_consent_version is distinct from 1
    or request.object_path is distinct from p_object_path or request.submitted_at is distinct from p_submitted_at then
    raise exception 'Certificate changed during analysis' using errcode='PT409';
  end if;
  if request.status in ('approved','rejected','changes_requested') then
    if not exists(select 1 from benchmark_private.oi_evidence_fingerprints f where f.evidence_id=request.id
      and f.submitted_at=p_submitted_at and f.sha256=p_sha256) then
      raise exception 'Certificate changed during analysis' using errcode='PT409';
    end if;
    return jsonb_build_object('request',to_jsonb(request),'wallet',benchmark_private.oi_pickle_wallet_json(actor),
      'duplicate',request.review_note='duplicate_certificate','credited',false);
  end if;
  if request.status<>'pending' then raise exception 'Certificate request unavailable' using errcode='PT409'; end if;
  -- Composite identity is mandatory for approval. Lock both facts so dropping
  -- a serial number cannot turn the same certificate into another reward.
  for lock_key in select distinct hashtextextended('coin-certificate:'||value,506)
      from unnest(array[p_semantic_digest,p_secondary_digest]) value where value is not null order by 1 loop
    perform pg_advisory_xact_lock(lock_key);
  end loop;
  -- Existing private helper serializes exact and primary semantic matches across accounts.
  perform benchmark_private.oi_register_evidence_fingerprint(request.id,actor,p_object_path,p_submitted_at,p_sha256,p_semantic_digest);
  if p_decision='approved' then
    select exists(select 1 from benchmark_private.oi_coin_certificate_claims
      where evidence_id<>request.id and (sha256=p_sha256
        or (p_secondary_digest is not null and reference_digest=p_secondary_digest)
        or (semantic_digest=p_semantic_digest and (reference_digest is null or p_secondary_digest is null)))) into duplicate;
    if not duplicate then
      insert into benchmark_private.oi_coin_certificate_claims values(request.id,p_sha256,p_semantic_digest,p_secondary_digest) on conflict do nothing;
      if found then
        credited:=benchmark_private.oi_pickle_apply(actor,'certificate:'||request.id::text,'certificate',30);
      else duplicate:=true;
      end if;
    end if;
  end if;
  update public.oi_evidence_requests set
    status=case when duplicate then 'rejected' when p_decision='approved' then 'approved'
      when p_decision='rejected' then 'rejected' else 'changes_requested' end,
    review_note=case when duplicate then 'duplicate_certificate' when p_decision='approved' then 'certificate_verified'
      when p_decision='rejected' then 'certificate_rejected' else 'certificate_needs_review' end,
    reviewed_at=clock_timestamp(),reviewer_id=null where id=request.id returning * into request;
  perform benchmark_private.oi_ensure_pickle_wallet(actor);
  insert into benchmark_private.oi_audit(actor_id,action,target_id)
    values(p_user,'coin_certificate:'||request.status,request.id);
  return jsonb_build_object('request',to_jsonb(request),'wallet',benchmark_private.oi_pickle_wallet_json(actor),
    'duplicate',duplicate,'credited',credited);
end;
$$;

-- Enable the complete feature atomically with balances, evidence, grandfathering and ownership.
do $$ declare definition text:=pg_get_functiondef('public.oi_capabilities()'::regprocedure);
begin
  if definition !~ '''coins_enabled'',\s*false' then raise exception 'Pickle capability drift requires review'; end if;
  definition:=regexp_replace(definition,'''coins_enabled'',\s*false',
    '''coins_enabled'',true,''pickle_coin_evidence'',true,''pickle_farmer_shop'',true');
  execute definition;
end; $$;

revoke all on function benchmark_private.oi_coin_evidence_actor(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.oi_start_coin_evidence(uuid),public.oi_submit_coin_evidence(uuid,text,integer),public.oi_cancel_coin_evidence(uuid) from public,anon,authenticated,service_role;
grant execute on function public.oi_start_coin_evidence(uuid),public.oi_submit_coin_evidence(uuid,text,integer),public.oi_cancel_coin_evidence(uuid) to authenticated;
revoke all on function public.oi_prepare_coin_evidence(uuid,uuid,uuid),
  public.oi_coin_evidence_review(uuid,uuid,uuid,text,timestamptz,text,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.oi_prepare_coin_evidence(uuid,uuid,uuid),
  public.oi_coin_evidence_review(uuid,uuid,uuid,text,timestamptz,text,text,text,text,text) to service_role;

notify pgrst,'reload schema';
commit;
