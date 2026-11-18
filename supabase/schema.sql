-- 새 Supabase 프로젝트의 SQL Editor에서 한 번 실행하세요.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 email text not null,
 display_name text not null default '',
 department text not null default '미지정',
 role text not null default 'staff' check (role in ('staff','admin')),
 approved boolean not null default false,
 created_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles (id,email,display_name) values (new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'display_name',''));
 return new;
end;$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_approved() returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and approved=true)
$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and approved=true and role='admin')
$$;

create table if not exists public.cases (
 id uuid primary key default gen_random_uuid(),
 order_number text not null,
 customer_name text not null,
 seller text not null default '',
 product_name text not null,
 option_name text not null default '',
 quantity int not null default 1 check(quantity>0),
 original_tracking text not null,
 current_tracking text not null default '',
 carrier text not null default '',
 issue_reason text not null default '재고 부족',
 department text not null default '물류팀',
 assignee text not null default '',
 status text not null default 'pending' check(status in ('pending','restocked','shipping','shipped','canceled')),
 order_date date,
 expected_restock_date date,
 restocked_at date,
 shipped_at date,
 cs_notified boolean not null default false,
 sales_channel_checked boolean not null default false,
 notes text not null default '',
 created_by uuid not null references auth.users(id),
 updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint shipment_requires_date_tracking check (status <> 'shipped' or (shipped_at is not null and length(trim(coalesce(nullif(current_tracking,''),original_tracking)))>0))
);
create index if not exists cases_created_at_idx on public.cases(created_at desc);
create index if not exists cases_status_idx on public.cases(status);
create index if not exists cases_order_number_idx on public.cases(order_number);

create table if not exists public.case_events (
 id bigint generated always as identity primary key,
 case_id uuid not null references public.cases(id) on delete cascade,
 actor_id uuid references auth.users(id),
 action text not null,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists case_events_case_idx on public.case_events(case_id,created_at desc);

create or replace function public.case_audit() returns trigger language plpgsql security definer set search_path = '' as $$
declare changes jsonb := '{}'::jsonb; k text; before_value jsonb; after_value jsonb;
begin
 if tg_op='INSERT' then
  insert into public.case_events(case_id,actor_id,action,details) values(new.id,auth.uid(),'created',jsonb_build_object('order_number',new.order_number,'status',new.status));
  return new;
 end if;
 if tg_op='UPDATE' then
  for k in select jsonb_object_keys(to_jsonb(new)) loop
   if k not in ('updated_at','updated_by') then
    before_value:=to_jsonb(old)->k; after_value:=to_jsonb(new)->k;
    if before_value is distinct from after_value then
     changes:=changes||jsonb_build_object(k,jsonb_build_object('from',before_value,'to',after_value));
    end if;
   end if;
  end loop;
  if changes <> '{}'::jsonb then
   insert into public.case_events(case_id,actor_id,action,details) values(new.id,auth.uid(),'updated',changes);
  end if;
  return new;
 end if;
 return null;
end;$$;
drop trigger if exists case_audit_trigger on public.cases;
create trigger case_audit_trigger after insert or update on public.cases for each row execute function public.case_audit();

create or replace function public.case_timestamp() returns trigger language plpgsql as $$
begin
 new.updated_at=now(); new.updated_by=auth.uid();
 if tg_op='INSERT' then new.created_by=auth.uid(); end if;
 return new;
end;$$;
drop trigger if exists case_timestamp_trigger on public.cases;
create trigger case_timestamp_trigger before insert or update on public.cases for each row execute function public.case_timestamp();

alter table public.profiles enable row level security;
alter table public.cases enable row level security;
alter table public.case_events enable row level security;

-- 정책을 반복 실행해도 오류가 나지 않도록 초기화
 drop policy if exists profiles_self_read on public.profiles;
 drop policy if exists profiles_admin_read on public.profiles;
 drop policy if exists profiles_admin_update on public.profiles;
 drop policy if exists cases_read on public.cases;
 drop policy if exists cases_insert on public.cases;
 drop policy if exists cases_update on public.cases;
 drop policy if exists cases_delete on public.cases;
 drop policy if exists case_events_read on public.case_events;

create policy profiles_self_read on public.profiles for select to authenticated using(id=(select auth.uid()));
create policy profiles_admin_read on public.profiles for select to authenticated using(public.is_admin());
create policy profiles_admin_update on public.profiles for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy cases_read on public.cases for select to authenticated using(public.is_approved());
create policy cases_insert on public.cases for insert to authenticated with check(public.is_approved() and created_by=(select auth.uid()));
create policy cases_update on public.cases for update to authenticated using(public.is_approved()) with check(public.is_approved());
create policy cases_delete on public.cases for delete to authenticated using(public.is_admin());
create policy case_events_read on public.case_events for select to authenticated using(public.is_approved());
-- 이벤트는 DB 트리거만 작성, 사용자가 직접 수정/삭제할 수 없습니다.

revoke all on public.case_events from anon;
revoke insert,update,delete on public.case_events from authenticated;
grant select on public.case_events to authenticated;

-- 첫 관리자 계정은 Auth > Users에서 회원가입된 이메일을 확인한 다음,
-- 아래 SQL의 이메일을 바꾸어 SQL Editor에서 수동으로 한 번 승인하세요.
-- update public.profiles set role='admin',approved=true,department='관리자'
-- where email='admin@example.com';


-- 반송예정 관리 테이블 (새 프로젝트에 포함하거나 기존 프로젝트에 추가 실행 가능)
create table if not exists public.returns (
 id uuid primary key default gen_random_uuid(),
 order_number text not null,
 customer_name text not null,
 seller text not null default '',
 product_name text not null,
 option_name text not null default '',
 quantity integer not null default 1 check (quantity > 0),
 received_at date,
 inspection_reason text not null default '사용 흔적',
 inspection_notes text not null default '',
 customer_notified boolean not null default false,
 notified_at date,
 return_due_date date,
 shipped_at date,
 carrier text not null default '',
 return_tracking text not null default '',
 department text not null default '물류팀',
 assignee text not null default '',
 status text not null default 'awaiting_review' check (status in ('awaiting_review','return_planned','return_shipping','return_shipped','canceled')),
 notes text not null default '',
 created_by uuid not null references auth.users(id),
 updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint return_shipping_must_have_details check (status <> 'return_shipped' or (shipped_at is not null and length(trim(return_tracking)) > 0))
);
create index if not exists returns_status_idx on public.returns(status);
create index if not exists returns_created_idx on public.returns(created_at desc);
create index if not exists returns_order_idx on public.returns(order_number);

create table if not exists public.return_events (
 id bigint generated always as identity primary key,
 return_id uuid not null references public.returns(id) on delete cascade,
 actor_id uuid references auth.users(id),
 action text not null,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists return_events_parent_idx on public.return_events(return_id,created_at desc);

create or replace function public.return_timestamp() returns trigger language plpgsql set search_path = '' as $$
begin
 new.updated_at=now(); new.updated_by=auth.uid();
 if tg_op='INSERT' then new.created_by=auth.uid(); end if;
 return new;
end;$$;
drop trigger if exists return_timestamp_trigger on public.returns;
create trigger return_timestamp_trigger before insert or update on public.returns for each row execute function public.return_timestamp();

create or replace function public.return_audit() returns trigger language plpgsql security definer set search_path = '' as $$
declare changes jsonb := '{}'::jsonb; k text; before_value jsonb; after_value jsonb;
begin
 if tg_op='INSERT' then
   insert into public.return_events(return_id,actor_id,action,details)
   values(new.id,auth.uid(),'created',jsonb_build_object('order_number',new.order_number,'status',new.status));
   return new;
 elsif tg_op='UPDATE' then
   for k in select jsonb_object_keys(to_jsonb(new)) loop
     if k not in ('updated_at','updated_by') then
       before_value:=to_jsonb(old)->k; after_value:=to_jsonb(new)->k;
       if before_value is distinct from after_value then
         changes:=changes||jsonb_build_object(k,jsonb_build_object('from',before_value,'to',after_value));
       end if;
     end if;
   end loop;
   if changes <> '{}'::jsonb then
     insert into public.return_events(return_id,actor_id,action,details)
     values(new.id,auth.uid(),'updated',changes);
   end if;
   return new;
 end if;
 return null;
end;$$;
drop trigger if exists return_audit_trigger on public.returns;
create trigger return_audit_trigger after insert or update on public.returns for each row execute function public.return_audit();

alter table public.returns enable row level security;
alter table public.return_events enable row level security;
drop policy if exists returns_read on public.returns;
drop policy if exists returns_insert on public.returns;
drop policy if exists returns_update on public.returns;
drop policy if exists returns_delete on public.returns;
drop policy if exists return_events_read on public.return_events;
create policy returns_read on public.returns for select to authenticated using (public.is_approved());
create policy returns_insert on public.returns for insert to authenticated with check (public.is_approved() and created_by=(select auth.uid()));
create policy returns_update on public.returns for update to authenticated using (public.is_approved()) with check (public.is_approved());
create policy returns_delete on public.returns for delete to authenticated using (public.is_admin());
create policy return_events_read on public.return_events for select to authenticated using (public.is_approved());
revoke all on public.return_events from anon;
revoke insert, update, delete on public.return_events from authenticated;
grant select on public.return_events to authenticated;
