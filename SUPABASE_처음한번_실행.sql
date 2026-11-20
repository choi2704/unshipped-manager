-- Supabase Dashboard > SQL Editor > New query > 붙여넣기 > Run
-- 새 Supabase 프로젝트에서 단 한 번 실행하세요.
-- 관리자 등록은 이 스크립트 실행 후 별도 승인 쿼리로 진행합니다.

create extension if not exists pgcrypto;

create table if not exists public.members (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  approved boolean not null default false,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.new_member()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.members(id,email,approved,is_admin)
  values(new.id,coalesce(new.email,''),false,false)
  on conflict(id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_app on auth.users;
create trigger on_auth_user_created_app after insert on auth.users
for each row execute function public.new_member();

create or replace function public.is_active_member()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.members where id = (select auth.uid()) and approved = true);
$$;
create or replace function public.is_app_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.members where id = (select auth.uid()) and approved = true and is_admin = true);
$$;
revoke all on function public.is_active_member() from public;
revoke all on function public.is_app_admin() from public;
grant execute on function public.is_active_member(),public.is_app_admin() to authenticated;

create table if not exists public.work_items (
  id uuid primary key default gen_random_uuid(),
  kind text not null check(kind in ('out','return')),
  payload jsonb not null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id)
);

create table if not exists public.work_logs (
  id bigint generated always as identity primary key,
  item_id uuid not null,
  kind text not null,
  action text not null,
  old_payload jsonb,
  new_payload jsonb,
  actor_id uuid,
  changed_at timestamptz not null default now()
);

create or replace function public.stamp_work_item()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := (select auth.uid());
    new.updated_by := (select auth.uid());
    new.version := 1;
    new.created_at := now();
    new.updated_at := now();
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.kind := old.kind;
    new.version := old.version + 1;
    new.updated_by := (select auth.uid());
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_stamp_work_item on public.work_items;
create trigger trg_stamp_work_item before insert or update on public.work_items
for each row execute function public.stamp_work_item();

create or replace function public.audit_work_item()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    insert into public.work_logs(item_id,kind,action,old_payload,actor_id)
    values(old.id,old.kind,tg_op,old.payload,(select auth.uid()));
    return old;
  elsif tg_op = 'INSERT' then
    insert into public.work_logs(item_id,kind,action,new_payload,actor_id)
    values(new.id,new.kind,tg_op,new.payload,(select auth.uid()));
    return new;
  else
    insert into public.work_logs(item_id,kind,action,old_payload,new_payload,actor_id)
    values(new.id,new.kind,tg_op,old.payload,new.payload,(select auth.uid()));
    return new;
  end if;
end;
$$;

drop trigger if exists trg_audit_work_item on public.work_items;
create trigger trg_audit_work_item after insert or update or delete on public.work_items
for each row execute function public.audit_work_item();

alter table public.members enable row level security;
alter table public.work_items enable row level security;
alter table public.work_logs enable row level security;

-- 첫 설치를 다시 실행해도 정책 중복 오류가 나지 않도록 처리
 drop policy if exists "members read" on public.members;
create policy "members read" on public.members for select to authenticated
using ((select auth.uid())=id or (select public.is_app_admin()));
drop policy if exists "admin approves members" on public.members;
create policy "admin approves members" on public.members for update to authenticated
using ((select public.is_app_admin())) with check ((select public.is_app_admin()));

drop policy if exists "active member read items" on public.work_items;
create policy "active member read items" on public.work_items for select to authenticated
using ((select public.is_active_member()));
drop policy if exists "active member insert items" on public.work_items;
create policy "active member insert items" on public.work_items for insert to authenticated
with check ((select public.is_active_member()));
drop policy if exists "active member update items" on public.work_items;
create policy "active member update items" on public.work_items for update to authenticated
using ((select public.is_active_member())) with check ((select public.is_active_member()));
drop policy if exists "active member delete items" on public.work_items;
create policy "active member delete items" on public.work_items for delete to authenticated
using ((select public.is_active_member()));

drop policy if exists "active member read audit" on public.work_logs;
create policy "active member read audit" on public.work_logs for select to authenticated
using ((select public.is_active_member()));

revoke all on public.members,public.work_items,public.work_logs from anon;
grant select,update on public.members to authenticated;
grant select,insert,update,delete on public.work_items to authenticated;
grant select on public.work_logs to authenticated;

-- PostgreSQL Realtime: 테이블이 아직 등록되지 않은 경우만 추가
DO $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='work_items') then
    alter publication supabase_realtime add table public.work_items;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='work_logs') then
    alter publication supabase_realtime add table public.work_logs;
  end if;
END $$;

-- 기존에 가입한 유저가 있다면 members 행 생성(승인 전 상태 유지)
insert into public.members(id,email)
select id,coalesce(email,'') from auth.users
on conflict (id) do nothing;
