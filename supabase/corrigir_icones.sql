-- Correção dos ícones do catálogo (correr uma vez, depois do schema.sql)
update public.cursos c set icone = v.icone
from (values
  ('excel-para-iniciantes', '📊'),
  ('excel-intermedio', '📈'),
  ('excel-avancado', '💼'),
  ('power-bi', '📊'),
  ('microsoft-365', '💻'),
  ('power-automate', '⚡'),
  ('iva', '📋'),
  ('irc', '🏢'),
  ('encerramento-contas', '📅'),
  ('calendario-fiscal', '📅'),
  ('irs', '🧾'),
  ('contabilidade-nao-contabilistas', '📚'),
  ('id-fiscal', '🔬'),
  ('processamento-salarial', '💼'),
  ('contratos-trabalho', '📝'),
  ('ferias-faltas-licencas', '🏖️'),
  ('admissoes-cessacoes', '📝'),
  ('subsidios-beneficios', '🎁'),
  ('rgpd', '📑'),
  ('branqueamento-capitais', '🛡️'),
  ('sigilo-etica', '📜'),
  ('seguranca-informacao', '🔐'),
  ('comunicacao-cliente', '🗣️'),
  ('gestao-tempo', '⏱️'),
  ('reunioes-emails', '🤝'),
  ('apresentacao-resultados', '📈'),
  ('literacia-ai', '🤖'),
  ('ia-contabilidade', '🤖'),
  ('prompts-eficazes', '💬'),
  ('bpo', '🔄')
) as v(slug, icone)
where c.slug = v.slug;

-- Confirmação: deve devolver 0
select count(*) as sem_icone from public.cursos where icone is null or icone = 'undefined';
