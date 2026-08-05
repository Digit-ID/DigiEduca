# Portal de Formação Digit

Portal interno de formação da Digit — 30 cursos interativos em 6 áreas, com contas
individuais, registo de progresso, avaliações, certificados e painel de administração.

Publicado por GitHub Pages: <https://digit-id.github.io/Forma-o_Digit/>

## Estrutura

| Ficheiro | Função |
|---|---|
| `index.html` | Portal — entrada, catálogo, certificados e administração |
| `Digit-Site_Formacao.html` | Página pública de apresentação do catálogo |
| `Digit-Curso_*.html` | Os 30 cursos (5 módulos, avaliação final de 10 perguntas, 70% para aprovar) |
| `digit-data.js` | Camada de dados — Supabase (produção) ou modo de demonstração |
| `digit-tracker.js` | Registo de progresso e notas dentro de cada curso |
| `support.js` | Runtime da aplicação |
| `data/cursos.json` | Catálogo inicial dos 30 cursos |
| `assets/digit-logo.png` | Logótipo |
| `supabase/schema.sql` | Esquema da base de dados (referência; correr no SQL Editor) |
| `supabase/corrigir_icones.sql` | Correção dos ícones do catálogo |

## Base de dados

Projeto Supabase `digit-formacao` (região UE). Autenticação por email `@digit.com.pt`
com palavra-passe; apenas esse domínio pode registar-se — a validação está num gatilho
da base de dados. A segurança por linha (RLS) garante que cada colaborador só acede aos
seus registos e que só um perfil com `papel = 'admin'` vê os dados de todos.

Conta de administração: `id@digit.com.pt`.

Tabelas: `perfis`, `areas`, `cursos`, `progresso`, `respostas_quiz`, `avaliacoes`,
`certificados`, `auditoria`.

## Conformidade

O portal serve de prova documental para o **Art. 4.º do Regulamento (UE) 2024/1689
(AI Act)**: a tabela `auditoria` registra sessões, avaliações e alterações ao catálogo,
e o painel de administração emite um relatório de conformidade em PDF.

## Notas de manutenção

- Publicar sempre todos os ficheiros alterados em conjunto
- Depois de publicar, forçar `Ctrl+Shift+R` (a cache do GitHub Pages é persistente)
- Nomes de ficheiros com acentos (`Digit-Curso_Excel_Avançado.html`) têm de coincidir
  exatamente com as ligações do catálogo
- Todo o conteúdo em português europeu
