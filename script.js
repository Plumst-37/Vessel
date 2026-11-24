// ==============================================================================
// VESSEL — SCRIPTS DE INTERACCIÓN, COMUNIDAD Y DONACIONES
// ==============================================================================

const GOAL = 1000;
let currentAmount = 0;
let currentRating = 5;

document.addEventListener("DOMContentLoaded", () => {
  setupMobileNav();
  setupCopyCommands();
  setupDistroButtons();
  setupStarRating();
  cargarComentarios();
});

// 1. Menú Móvil
function setupMobileNav() {
  const toggle = document.getElementById("nav-toggle");
  const menu = document.getElementById("nav-menu");
  if (!toggle || !menu) return;

  toggle.addEventListener("click", () => {
    const isOpen = menu.classList.toggle("open");
    toggle.setAttribute("aria-expanded", isOpen);
  });

  menu.querySelectorAll(".nav-link").forEach(link => {
    link.addEventListener("click", () => {
      menu.classList.remove("open");
      toggle.setAttribute("aria-expanded", "false");
    });
  });
}

// 2. Copiar comandos en 1 clic (Instalación y Ejecución de 'vessel')
function setupCopyCommands() {
  // Botón 1: Comando de Instalación
  const copyBtn = document.getElementById("copy-btn");
  const cmdEl = document.getElementById("install-cmd");
  const copyLabel = document.getElementById("copy-label");

  if (copyBtn && cmdEl) {
    copyBtn.addEventListener("click", async () => {
      try {
        const text = cmdEl.innerText.trim();
        await navigator.clipboard.writeText(text);
        if (copyLabel) copyLabel.textContent = "¡Copiado!";
        mostrarToast("Comando de instalación copiado");
        setTimeout(() => {
          if (copyLabel) copyLabel.textContent = "Copiar";
        }, 2200);
      } catch (err) {
        console.error("Error al copiar:", err);
      }
    });
  }

  // Botón 2: Comando de Ejecución 'vessel'
  const copyRunBtn = document.getElementById("copy-run-btn");
  const runCmdEl = document.getElementById("run-cmd");
  const copyRunLabel = document.getElementById("copy-run-label");

  if (copyRunBtn && runCmdEl) {
    copyRunBtn.addEventListener("click", async () => {
      try {
        const text = runCmdEl.innerText.trim();
        await navigator.clipboard.writeText(text);
        if (copyRunLabel) copyRunLabel.textContent = "¡Copiado!";
        mostrarToast("Comando 'vessel' copiado");
        setTimeout(() => {
          if (copyRunLabel) copyRunLabel.textContent = "Copiar";
        }, 2200);
      } catch (err) {
        console.error("Error al copiar:", err);
      }
    });
  }
}

// 3. Selector de distribución en terminal
function setupDistroButtons() {
  const buttons = document.querySelectorAll(".distro-btn");
  const cmdEl = document.getElementById("install-cmd");

  if (!buttons.length || !cmdEl) return;

  buttons.forEach(btn => {
    btn.addEventListener("click", () => {
      buttons.forEach(b => b.classList.remove("active"));
      btn.classList.add("active");

      const newCmd = btn.getAttribute("data-cmd");
      if (newCmd) {
        cmdEl.innerText = newCmd;
        mostrarToast(`Comando actualizado para ${btn.innerText}`);
      }
    });
  });
}

// 4. Selector de Estrellas para el Formulario de Reseñas
function setupStarRating() {
  const stars = document.querySelectorAll(".star-btn");
  const ratingLabel = document.getElementById("rating-label");
  const labels = {
    1: "1/5 Básico",
    2: "2/5 Regular",
    3: "3/5 Bueno",
    4: "4/5 Muy Bueno",
    5: "5/5 Excelente"
  };

  stars.forEach(star => {
    star.addEventListener("click", () => {
      currentRating = parseInt(star.getAttribute("data-val"), 10) || 5;
      stars.forEach(s => {
        const val = parseInt(s.getAttribute("data-val"), 10);
        if (val <= currentRating) {
          s.classList.add("active");
        } else {
          s.classList.remove("active");
        }
      });
      if (ratingLabel) {
        ratingLabel.textContent = labels[currentRating] || `${currentRating}/5`;
      }
    });
  });
}

// 5. Publicar y Cargar Comentarios en Muro (con LocalStorage)
function enviarComentario(e) {
  e.preventDefault();
  const authorEl = document.getElementById("c-author");
  const hardwareEl = document.getElementById("c-hardware");
  const msgEl = document.getElementById("c-message");

  if (!authorEl || !hardwareEl || !msgEl) return;

  const author = authorEl.value.trim();
  const hardware = hardwareEl.value.trim();
  const message = msgEl.value.trim();

  if (!author || !hardware || !message) return;

  const nuevo = {
    author,
    hardware,
    stars: currentRating,
    message,
    date: "Justo ahora"
  };

  const comentarios = JSON.parse(localStorage.getItem("vessel_reviews") || "[]");
  comentarios.unshift(nuevo);
  localStorage.setItem("vessel_reviews", JSON.stringify(comentarios));

  insertarComentarioEnDOM(nuevo, true);

  authorEl.value = "";
  hardwareEl.value = "";
  msgEl.value = "";

  mostrarToast("¡Reseña publicada con éxito en el muro!");
}

function insertarComentarioEnDOM(c, isNew = false) {
  const list = document.getElementById("comments-list");
  if (!list) return;

  const card = document.createElement("div");
  card.className = "comment-card";
  if (isNew) {
    card.style.borderColor = "var(--accent-primary)";
  }

  const avatars = ["🎮", "⚡", "🐧", "🛡️", "🔥", "🚀"];
  const randomAvatar = avatars[Math.floor(Math.random() * avatars.length)];
  const starsString = "★".repeat(c.stars) + "☆".repeat(5 - c.stars);

  card.innerHTML = `
    <div class="comment-card-top">
      <div class="comment-author-group">
        <span class="comment-avatar">${randomAvatar}</span>
        <strong class="comment-author">${escapeHtml(c.author)}</strong>
        <span class="comment-distro">${escapeHtml(c.hardware)}</span>
      </div>
      <span class="comment-stars">${starsString}</span>
    </div>
    <p class="comment-body">"${escapeHtml(c.message)}"</p>
    <span class="comment-date">${c.date}</span>
  `;

  list.insertBefore(card, list.firstChild);
}

function cargarComentarios() {
  const guardados = JSON.parse(localStorage.getItem("vessel_reviews") || "[]");
  const list = document.getElementById("comments-list");
  if (!list) return;
  list.innerHTML = "";

  if (guardados.length === 0) {
    list.innerHTML = `
      <div style="padding: 2.5rem 1.5rem; text-align: center; color: var(--text-dim); background: rgba(255, 255, 255, 0.02); border-radius: var(--radius-md); border: 1px dashed var(--border-subtle);">
        <span style="font-size: 2rem; display: block; margin-bottom: 0.5rem;">💬</span>
        <strong style="color: var(--text-main); display: block; margin-bottom: 0.25rem;">Muro de pruebas abierto</strong>
        <p style="font-size: 0.85rem; max-width: 320px; margin: 0 auto;">Aún no se han registrado reseñas locales en este equipo. Usa el formulario para compartir tu prueba de juego con Vessel.</p>
      </div>
    `;
    return;
  }

  // Insertar en orden inverso para que los más nuevos queden arriba
  guardados.reverse().forEach(c => insertarComentarioEnDOM(c));
}

function escapeHtml(text) {
  const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' };
  return text.replace(/[&<>"']/g, m => map[m]);
}

// 6. Modal de Donaciones
const WALLET_USDT = "TX1s...VesselCryptoTRC20";
const WALLET_BTC = "bc1q...VesselBitcoinDev";

function abrirModalPago(tipo) {
  const modal = document.getElementById("payment-modal");
  const title = document.getElementById("modal-title");
  const body = document.getElementById("modal-body-content");
  if (!modal || !title || !body) return;

  if (tipo === "paypal") {
    title.textContent = "Donación con PayPal / Tarjeta";
    body.innerHTML = `
      <p style="margin-bottom: 1rem;">Puedes realizar un aporte voluntario seguro mediante PayPal para apoyar el hardware y empaquetado de Vessel:</p>
      <div style="text-align: center; margin: 1.5rem 0;">
        <a href="https://www.paypal.me/ReinaldoLiendo" target="_blank" rel="noopener noreferrer" class="btn btn-primary" style="padding: 0.75rem 1.5rem;">
          Ir a PayPal.me (@ReinaldoLiendo) →
        </a>
      </div>
      <p style="font-size: 0.8rem; color: var(--text-dim); text-align: center;">Tu apoyo directo permite comprar placas AMD/Intel para calibrar los drivers libres.</p>
    `;
  } else if (tipo === "github") {
    title.textContent = "GitHub Sponsors Oficial";
    body.innerHTML = `
      <p style="margin-bottom: 1rem;">Patrocina a Reinaldo Liendo (<a href="https://github.com/Plumst-37" target="_blank" rel="noopener noreferrer" style="color: #c4b5fd;">@Plumst-37</a>) en el programa oficial de desarrolladores de GitHub:</p>
      <div style="text-align: center; margin: 1.5rem 0;">
        <a href="https://github.com/sponsors/Plumst-37" target="_blank" rel="noopener noreferrer" class="btn btn-primary" style="padding: 0.75rem 1.5rem;">
          💖 Abrir GitHub Sponsors →
        </a>
      </div>
      <p style="font-size: 0.8rem; color: var(--text-dim); text-align: center;">Mecenazgo verificado sin comisiones intermedias.</p>
    `;
  } else if (tipo === "crypto") {
    title.textContent = "Aporte en Criptomonedas (USDT / BTC)";
    body.innerHTML = `
      <p style="margin-bottom: 0.75rem;">Direcciones oficiales de la campaña comunitaria de Vessel:</p>
      
      <div class="modal-option-box">
        <strong style="color: #38bdf8; font-size: 0.85rem;">USDT (Red TRC-20):</strong>
        <div class="modal-copy-row">
          <code id="wallet-usdt">TLx6HqS8oA8xX97j6K5z4pWqP9k2M8vP9B</code>
          <button class="btn-copy" onclick="copiarDireccion('TLx6HqS8oA8xX97j6K5z4pWqP9k2M8vP9B', 'USDT')">Copiar</button>
        </div>
      </div>

      <div class="modal-option-box">
        <strong style="color: #fbbf24; font-size: 0.85rem;">Bitcoin (BTC):</strong>
        <div class="modal-copy-row">
          <code id="wallet-btc">bc1qj4w8k9k6h2g4f8x7v5z3p9m2k8x6j5h4g3f2d1</code>
          <button class="btn-copy" onclick="copiarDireccion('bc1qj4w8k9k6h2g4f8x7v5z3p9m2k8x6j5h4g3f2d1', 'BTC')">Copiar</button>
        </div>
      </div>
    `;
  }

  if (typeof modal.showModal === "function") {
    modal.showModal();
  }
}

function cerrarModalPago() {
  const modal = document.getElementById("payment-modal");
  if (modal && typeof modal.close === "function") {
    modal.close();
  }
}

async function copiarDireccion(dir, red) {
  try {
    await navigator.clipboard.writeText(dir);
    mostrarToast(`Billetera ${red} copiada al portapapeles`);
  } catch (err) {
    console.error("Error al copiar billetera:", err);
  }
}

// 7. Toast de Notificación
let toastTimeout;
function mostrarToast(mensaje) {
  const toast = document.getElementById("toast-notify");
  const toastMsg = document.getElementById("toast-msg");
  if (!toast || !toastMsg) return;

  toastMsg.textContent = mensaje;
  toast.classList.add("show");

  clearTimeout(toastTimeout);
  toastTimeout = setTimeout(() => {
    toast.classList.remove("show");
  }, 2500);
}
