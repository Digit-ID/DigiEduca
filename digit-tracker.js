/* Digit — registo de progresso dos cursos.
   Incluir em cada ficheiro Digit-Curso_*.html, antes de </body>:
     <script type="module" src="digit-tracker.js"></script>
   Depois, no código do curso, chamar:
     DigitTracker.modulo(3);                  // ao concluir o módulo 3
     DigitTracker.avaliacao(8, 10);           // ao submeter a avaliação final
   Sem sessão iniciada no portal, as chamadas são ignoradas em silêncio. */

import { criarStore, lerConfig } from "./digit-data.js";

let store = null;
const pronto = (async () => { store = await criarStore(lerConfig()); })();

const slug = decodeURIComponent(location.pathname.split("/").pop() || "")
  .replace(/^Digit-Curso_/, "").replace(/\.html$/, "")
  .normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
  .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

window.DigitTracker = {
  slug,
  async modulo(n) {
    await pronto;
    if (!store || !store.perfilAtual()) return;
    try { await store.guardarProgresso(slug, Number(n)); } catch (e) { console.warn("Progresso não guardado:", e.message); }
  },
  async avaliacao(nota, total) {
    await pronto;
    if (!store || !store.perfilAtual()) return null;
    try { return await store.concluirCurso(slug, Number(nota), Number(total || 10)); }
    catch (e) { console.warn("Avaliação não guardada:", e.message); return null; }
  },
  async nome() { await pronto; const p = store && store.perfilAtual(); return p ? p.nome : null; }
};

/* Com sessão iniciada no portal, o ecrã de boas-vindas já sabe quem é o colaborador */
(async () => {
  await pronto;
  const p = store && store.perfilAtual();
  const campo = document.getElementById("ni");
  if (p && campo && !campo.value) {
    campo.value = p.nome;
    const rotulo = document.querySelector(".ws-label");
    if (rotulo) rotulo.textContent = "CONFIRMA O TEU NOME (DA TUA CONTA DIGIT)";
  }
})();

/* Símbolo da Digit como favicon em todos os cursos */
(function () {
  if (!document.querySelector('link[rel="icon"]')) {
    const l = document.createElement("link");
    l.rel = "icon"; l.type = "image/png"; l.href = "assets/digit-simbolo.png";
    document.head.appendChild(l);
  }
})();

/* Botão fixo de regresso ao portal, em todos os cursos */
(function () {
  function criar() {
    if (document.getElementById("digitVoltar")) return;
    const a = document.createElement("a");
    a.id = "digitVoltar";
    a.href = "index.html";
    a.textContent = "← Voltar ao portal";
    a.setAttribute("style", [
      "position:fixed", "top:14px", "right:16px", "z-index:99999",
      "background:#fff", "color:#3B5BFF", "border:1.5px solid #3B5BFF",
      "border-radius:9px", "padding:9px 14px", "font:600 13.5px/1 'Helvetica Neue',Helvetica,Arial,sans-serif",
      "text-decoration:none", "box-shadow:0 4px 14px rgba(20,35,100,.16)"
    ].join(";"));
    document.body.appendChild(a);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", criar);
  else criar();
})();
