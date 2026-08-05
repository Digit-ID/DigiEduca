-- =====================================================================
--  Três estados de disponibilidade por curso
--  Correr uma vez no SQL Editor, depois do schema.sql
--    disponivel    → visível e acessível a todos os colaboradores
--    proximamente  → visível com a marca "Em breve", ainda não acessível
--    oculto        → invisível para os colaboradores, só o admin o vê
-- =====================================================================

alter table public.cursos
  add column if not exists estado text not null default 'disponivel';

alter table public.cursos drop constraint if exists cursos_estado_check;
alter table public.cursos
  add constraint cursos_estado_check check (estado in ('disponivel','proximamente','oculto'));

-- Manter o antigo campo booleano coerente com o novo estado
update public.cursos set estado = case when ativo then 'disponivel' else 'oculto' end;

create or replace function public.sincronizar_ativo()
returns trigger language plpgsql as $$
begin
  new.ativo := (new.estado = 'disponivel');
  return new;
end $$;
drop trigger if exists trg_sincronizar_ativo on public.cursos;
create trigger trg_sincronizar_ativo before insert or update of estado on public.cursos
  for each row execute function public.sincronizar_ativo();

-- Leitura: o colaborador vê tudo menos os cursos ocultos; o admin vê tudo
drop policy if exists cursos_ler on public.cursos;
create policy cursos_ler on public.cursos for select to authenticated
  using (estado <> 'oculto' or public.e_admin());

-- Só os cursos disponíveis contam para a conformidade do AI Act
create or replace view public.vw_conformidade_ai_act with (security_invoker = true) as
select p.id as utilizador_id, p.nome, p.email, p.departamento,
       (select count(*) from public.cursos where obrigatorio and estado = 'disponivel') as obrigatorios_total,
       count(distinct pr.curso_slug) as obrigatorios_concluidos,
       (count(distinct pr.curso_slug) >= (select count(*) from public.cursos where obrigatorio and estado = 'disponivel')) as conforme,
       max(cert.emitido_em) as ultimo_certificado
from public.perfis p
left join public.cursos cu on cu.obrigatorio and cu.estado = 'disponivel'
left join public.progresso pr on pr.utilizador_id = p.id and pr.curso_slug = cu.slug and pr.estado = 'concluido'
left join public.certificados cert on cert.utilizador_id = p.id and cert.curso_slug = cu.slug and cert.valido
where p.papel = 'colaborador'
group by p.id, p.nome, p.email, p.departamento;

-- Confirmação
select estado, count(*) from public.cursos group by estado order by estado;
