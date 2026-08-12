-- DigiEduca v2: avaliações de cursos, atribuições com prazo, ranking de departamentos
-- Correr no SQL Editor do Supabase depois de schema.sql

create table if not exists public.avaliacoes_cursos (
  id uuid primary key default gen_random_uuid(),
  utilizador_id uuid not null references public.perfis(id) on delete cascade,
  curso_slug text not null,
  estrelas int not null check (estrelas between 1 and 5),
  comentario text,
  criado_em timestamptz not null default now(),
  unique (utilizador_id, curso_slug)
);
alter table public.avaliacoes_cursos enable row level security;
drop policy if exists "avaliacoes ler" on public.avaliacoes_cursos;
create policy "avaliacoes ler" on public.avaliacoes_cursos for select to authenticated using (true);
drop policy if exists "avaliacoes criar" on public.avaliacoes_cursos;
create policy "avaliacoes criar" on public.avaliacoes_cursos for insert to authenticated with check (utilizador_id = auth.uid());
drop policy if exists "avaliacoes editar" on public.avaliacoes_cursos;
create policy "avaliacoes editar" on public.avaliacoes_cursos for update to authenticated using (utilizador_id = auth.uid());

create table if not exists public.atribuicoes (
  id uuid primary key default gen_random_uuid(),
  utilizador_id uuid not null references public.perfis(id) on delete cascade,
  curso_slug text not null,
  prazo date,
  criado_em timestamptz not null default now()
);
alter table public.atribuicoes enable row level security;
drop policy if exists "atribuicoes ler" on public.atribuicoes;
create policy "atribuicoes ler" on public.atribuicoes for select to authenticated
  using (utilizador_id = auth.uid() or exists (select 1 from public.perfis where id = auth.uid() and papel = 'admin'));
drop policy if exists "atribuicoes criar" on public.atribuicoes;
create policy "atribuicoes criar" on public.atribuicoes for insert to authenticated
  with check (utilizador_id = auth.uid() or exists (select 1 from public.perfis where id = auth.uid() and papel = 'admin'));
drop policy if exists "atribuicoes apagar" on public.atribuicoes;
create policy "atribuicoes apagar" on public.atribuicoes for delete to authenticated
  using (exists (select 1 from public.perfis where id = auth.uid() and papel = 'admin'));

-- Ranking agregado (a vista corre com os direitos do dono e ignora RLS — expõe só totais por departamento)
create or replace view public.ranking_departamentos as
  select p.departamento,
         count(distinct p.id) as colaboradores,
         count(pr.*) filter (where pr.estado = 'concluido') as conclusoes
  from public.perfis p
  left join public.progresso pr on pr.utilizador_id = p.id
  where p.papel = 'colaborador' and coalesce(p.ativo, true)
  group by p.departamento;
grant select on public.ranking_departamentos to authenticated;
