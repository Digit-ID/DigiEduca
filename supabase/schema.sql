-- =====================================================================
--  Portal de Formação Digit — esquema Supabase
--  Executar no SQL Editor do projeto Supabase (uma única vez, de cima a baixo).
--  Português europeu. Base de dados: PostgreSQL 15+ / Supabase.
-- =====================================================================

-- ---------- 0. Extensões -------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------- 1. Perfis (1:1 com auth.users) -------------------------------
create table if not exists public.perfis (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text not null unique,
  nome          text not null,
  departamento  text,
  papel         text not null default 'colaborador' check (papel in ('colaborador','admin')),
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now()
);

-- Só emails @digit.com.pt podem registar-se + criação automática do perfil
create or replace function public.tratar_novo_utilizador()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.email not ilike '%@digit.com.pt' then
    raise exception 'Apenas endereços @digit.com.pt podem registar-se no portal.';
  end if;
  insert into public.perfis (id, email, nome, departamento)
  values (
    new.id,
    lower(new.email),
    coalesce(new.raw_user_meta_data->>'nome', split_part(new.email,'@',1)),
    new.raw_user_meta_data->>'departamento'
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists trg_novo_utilizador on auth.users;
create trigger trg_novo_utilizador
  after insert on auth.users
  for each row execute function public.tratar_novo_utilizador();

-- Auxiliar: o utilizador atual é admin?
create or replace function public.e_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis where id = auth.uid() and papel = 'admin');
$$;

-- ---------- 2. Catálogo ---------------------------------------------------
create table if not exists public.areas (
  nome   text primary key,
  icone  text,
  ordem  int not null default 0
);

create table if not exists public.cursos (
  slug         text primary key,
  titulo       text not null,
  descricao    text,
  area         text not null references public.areas(nome) on update cascade,
  icone        text,
  ficheiro     text not null,
  nivel        text,
  modulos      int not null default 5,
  duracao_min  int not null default 10,
  ativo        boolean not null default true,   -- o admin liga/desliga aqui
  obrigatorio  boolean not null default false,  -- conta para o Art. 4.º do AI Act
  ordem        int not null default 0,
  criado_em    timestamptz not null default now()
);

-- ---------- 3. Progresso, avaliações e certificados ----------------------
create table if not exists public.progresso (
  id            uuid primary key default gen_random_uuid(),
  utilizador_id uuid not null references public.perfis(id) on delete cascade,
  curso_slug    text not null references public.cursos(slug) on delete cascade,
  modulo_atual  int  not null default 1,
  modulos_feitos int[] not null default '{}',
  estado        text not null default 'em_curso' check (estado in ('em_curso','concluido')),
  iniciado_em   timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (utilizador_id, curso_slug)
);

create table if not exists public.respostas_quiz (
  id            uuid primary key default gen_random_uuid(),
  utilizador_id uuid not null references public.perfis(id) on delete cascade,
  curso_slug    text not null references public.cursos(slug) on delete cascade,
  modulo        int not null,
  pergunta      int not null,
  resposta      int,
  correta       boolean not null default false,
  respondido_em timestamptz not null default now()
);

create table if not exists public.avaliacoes (
  id            uuid primary key default gen_random_uuid(),
  utilizador_id uuid not null references public.perfis(id) on delete cascade,
  curso_slug    text not null references public.cursos(slug) on delete cascade,
  nota          int not null,
  total         int not null default 10,
  percentagem   int generated always as (round(nota::numeric * 100 / greatest(total,1))) stored,
  aprovado      boolean not null default false,
  tentativa     int not null default 1,
  submetido_em  timestamptz not null default now()
);

create table if not exists public.certificados (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique,
  utilizador_id  uuid not null references public.perfis(id) on delete cascade,
  curso_slug     text not null references public.cursos(slug) on delete cascade,
  nome_certificado text not null,
  nota           int,
  total          int default 10,
  emitido_em     timestamptz not null default now(),
  valido         boolean not null default true
);
create index if not exists idx_cert_utilizador on public.certificados(utilizador_id);

-- Código legível do certificado: DIGIT-2026-A1B2C3
create or replace function public.gerar_codigo_certificado()
returns trigger language plpgsql as $$
begin
  if new.codigo is null or new.codigo = '' then
    new.codigo := 'DIGIT-' || to_char(now(),'YYYY') || '-' || upper(substr(md5(gen_random_uuid()::text),1,6));
  end if;
  return new;
end $$;
drop trigger if exists trg_codigo_certificado on public.certificados;
create trigger trg_codigo_certificado before insert on public.certificados
  for each row execute function public.gerar_codigo_certificado();

-- ---------- 4. Trilha de auditoria (Art. 4.º do AI Act) ------------------
create table if not exists public.auditoria (
  id            bigserial primary key,
  utilizador_id uuid references public.perfis(id) on delete set null,
  email         text,
  acao          text not null,
  entidade      text,
  detalhe       jsonb,
  criado_em     timestamptz not null default now()
);
create index if not exists idx_auditoria_data on public.auditoria(criado_em desc);

create or replace function public.registar_auditoria(p_acao text, p_entidade text, p_detalhe jsonb default '{}')
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.auditoria (utilizador_id, email, acao, entidade, detalhe)
  values (auth.uid(), (select email from public.perfis where id = auth.uid()), p_acao, p_entidade, p_detalhe);
end $$;

-- ---------- 5. Vistas para o painel de administração ---------------------
create or replace view public.vw_progresso_colaborador with (security_invoker = true) as
select p.id as utilizador_id, p.nome, p.email, p.departamento, p.papel,
       count(distinct pr.curso_slug) filter (where pr.estado = 'concluido') as cursos_concluidos,
       count(distinct pr.curso_slug) filter (where pr.estado = 'em_curso')  as cursos_em_curso,
       count(distinct c.id) as certificados,
       max(greatest(pr.atualizado_em, coalesce(c.emitido_em, pr.atualizado_em))) as ultima_atividade
from public.perfis p
left join public.progresso pr on pr.utilizador_id = p.id
left join public.certificados c on c.utilizador_id = p.id and c.valido
group by p.id, p.nome, p.email, p.departamento, p.papel;

-- Conformidade: cursos obrigatórios concluídos por colaborador
create or replace view public.vw_conformidade_ai_act with (security_invoker = true) as
select p.id as utilizador_id, p.nome, p.email, p.departamento,
       (select count(*) from public.cursos where obrigatorio and ativo) as obrigatorios_total,
       count(distinct pr.curso_slug) as obrigatorios_concluidos,
       (count(distinct pr.curso_slug) >= (select count(*) from public.cursos where obrigatorio and ativo)) as conforme,
       max(cert.emitido_em) as ultimo_certificado
from public.perfis p
left join public.cursos cu on cu.obrigatorio and cu.ativo
left join public.progresso pr on pr.utilizador_id = p.id and pr.curso_slug = cu.slug and pr.estado = 'concluido'
left join public.certificados cert on cert.utilizador_id = p.id and cert.curso_slug = cu.slug and cert.valido
where p.papel = 'colaborador'
group by p.id, p.nome, p.email, p.departamento;

-- ---------- 6. Segurança (RLS) -------------------------------------------
alter table public.perfis         enable row level security;
alter table public.cursos         enable row level security;
alter table public.areas          enable row level security;
alter table public.progresso      enable row level security;
alter table public.respostas_quiz enable row level security;
alter table public.avaliacoes     enable row level security;
alter table public.certificados   enable row level security;
alter table public.auditoria      enable row level security;

-- Catálogo: qualquer utilizador autenticado lê; só o admin escreve
drop policy if exists areas_ler on public.areas;
create policy areas_ler on public.areas for select to authenticated using (true);
drop policy if exists areas_admin on public.areas;
create policy areas_admin on public.areas for all to authenticated using (public.e_admin()) with check (public.e_admin());

drop policy if exists cursos_ler on public.cursos;
create policy cursos_ler on public.cursos for select to authenticated using (ativo or public.e_admin());
drop policy if exists cursos_admin on public.cursos;
create policy cursos_admin on public.cursos for all to authenticated using (public.e_admin()) with check (public.e_admin());

-- Perfis: cada um vê e edita o seu; o admin vê e gere todos
drop policy if exists perfis_proprio on public.perfis;
create policy perfis_proprio on public.perfis for select to authenticated using (id = auth.uid() or public.e_admin());
drop policy if exists perfis_editar_proprio on public.perfis;
create policy perfis_editar_proprio on public.perfis for update to authenticated using (id = auth.uid() or public.e_admin()) with check (id = auth.uid() or public.e_admin());
drop policy if exists perfis_admin on public.perfis;
create policy perfis_admin on public.perfis for delete to authenticated using (public.e_admin());

-- Dados de formação: cada um só toca nos seus registos; o admin lê tudo
do $$
declare t text;
begin
  foreach t in array array['progresso','respostas_quiz','avaliacoes','certificados'] loop
    execute format('drop policy if exists %I_proprio on public.%I', t, t);
    execute format('create policy %I_proprio on public.%I for select to authenticated using (utilizador_id = auth.uid() or public.e_admin())', t, t);
    execute format('drop policy if exists %I_inserir on public.%I', t, t);
    execute format('create policy %I_inserir on public.%I for insert to authenticated with check (utilizador_id = auth.uid() or public.e_admin())', t, t);
    execute format('drop policy if exists %I_atualizar on public.%I', t, t);
    execute format('create policy %I_atualizar on public.%I for update to authenticated using (utilizador_id = auth.uid() or public.e_admin()) with check (utilizador_id = auth.uid() or public.e_admin())', t, t);
    execute format('drop policy if exists %I_apagar on public.%I', t, t);
    execute format('create policy %I_apagar on public.%I for delete to authenticated using (public.e_admin())', t, t);
  end loop;
end $$;

-- Auditoria: escrita por qualquer autenticado, leitura só do admin (não se apaga)
drop policy if exists auditoria_inserir on public.auditoria;
create policy auditoria_inserir on public.auditoria for insert to authenticated with check (utilizador_id = auth.uid());
drop policy if exists auditoria_ler on public.auditoria;
create policy auditoria_ler on public.auditoria for select to authenticated using (public.e_admin());

-- ---------- 7. Catálogo inicial (6 áreas, 30 cursos) ---------------------
insert into public.areas (nome, icone, ordem) values
  ('Excel & Ferramentas', '📊', 1),
  ('Fiscal & Contabilidade', '🧾', 2),
  ('Recursos Humanos', '👥', 3),
  ('Compliance & Legal', '⚖️', 4),
  ('Soft Skills', '💬', 5),
  ('Inovação', '🤖', 6)
on conflict (nome) do update set icone = excluded.icone, ordem = excluded.ordem;

insert into public.cursos (slug, titulo, descricao, area, icone, ficheiro, nivel, modulos, duracao_min, ativo, obrigatorio, ordem) values
  ('excel-para-iniciantes', 'Excel para Iniciantes', 'Aprende a usar o Microsoft Excel do zero — interface, formatação de dados, fórmulas essenciais (SOMA, MÉDIA), filtros, gráficos e os atalhos que aumentam a tua produtividade.', 'Excel & Ferramentas', '📊', 'Digit-Curso_Excel_para_Iniciantes.html', 'Recomendado', 5, 10, true, false, 1),
  ('excel-intermedio', 'Excel Intermédio', 'Dá o próximo passo: funções lógicas (SE, E, OU), PROCV e PROCX, formatação condicional, validação de dados e tabelas dinâmicas — as ferramentas que transformam dados em decisões.', 'Excel & Ferramentas', '📈', 'Digit-Curso_Excel_Intermedio.html', 'Recomendado', 5, 10, true, false, 2),
  ('excel-avancado', 'Excel Avançado', 'Domina o Excel ao nível profissional. Fórmulas matriciais dinâmicas, ÍNDICE+CORRESP, Power Query, dashboards interativos e introdução a macros (VBA).', 'Excel & Ferramentas', '💼', 'Digit-Curso_Excel_Avançado.html', 'Avançado', 5, 10, true, false, 3),
  ('power-bi', 'Power BI — relatórios e dashboards', 'Aprende a criar dashboards interativos e relatórios visuais com o Power BI — a ferramenta de business intelligence da Microsoft.', 'Excel & Ferramentas', '📊', 'Digit-Curso_Power_BI.html', NULL, 5, 10, true, false, 4),
  ('microsoft-365', 'Microsoft 365 — Dicas e Produtividade', 'Tira o máximo partido do Teams, Outlook, OneDrive e SharePoint no teu dia a dia na Digit.', 'Excel & Ferramentas', '💻', 'Digit-Curso_Microsoft_365.html', NULL, 5, 10, true, false, 5),
  ('power-automate', 'Introdução ao Power Automate', 'Automatiza tarefas repetitivas com o Power Automate — desde aprovações a notificações automáticas, sem código.', 'Excel & Ferramentas', '⚡', 'Digit-Curso_Power_Automate.html', NULL, 5, 10, true, false, 6),
  ('iva', 'IVA na prática', 'Compreende o funcionamento do IVA em Portugal — taxas, isenções, declarações e casos práticos da consultoria financeira.', 'Fiscal & Contabilidade', '📋', 'Digit-Curso_IVA.html', NULL, 5, 10, true, false, 7),
  ('irc', 'IRC e obrigações declarativas', 'Os fundamentos do Imposto sobre o Rendimento das Pessoas Coletivas aplicados ao contexto da Digit e dos seus clientes.', 'Fiscal & Contabilidade', '🏢', 'Digit-Curso_IRC.html', NULL, 5, 10, true, false, 8),
  ('encerramento-contas', 'Encerramento de contas', 'Procedimentos, prazos e boas práticas para o encerramento de contas anual — do balancete ao depósito das contas.', 'Fiscal & Contabilidade', '📅', 'Digit-Curso_Encerramento_Contas.html', NULL, 5, 10, true, false, 9),
  ('calendario-fiscal', 'Calendário fiscal — prazos e coimas', 'As obrigações fiscais mensais e anuais da Digit, os seus prazos e como nunca falhar uma data. Coimas, juros e métodos práticos para manter tudo em dia.', 'Fiscal & Contabilidade', '📅', 'Digit-Curso_Calendario_Fiscal.html', NULL, 5, 10, true, false, 10),
  ('irs', 'IRS — Processamento e Entregas', 'Tudo o que precisas de saber sobre o processamento de IRS, prazos, declarações e casos especiais.', 'Fiscal & Contabilidade', '🧾', 'Digit-Curso_IRS.html', NULL, 5, 10, true, false, 11),
  ('contabilidade-nao-contabilistas', 'Contabilidade para Não Contabilistas', 'Os conceitos essenciais de contabilidade explicados de forma simples para colaboradores de outras áreas da Digit.', 'Fiscal & Contabilidade', '📚', 'Digit-Curso_Contabilidade_Nao_Contabilistas.html', NULL, 5, 10, true, false, 12),
  ('id-fiscal', 'Noções de I&D Fiscal', 'Os incentivos fiscais à Investigação e Desenvolvimento em Portugal — SIFIDE, elegibilidade e como identificar projetos qualificáveis.', 'Fiscal & Contabilidade', '🔬', 'Digit-Curso_ID_Fiscal.html', NULL, 5, 10, true, false, 13),
  ('processamento-salarial', 'Processamento salarial', 'Os conceitos base do processamento de salários em Portugal — remunerações, deduções, subsídios e contribuições.', 'Recursos Humanos', '💼', 'Digit-Curso_Processamento_Salarial.html', NULL, 5, 10, true, false, 14),
  ('contratos-trabalho', 'Contratos de trabalho', 'Os tipos de contrato, os elementos essenciais e as regras práticas. Inclui o salário mínimo de 2026 e a remuneração de gerentes e administradores (IAS).', 'Recursos Humanos', '📝', 'Digit-Curso_Contratos_Trabalho.html', NULL, 5, 10, true, false, 15),
  ('ferias-faltas-licencas', 'Férias, faltas e licenças', 'Regras do Código do Trabalho sobre férias, faltas justificadas e injustificadas, e como gerir corretamente os registos.', 'Recursos Humanos', '🏖️', 'Digit-Curso_Ferias_Faltas_Licencas.html', NULL, 5, 10, true, false, 16),
  ('admissoes-cessacoes', 'Admissões e cessações', 'Procedimentos legais e administrativos nas admissões, renovações e cessações de contratos de trabalho.', 'Recursos Humanos', '📝', 'Digit-Curso_Admissoes_Cessacoes.html', NULL, 5, 10, true, false, 17),
  ('subsidios-beneficios', 'Subsídios e Benefícios — O que deves saber', 'Subsídio de alimentação, transporte, saúde e outros benefícios — regras, limites fiscais e como processar corretamente.', 'Recursos Humanos', '🎁', 'Digit-Curso_Subsidios_Beneficios.html', NULL, 5, 10, true, false, 18),
  ('rgpd', 'RGPD no dia a dia', 'Proteção de dados pessoais no contexto da consultoria financeira — o que podes e não podes fazer com dados de clientes.', 'Compliance & Legal', '📑', 'Digit-Curso_RGPD.html', NULL, 5, 10, true, true, 19),
  ('branqueamento-capitais', 'Prevenção do branqueamento de capitais', 'Obrigações legais de prevenção do branqueamento de capitais e financiamento do terrorismo aplicadas à consultoria financeira.', 'Compliance & Legal', '🛡️', 'Digit-Curso_Branqueamento_Capitais.html', NULL, 5, 10, true, true, 20),
  ('sigilo-etica', 'Sigilo profissional e ética', 'Os valores, princípios e regras de conduta que orientam o trabalho de todos os colaboradores da Digit.', 'Compliance & Legal', '📜', 'Digit-Curso_Sigilo_Etica.html', NULL, 5, 10, true, true, 21),
  ('seguranca-informacao', 'Segurança da Informação', 'Boas práticas de cibersegurança, proteção de dados e uso seguro dos sistemas de informação na Digit.', 'Compliance & Legal', '🔐', 'Digit-Curso_Seguranca_Informacao.html', NULL, 5, 10, true, true, 22),
  ('comunicacao-cliente', 'Comunicação com o cliente', 'Técnicas de comunicação eficaz com clientes — presencial, por email e em reuniões — no contexto da consultoria.', 'Soft Skills', '🗣️', 'Digit-Curso_Comunicacao_Cliente.html', NULL, 5, 10, true, false, 23),
  ('gestao-tempo', 'Gestão de tempo e prioridades', 'Métodos e ferramentas para gerir melhor o tempo, priorizar tarefas e aumentar a produtividade no trabalho.', 'Soft Skills', '⏱️', 'Digit-Curso_Gestao_Tempo.html', NULL, 5, 10, true, false, 24),
  ('reunioes-emails', 'Reuniões e e-mails eficazes', 'Como preparar, conduzir e concluir reuniões produtivas — presenciais e remotas — poupando tempo a toda a equipa.', 'Soft Skills', '🤝', 'Digit-Curso_Reunioes_Emails.html', NULL, 5, 10, true, false, 25),
  ('apresentacao-resultados', 'Apresentação de Resultados', 'Como estruturar e apresentar resultados financeiros e relatórios de forma clara e convincente para clientes e gestão.', 'Soft Skills', '📈', 'Digit-Curso_Apresentacao_Resultados.html', NULL, 5, 10, true, false, 26),
  ('literacia-ai', 'Literacia em Inteligência Artificial', 'Formação obrigatória em cumprimento do Artigo 4.º do Regulamento Europeu da IA (AI Act). Aprende o que a lei exige, os níveis de risco e como usar IA de forma responsável na Digit.', 'Inovação', '🤖', 'Digit-Curso_Literacia_AI.html', 'Obrigatório', 5, 10, true, true, 27),
  ('ia-contabilidade', 'IA na Contabilidade', 'Onde a inteligência artificial ajuda no trabalho contabilístico, os seus limites e riscos, e como a usar com rigor, sigilo e supervisão humana.', 'Inovação', '🤖', 'Digit-Curso_IA_Contabilidade.html', NULL, 5, 10, true, false, 28),
  ('prompts-eficazes', 'Prompts eficazes', 'Como escrever instruções claras e bem estruturadas para tirar o máximo das ferramentas de IA — com exemplos práticos do dia a dia da Digit.', 'Inovação', '💬', 'Digit-Curso_Prompts_Eficazes.html', NULL, 5, 10, true, false, 29),
  ('bpo', 'BPO — O que é e como funciona', 'Business Process Outsourcing na prática — modelos, processos e como a Digit entrega valor aos clientes em BPO.', 'Inovação', '🔄', 'Digit-Curso_BPO.html', NULL, 5, 10, true, false, 30)
on conflict (slug) do update set
  titulo = excluded.titulo, descricao = excluded.descricao, area = excluded.area,
  icone = excluded.icone, ficheiro = excluded.ficheiro, nivel = excluded.nivel, ordem = excluded.ordem;

-- ---------- 8. Promover o primeiro administrador -------------------------
-- Depois de te registares no portal com o teu email @digit.com.pt, corre:
--   update public.perfis set papel = 'admin' where email = 'id@digit.com.pt';
