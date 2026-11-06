-- 새 Supabase 프로젝트의 SQL Editor에서 실행하세요.
-- 기존 tasks 테이블이 있는 프로젝트에는 구조 확인 없이 실행하지 마세요.
begin;
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  title text not null check (length(btrim(title)) between 1 and 150),
  description text not null default '' check (length(description) <= 5000),
  status text not null default 'todo' check (status in ('todo','doing','done')),
  priority text not null default 'medium' check (priority in ('low','medium','high')),
  due date check (due between date '1900-01-01' and date '9999-12-31'),
  created bigint not null default ((extract(epoch from now())*1000)::bigint),
  updated_at timestamptz not null default now()
);
create index tasks_user_created_idx on public.tasks(user_id,created desc);
alter table public.tasks enable row level security;
revoke all on public.tasks from anon;
grant select,insert,update,delete on public.tasks to authenticated;
create policy tasks_select_own on public.tasks for select to authenticated using ((select auth.uid())=user_id);
create policy tasks_insert_own on public.tasks for insert to authenticated with check ((select auth.uid())=user_id);
create policy tasks_update_own on public.tasks for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create policy tasks_delete_own on public.tasks for delete to authenticated using ((select auth.uid())=user_id);
create function public.touch_task_updated_at() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at=now(); return new; end;
$$;
create trigger tasks_updated_at before update on public.tasks for each row execute function public.touch_task_updated_at();

-- 백업 복원은 트랜잭션에서 일괄 교체합니다.
-- SECURITY INVOKER: 호출 사용자의 RLS를 적용하며 관리자 권한을 사용하지 않습니다.
create function public.replace_my_tasks(items jsonb) returns void
language plpgsql security invoker set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(items) is distinct from 'array' then raise exception 'Expected array'; end if;
  delete from public.tasks where user_id=auth.uid();
  insert into public.tasks (id,user_id,title,description,status,priority,due,created)
  select x.id,auth.uid(),x.title,x.description,x.status,x.priority,nullif(x.due,'')::date,x.created
  from jsonb_to_recordset(items) as x(id uuid,title text,description text,status text,priority text,due text,created bigint);
end;
$$;
revoke all on function public.replace_my_tasks(jsonb) from public,anon;
grant execute on function public.replace_my_tasks(jsonb) to authenticated;
commit;
