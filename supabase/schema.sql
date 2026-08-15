create extension if not exists pgcrypto;

create table if not exists public.analysis_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  analyzed_at timestamptz not null default now(),
  category text not null check (category in ('스포츠', '경제', '정치', '연예', '과학')),
  title text not null default '',
  url text not null default '',
  article_text text not null default '',
  char_count integer not null default 0 check (char_count >= 0),
  sentence_count integer not null default 0 check (sentence_count >= 0),
  fact_count integer not null default 0 check (fact_count >= 0),
  opinion_count integer not null default 0 check (opinion_count >= 0),
  quote_count integer not null default 0 check (quote_count >= 0),
  opinion_ratio numeric(5, 3) not null default 0 check (opinion_ratio between 0 and 1),
  vocab_count integer not null default 0 check (vocab_count >= 0),
  engine text not null default '규칙 기반',
  summary jsonb not null default '[]'::jsonb,
  vocab jsonb not null default '[]'::jsonb,
  key_facts jsonb not null default '[]'::jsonb,
  key_opinions jsonb not null default '[]'::jsonb,
  checks jsonb not null default '[]'::jsonb
);

-- 이미 이전 버전의 테이블을 만든 프로젝트에서도 다시 실행할 수 있습니다.
alter table public.analysis_logs add column if not exists article_text text not null default '';
alter table public.analysis_logs add column if not exists vocab jsonb not null default '[]'::jsonb;
alter table public.analysis_logs add column if not exists key_facts jsonb not null default '[]'::jsonb;
alter table public.analysis_logs add column if not exists key_opinions jsonb not null default '[]'::jsonb;
alter table public.analysis_logs add column if not exists checks jsonb not null default '[]'::jsonb;

create index if not exists analysis_logs_user_analyzed_at_idx
  on public.analysis_logs (user_id, analyzed_at desc);

alter table public.analysis_logs enable row level security;

drop policy if exists "Users can read their analysis logs" on public.analysis_logs;
create policy "Users can read their analysis logs"
  on public.analysis_logs for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their analysis logs" on public.analysis_logs;
create policy "Users can insert their analysis logs"
  on public.analysis_logs for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their analysis logs" on public.analysis_logs;
create policy "Users can delete their analysis logs"
  on public.analysis_logs for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.get_analysis_stats()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with visible_logs as (
    select category, opinion_ratio, analyzed_at
    from public.analysis_logs
    where user_id = (select auth.uid())
  ), category_stats as (
    select
      category,
      count(*)::integer as count,
      coalesce(avg(opinion_ratio), 0) as avg_opinion_ratio
    from visible_logs
    group by category
  )
  select jsonb_build_object(
    'total', (select count(*) from visible_logs),
    'avg_opinion_ratio', coalesce((select avg(opinion_ratio) from visible_logs), 0),
    'recent_category', coalesce((select category from visible_logs order by analyzed_at desc limit 1), ''),
    'categories', coalesce((
      select jsonb_object_agg(
        category_stats.category,
        jsonb_build_object(
          'count', category_stats.count,
          'avg_opinion_ratio', category_stats.avg_opinion_ratio
        )
      )
      from category_stats
    ), '{}'::jsonb)
  );
$$;

revoke all on function public.get_analysis_stats() from public;
grant execute on function public.get_analysis_stats() to authenticated;
