/* Portal de Formação Digit — camada de dados.
   Dois modos:
   · "supabase" — quando existem URL + chave anónima (produção)
   · "demonstração" — dados locais no navegador, para desenhar/testar sem servidor
   Todas as funções são assíncronas e devolvem a mesma forma nos dois modos. */

const NOMES_DEMO = ["Amílcar Rengel","Gonçalo Vieira","Karina Marques","Alexandre Oliveira","Ruben Fernandes","Helena Costa","Noah Reis","Diogo Vitorino","Joana Piçarra","Ana Rita Martins","Ricardo Martins","Margarida Garcia","Luís Garcia","Francisco Marques","Hugo Ferreira","Nuno Rodrigues","Tiago Silva","Francisco Pinheiro","Paula Garcia","António Sousa","Marisa Barbosa"];
const DEPARTAMENTOS = ["Contabilidade","Fiscalidade","Recursos Humanos","Processamento Salarial","Tesouraria","I&D","BPO"];
const OBRIGATORIOS = ["literacia-ai","rgpd","branqueamento-capitais","seguranca-informacao","sigilo-etica"];
const CHAVE_DEMO = "digitPortalDemo_v3";

/* Projeto Supabase da Digit (chave publicável — protegida por RLS) */
const URL_PADRAO = "https://aucnnpvdbvqwijamjokm.supabase.co";
const CHAVE_PADRAO = "sb_publishable_oMc9Ls4Te9w5MlkuTiuMaQ_pRaEaF1j";

export const slugDoFicheiro = f => String(f).replace(/^Digit-Curso_/, "").replace(/\.html$/, "")
  .normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

const emailDe = n => n.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().split(" ").slice(0, 2).join(".") + "@digit.com.pt";
const semente = s => { let h = 0; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 100000; return h; };
const agora = () => new Date().toISOString();
const diasAtras = d => new Date(Date.now() - d * 864e5).toISOString();
export const codigoCert = () => "DIGIT-" + new Date().getFullYear() + "-" + Math.random().toString(36).slice(2, 8).toUpperCase();

/* ------------------------------------------------------------------ DEMO */
function storeDemo() {
  let db = null;

  const ler = () => { try { return JSON.parse(localStorage.getItem(CHAVE_DEMO) || "null"); } catch (e) { return null; } };
  const gravar = () => localStorage.setItem(CHAVE_DEMO, JSON.stringify(db));

  async function semear() {
    let cursosBase = [];
    try { cursosBase = await (await fetch("./data/cursos.json")).json(); } catch (e) { cursosBase = []; }
    const areas = [];
    cursosBase.forEach(c => { if (!areas.some(a => a.nome === c.area)) areas.push({ nome: c.area, icone: c.areaIcon, ordem: areas.length + 1 }); });
    const cursos = cursosBase.map((c, i) => {
      const slug = slugDoFicheiro(c.ficheiro);
      return { slug, titulo: c.titulo, descricao: c.descricao, area: c.area, icone: c.icon, ficheiro: c.ficheiro, nivel: c.nivel, modulos: 5, duracao_min: 10, estado: "disponivel", ativo: true, obrigatorio: OBRIGATORIOS.includes(slug), ordem: i + 1 };
    });
    const perfis = [{ id: "u-admin", email: "id@digit.com.pt", nome: "Administração Digit", departamento: "Direção", papel: "admin", ativo: true, criado_em: diasAtras(120) }];
    NOMES_DEMO.forEach((n, i) => perfis.push({ id: "u" + i, email: emailDe(n), nome: n, departamento: DEPARTAMENTOS[i % DEPARTAMENTOS.length], papel: "colaborador", ativo: true, criado_em: diasAtras(90 - i) }));
    const progresso = [], certificados = [], avaliacoes = [], auditoria = [];
    perfis.filter(p => p.papel === "colaborador").forEach(p => {
      const s = semente(p.nome);
      const n = s % 7;
      for (let k = 0; k < n; k++) {
        const cu = cursos[(s + k * 7) % cursos.length];
        const concluido = (s + k) % 3 !== 0;
        progresso.push({ utilizador_id: p.id, curso_slug: cu.slug, modulo_atual: concluido ? 5 : 1 + ((s + k) % 4), modulos_feitos: concluido ? [1, 2, 3, 4, 5] : [1, 2], estado: concluido ? "concluido" : "em_curso", iniciado_em: diasAtras(60 - k * 3), atualizado_em: diasAtras(40 - k * 3) });
        if (concluido) {
          const nota = 7 + ((s + k) % 4);
          avaliacoes.push({ utilizador_id: p.id, curso_slug: cu.slug, nota, total: 10, aprovado: true, tentativa: 1, submetido_em: diasAtras(40 - k * 3) });
          certificados.push({ id: "c" + p.id + k, codigo: "DIGIT-2026-" + (1000 + s + k).toString(36).toUpperCase(), utilizador_id: p.id, curso_slug: cu.slug, nome_certificado: p.nome, nota, total: 10, emitido_em: diasAtras(40 - k * 3), valido: true });
        }
      }
    });
    db = { areas, cursos, perfis, progresso, certificados, avaliacoes, auditoria, sessao: null };
    gravar();
  }

  const perfil = () => db.sessao ? db.perfis.find(p => p.id === db.sessao) || null : null;
  const registo = (acao, entidade, detalhe) => {
    const p = perfil();
    db.auditoria.unshift({ id: db.auditoria.length + 1, utilizador_id: p && p.id, email: p ? p.email : null, acao, entidade, detalhe: detalhe || {}, criado_em: agora() });
    gravar();
  };

  return {
    modo: "demonstração",
    async init() { db = ler(); if (!db || !db.cursos || !db.cursos.length) await semear(); return this; },
    reiniciar: async () => { await semear(); },
    perfilAtual: () => perfil(),
    async entrar(email) {
      const p = db.perfis.find(x => x.email === String(email).trim().toLowerCase());
      if (!p) throw new Error("Não existe conta com esse email. Cria a tua conta primeiro.");
      if (!p.ativo) throw new Error("Conta desativada. Fala com a administração.");
      db.sessao = p.id; gravar(); registo("sessao_iniciada", "perfis", { email: p.email });
      return p;
    },
    async registar({ nome, email, departamento }) {
      email = String(email).trim().toLowerCase();
      if (!email.endsWith("@digit.com.pt")) throw new Error("Usa o teu endereço @digit.com.pt.");
      if (db.perfis.some(p => p.email === email)) throw new Error("Já existe uma conta com esse email.");
      const p = { id: "u" + Date.now(), email, nome, departamento, papel: "colaborador", ativo: true, criado_em: agora() };
      db.perfis.push(p); db.sessao = p.id; gravar(); registo("conta_criada", "perfis", { email });
      return p;
    },
    async sair() { registo("sessao_terminada", "perfis", {}); db.sessao = null; gravar(); },
    recuperacaoAtiva: () => false,
    async recuperar(email) {
      if (!db.perfis.some(p => p.email === String(email).trim().toLowerCase())) throw new Error("Não existe conta com esse email.");
      return "No modo de demonstração não há envio de email. Com o Supabase ligado, recebes a mensagem de recuperação.";
    },
    async definirNovaPassword() { throw new Error("Disponível apenas com o Supabase ligado."); },
    async catalogo() {
      const admin = perfil() && perfil().papel === "admin";
      return { areas: db.areas.slice().sort((a, b) => a.ordem - b.ordem), cursos: db.cursos.filter(c => admin || (c.estado || "disponivel") !== "oculto") };
    },
    async meuProgresso() {
      const p = perfil(); if (!p) return {};
      const m = {};
      db.progresso.filter(x => x.utilizador_id === p.id).forEach(x => { m[x.curso_slug] = { ...x }; });
      db.avaliacoes.filter(x => x.utilizador_id === p.id).forEach(x => { m[x.curso_slug] = { ...(m[x.curso_slug] || {}), nota: x.nota, total: x.total }; });
      return m;
    },
    async meusCertificados() {
      const p = perfil(); if (!p) return [];
      return db.certificados.filter(c => c.utilizador_id === p.id && c.valido).sort((a, b) => b.emitido_em.localeCompare(a.emitido_em));
    },
    async guardarProgresso(slug, modulo) {
      const p = perfil(); if (!p) return;
      let r = db.progresso.find(x => x.utilizador_id === p.id && x.curso_slug === slug);
      if (!r) { r = { utilizador_id: p.id, curso_slug: slug, modulos_feitos: [], estado: "em_curso", iniciado_em: agora() }; db.progresso.push(r); }
      r.modulo_atual = modulo;
      if (!r.modulos_feitos.includes(modulo)) r.modulos_feitos.push(modulo);
      r.atualizado_em = agora(); gravar();
    },
    async concluirCurso(slug, nota, total) {
      const p = perfil(); if (!p) return null;
      let r = db.progresso.find(x => x.utilizador_id === p.id && x.curso_slug === slug);
      if (!r) { r = { utilizador_id: p.id, curso_slug: slug, modulos_feitos: [1, 2, 3, 4, 5], iniciado_em: agora() }; db.progresso.push(r); }
      r.estado = nota >= Math.ceil(total * 0.7) ? "concluido" : "em_curso"; r.modulo_atual = 5; r.atualizado_em = agora();
      db.avaliacoes.push({ utilizador_id: p.id, curso_slug: slug, nota, total, aprovado: r.estado === "concluido", tentativa: db.avaliacoes.filter(a => a.utilizador_id === p.id && a.curso_slug === slug).length + 1, submetido_em: agora() });
      let cert = null;
      if (r.estado === "concluido" && !db.certificados.some(c => c.utilizador_id === p.id && c.curso_slug === slug && c.valido)) {
        cert = { id: "c" + Date.now(), codigo: codigoCert(), utilizador_id: p.id, curso_slug: slug, nome_certificado: p.nome, nota, total, emitido_em: agora(), valido: true };
        db.certificados.push(cert);
      }
      registo("avaliacao_submetida", "avaliacoes", { curso: slug, nota, total });
      gravar(); return cert;
    },
    async colaboradores() {
      return db.perfis.map(p => {
        const pr = db.progresso.filter(x => x.utilizador_id === p.id);
        const certs = db.certificados.filter(c => c.utilizador_id === p.id && c.valido);
        const obrig = db.cursos.filter(c => c.obrigatorio && (c.estado || "disponivel") === "disponivel");
        return {
          ...p,
          cursos_concluidos: pr.filter(x => x.estado === "concluido").length,
          cursos_em_curso: pr.filter(x => x.estado === "em_curso").length,
          certificados: certs.length,
          obrigatorios_total: obrig.length,
          obrigatorios_concluidos: obrig.filter(c => pr.some(x => x.curso_slug === c.slug && x.estado === "concluido")).length,
          ultima_atividade: pr.length ? pr.map(x => x.atualizado_em).sort().pop() : p.criado_em,
          notas: db.avaliacoes.filter(a => a.utilizador_id === p.id).map(a => ({ curso: a.curso_slug, nota: a.nota, total: a.total, data: a.submetido_em }))
        };
      });
    },
    async certificadosTodos() {
      return db.certificados.map(c => ({ ...c, nome: (db.perfis.find(p => p.id === c.utilizador_id) || {}).nome, email: (db.perfis.find(p => p.id === c.utilizador_id) || {}).email, curso: (db.cursos.find(x => x.slug === c.curso_slug) || {}).titulo }))
        .sort((a, b) => b.emitido_em.localeCompare(a.emitido_em));
    },
    async auditoria() { return db.auditoria.slice(0, 200); },
    async definirEstado(slug, estado) {
      const c = db.cursos.find(x => x.slug === slug);
      if (c) { c.estado = estado; c.ativo = estado === "disponivel"; registo("curso_estado", "cursos", { curso: slug, estado }); }
    },
    async alternarObrigatorio(slug, v) {
      const c = db.cursos.find(x => x.slug === slug); if (c) { c.obrigatorio = v; registo("curso_obrigatoriedade", "cursos", { curso: slug, obrigatorio: v }); }
    },
    async definirPapel(id, papel) {
      const p = db.perfis.find(x => x.id === id); if (p) { p.papel = papel; registo("papel_alterado", "perfis", { email: p.email, papel }); }
    },
    async removerColaborador(id) {
      const p = db.perfis.find(x => x.id === id);
      db.perfis = db.perfis.filter(x => x.id !== id);
      db.progresso = db.progresso.filter(x => x.utilizador_id !== id);
      registo("colaborador_removido", "perfis", { email: p && p.email });
    },
    async revalidarCertificado(id, valido) {
      const c = db.certificados.find(x => x.id === id); if (c) { c.valido = valido; registo(valido ? "certificado_revalidado" : "certificado_anulado", "certificados", { codigo: c.codigo }); }
    }
  };
}

/* -------------------------------------------------------------- SUPABASE */
function storeSupabase(url, chave) {
  let sb = null, meu = null, recuperacao = false;
  const erro = r => { if (r.error) throw new Error(r.error.message); return r.data; };
  const audit = (acao, entidade, detalhe) => sb.rpc("registar_auditoria", { p_acao: acao, p_entidade: entidade, p_detalhe: detalhe || {} }).then(() => {}, () => {});

  return {
    modo: "supabase",
    async init() {
      const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
      /* Com o Supabase ligado, os dados do antigo modo de demonstração ficam obsoletos
         e podem encher a quota do navegador, impedindo a gravação do token de sessão. */
      try {
        ["digitPortalDemo", "digitPortalDemo_v2", "digitPortalDemo_v3", "digitUsers", "digitSession"]
          .forEach(k => { localStorage.removeItem(k); sessionStorage.removeItem(k); });
      } catch (e) {}
      /* Armazenamento resiliente: se o localStorage falhar, cai para sessionStorage e depois memória */
      const memoria = {};
      const arm = {
        getItem: k => { try { const v = localStorage.getItem(k); if (v != null) return v; } catch (e) {} try { const v = sessionStorage.getItem(k); if (v != null) return v; } catch (e) {} return memoria[k] != null ? memoria[k] : null; },
        setItem: (k, v) => { memoria[k] = v; try { localStorage.setItem(k, v); return; } catch (e) {} try { sessionStorage.setItem(k, v); } catch (e) {} },
        removeItem: k => { delete memoria[k]; try { localStorage.removeItem(k); } catch (e) {} try { sessionStorage.removeItem(k); } catch (e) {} }
      };
      sb = createClient(url, chave, { auth: { storage: arm } });
      recuperacao = /type=recovery/.test(location.hash) || /type=recovery/.test(location.search);
      const { data } = await sb.auth.getSession();
      if (data && data.session && !recuperacao) meu = erro(await sb.from("perfis").select("*").eq("id", data.session.user.id).single());
      return this;
    },
    perfilAtual: () => meu,
    async entrar(email, password) {
      const d = erro(await sb.auth.signInWithPassword({ email: String(email).trim().toLowerCase(), password }));
      meu = erro(await sb.from("perfis").select("*").eq("id", d.user.id).single());
      audit("sessao_iniciada", "perfis", { email: meu.email });
      return meu;
    },
    async registar({ nome, email, password, departamento }) {
      email = String(email).trim().toLowerCase();
      if (!email.endsWith("@digit.com.pt")) throw new Error("Usa o teu endereço @digit.com.pt.");
      const d = erro(await sb.auth.signUp({ email, password, options: { data: { nome, departamento } } }));
      if (!d.session) throw new Error("Conta criada. Confirma o email para entrar.");
      meu = erro(await sb.from("perfis").select("*").eq("id", d.user.id).single());
      return meu;
    },
    async sair() { await audit("sessao_terminada", "perfis", {}); await sb.auth.signOut(); meu = null; },
    recuperacaoAtiva: () => recuperacao,
    async recuperar(email) {
      email = String(email).trim().toLowerCase();
      if (!email.endsWith("@digit.com.pt")) throw new Error("Usa o teu endereço @digit.com.pt.");
      erro(await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname }));
      return "Enviámos um email para " + email + " com a ligação para definir uma nova palavra-passe. Verifica também o spam.";
    },
    async definirNovaPassword(password) {
      if (!password || password.length < 8) throw new Error("A palavra-passe precisa de 8 caracteres.");
      const d = erro(await sb.auth.updateUser({ password }));
      recuperacao = false;
      if (history.replaceState) history.replaceState(null, "", location.pathname);
      meu = erro(await sb.from("perfis").select("*").eq("id", d.user.id).single());
      audit("password_alterada", "perfis", { email: meu.email });
      return meu;
    },
    async catalogo() {
      const areas = erro(await sb.from("areas").select("*").order("ordem"));
      const cursos = erro(await sb.from("cursos").select("*").order("ordem"));
      return { areas, cursos };
    },
    async meuProgresso() {
      if (!meu) return {};
      const pr = erro(await sb.from("progresso").select("*").eq("utilizador_id", meu.id));
      const av = erro(await sb.from("avaliacoes").select("*").eq("utilizador_id", meu.id));
      const m = {};
      pr.forEach(x => { m[x.curso_slug] = { ...x }; });
      av.forEach(x => { m[x.curso_slug] = { ...(m[x.curso_slug] || {}), nota: x.nota, total: x.total }; });
      return m;
    },
    async meusCertificados() {
      if (!meu) return [];
      return erro(await sb.from("certificados").select("*").eq("utilizador_id", meu.id).eq("valido", true).order("emitido_em", { ascending: false }));
    },
    async guardarProgresso(slug, modulo) {
      if (!meu) return;
      const atual = erro(await sb.from("progresso").select("*").eq("utilizador_id", meu.id).eq("curso_slug", slug).maybeSingle());
      const feitos = new Set((atual && atual.modulos_feitos) || []); feitos.add(modulo);
      erro(await sb.from("progresso").upsert({ utilizador_id: meu.id, curso_slug: slug, modulo_atual: modulo, modulos_feitos: [...feitos], estado: (atual && atual.estado) || "em_curso", atualizado_em: new Date().toISOString() }, { onConflict: "utilizador_id,curso_slug" }));
    },
    async concluirCurso(slug, nota, total) {
      if (!meu) return null;
      const aprovado = nota >= Math.ceil(total * 0.7);
      const tentativas = erro(await sb.from("avaliacoes").select("id").eq("utilizador_id", meu.id).eq("curso_slug", slug));
      erro(await sb.from("avaliacoes").insert({ utilizador_id: meu.id, curso_slug: slug, nota, total, aprovado, tentativa: tentativas.length + 1 }));
      erro(await sb.from("progresso").upsert({ utilizador_id: meu.id, curso_slug: slug, modulo_atual: 5, modulos_feitos: [1, 2, 3, 4, 5], estado: aprovado ? "concluido" : "em_curso", atualizado_em: new Date().toISOString() }, { onConflict: "utilizador_id,curso_slug" }));
      audit("avaliacao_submetida", "avaliacoes", { curso: slug, nota, total });
      if (!aprovado) return null;
      const jaTem = erro(await sb.from("certificados").select("*").eq("utilizador_id", meu.id).eq("curso_slug", slug).eq("valido", true));
      if (jaTem.length) return jaTem[0];
      return erro(await sb.from("certificados").insert({ utilizador_id: meu.id, curso_slug: slug, nome_certificado: meu.nome, nota, total }).select().single());
    },
    async colaboradores() {
      const perfis = erro(await sb.from("perfis").select("*").order("nome"));
      const pr = erro(await sb.from("progresso").select("*"));
      const av = erro(await sb.from("avaliacoes").select("*"));
      const certs = erro(await sb.from("certificados").select("*").eq("valido", true));
      const obrig = erro(await sb.from("cursos").select("slug").eq("obrigatorio", true).eq("estado", "disponivel"));
      return perfis.map(p => {
        const meus = pr.filter(x => x.utilizador_id === p.id);
        return {
          ...p,
          cursos_concluidos: meus.filter(x => x.estado === "concluido").length,
          cursos_em_curso: meus.filter(x => x.estado === "em_curso").length,
          certificados: certs.filter(c => c.utilizador_id === p.id).length,
          obrigatorios_total: obrig.length,
          obrigatorios_concluidos: obrig.filter(o => meus.some(x => x.curso_slug === o.slug && x.estado === "concluido")).length,
          ultima_atividade: meus.length ? meus.map(x => x.atualizado_em).sort().pop() : p.criado_em,
          notas: av.filter(a => a.utilizador_id === p.id).map(a => ({ curso: a.curso_slug, nota: a.nota, total: a.total, data: a.submetido_em }))
        };
      });
    },
    async certificadosTodos() {
      const certs = erro(await sb.from("certificados").select("*").order("emitido_em", { ascending: false }));
      const perfis = erro(await sb.from("perfis").select("id,nome,email"));
      const cursos = erro(await sb.from("cursos").select("slug,titulo"));
      return certs.map(c => ({ ...c, nome: (perfis.find(p => p.id === c.utilizador_id) || {}).nome, email: (perfis.find(p => p.id === c.utilizador_id) || {}).email, curso: (cursos.find(x => x.slug === c.curso_slug) || {}).titulo }));
    },
    async auditoria() { return erro(await sb.from("auditoria").select("*").order("criado_em", { ascending: false }).limit(200)); },
    async definirEstado(slug, estado) { erro(await sb.from("cursos").update({ estado }).eq("slug", slug)); audit("curso_estado", "cursos", { curso: slug, estado }); },
    async alternarObrigatorio(slug, obrigatorio) { erro(await sb.from("cursos").update({ obrigatorio }).eq("slug", slug)); audit("curso_obrigatoriedade", "cursos", { curso: slug, obrigatorio }); },
    async definirPapel(id, papel) { erro(await sb.from("perfis").update({ papel }).eq("id", id)); audit("papel_alterado", "perfis", { id, papel }); },
    async removerColaborador(id) { erro(await sb.from("perfis").update({ ativo: false }).eq("id", id)); audit("colaborador_desativado", "perfis", { id }); },
    async revalidarCertificado(id, valido) { erro(await sb.from("certificados").update({ valido }).eq("id", id)); audit(valido ? "certificado_revalidado" : "certificado_anulado", "certificados", { id }); }
  };
}

export function lerConfig(props) {
  let guardado = {};
  try { guardado = JSON.parse(localStorage.getItem("digitSupabaseConfig") || "{}"); } catch (e) {}
  return {
    url: (props && props.supabaseUrl) || guardado.url || URL_PADRAO,
    chave: (props && props.supabaseKey) || guardado.chave || CHAVE_PADRAO
  };
}
export function gravarConfig(url, chave) {
  localStorage.setItem("digitSupabaseConfig", JSON.stringify({ url, chave }));
}

export async function criarStore(cfg) {
  if (cfg && cfg.url && cfg.chave) {
    try { return await storeSupabase(cfg.url, cfg.chave).init(); }
    catch (e) { console.warn("Supabase indisponível, a usar modo de demonstração:", e.message); }
  }
  return await storeDemo().init();
}

export function paraCSV(linhas) {
  if (!linhas.length) return "";
  const cols = Object.keys(linhas[0]);
  const esc = v => '"' + String(v == null ? "" : v).replace(/"/g, '""') + '"';
  return [cols.join(";")].concat(linhas.map(l => cols.map(c => esc(l[c])).join(";"))).join("\r\n");
}
export function descarregar(nome, texto, tipo) {
  const b = new Blob(["\ufeff" + texto], { type: (tipo || "text/csv") + ";charset=utf-8" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(b); a.download = nome; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}
