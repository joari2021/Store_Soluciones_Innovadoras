import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["modalBody"];

  connect() {
    const modal = document.getElementById("serviceModal");
    modal.addEventListener("hidden.bs.modal", () => {
      this.modalBodyTarget.innerHTML = "";
      document.getElementById("serviceModalLabel").textContent = "";
    });

    document.addEventListener("click", (event) => {
      if (event.target.closest(".view-service")) {
        const button = event.target.closest(".view-service");
        const serviceId = button.dataset.serviceId;
        const serviceDescription = button.dataset.serviceDescription;
        this.loadService(serviceId, serviceDescription);
      }
    });

    document.addEventListener("click", (event) => {
      // Copiar todo
      if (event.target.closest("#copy-service-modal")) {
        const copyBtn = event.target.closest("#copy-service-modal");
        // 1. Título del modal
        const title = document
          .getElementById("serviceModalLabel")
          .textContent.trim();
        let underlineLength = Math.min(title.length, 30);
        let underline = "=".repeat(underlineLength);
        let text = `*${title}*\n${underline}\n\n`;

        // 2. Precio
        const priceBadge = document.querySelector(
          "#serviceModal .badge.bg-primary"
        );
        if (priceBadge) {
          text += `💰 *PRECIO:* ${priceBadge.textContent.trim()}\n\n`;
        }

        // 3. Cards (excepto pasos a seguir y datos requeridos)
        const cards = document.querySelectorAll(
          "#serviceModal .card:not([data-no-copy])"
        );
        let cardTexts = [];
        cards.forEach((card) => {
          const header = card.querySelector(".card-header");
          const body = card.querySelector(".card-body");
          if (header && body) {
            const title = header.textContent.trim();
            let bodyText = body.innerHTML
              .replace(/<br\s*\/?>/gi, "\n")
              .replace(/<\/p>\s*<p>/gi, "\n")
              .replace(/<\/?p>/gi, "")
              .replace(/&nbsp;/g, " ")
              .replace(/<[^>]+>/g, "");
            bodyText = bodyText.replace(/\n+/g, "\n").trim();

            if (title === "📝 DATOS REQUERIDOS") {
              let formattedLines = bodyText
                .split("\n")
                .map((line) => {
                  // Elimina asteriscos y espacios al inicio
                  let cleanLine = line.trim().replace(/^\*+\s*/, "");
                  if (cleanLine) {
                    return ` 〽️ ${cleanLine}:`; // Solo un asterisco al inicio y al final
                  }
                  return "";
                })
                .filter((line) => line !== "")
                .join("\n");
              cardTexts.push(
                `*${title}*\n${formattedLines}\n\n_*Es importante que no obvie ningún dato a menos que el dato a llenar diga (opcional).*_`
              );
            }

            // Si es "NOTA" o "TIEMPO DE ENTREGA", título en negrita seguido del contenido en cursiva, sin salto de línea
            else if (title === "⚠️ NOTA" || title === "⏰ TIEMPO DE ENTREGA") {
              cardTexts.push(`*${title}:* _${bodyText}_`);
            } else {
              cardTexts.push(`*${title}*\n${bodyText}`);
            }
          }
        });
        if (cardTexts.length > 0) {
          text += cardTexts.join("\n\n") + "\n";
        }

        // Copiar al portapapeles
        navigator.clipboard.writeText(text.trimEnd()).then(() => {
          copyBtn.innerHTML = '<i class="fas fa-check"></i> Copiado';
          setTimeout(() => {
            copyBtn.innerHTML =
              '<i class="fas fa-copy"></i> Copiar información del servicio';
          }, 1500);
        });
      }

      // Copiar solo datos requeridos
      /*
      if (event.target.closest("#copy-required-data")) {
        const copyBtn = event.target.closest("#copy-required-data");
        const card = document.getElementById("required-data-card");
        if (!card) return;

        // Título del servicio con subrayado grueso
        const title = document
          .getElementById("serviceModalLabel")
          .textContent.trim();
        let underlineLength = Math.min(title.length, 30);
        let underline = "=".repeat(underlineLength);
        let text = `*${title}*\n${underline}\n\n`;

        // Card de datos requeridos
        const header = card.querySelector(".card-header");
        const body = card.querySelector(".card-body");
        if (header && body) {
          text += `*${header.textContent.trim()}*\n\n`;
          let bodyText = body.innerHTML
            .replace(/<button[\s\S]*?<\/button>/gi, "")
            .replace(/<br\s*\/?>/gi, "\n")
            .replace(/<\/p>\s*<p>/gi, "\n")
            .replace(/<\/?p>/gi, "")
            .replace(/&nbsp;/g, " ")
            .replace(/<[^>]+>/g, "");
          bodyText = bodyText.replace(/\n+/g, "\n").trim();

          // Procesa cada línea: elimina * inicial, pone en mayúsculas, agrega * al inicio y final, : al final, y punto de lista
          let formattedLines = bodyText
            .split("\n")
            .map((line) => {
              let cleanLine = line.replace(/^\*+/, "").trim();
              if (cleanLine) {
                cleanLine = cleanLine.toUpperCase();
                return `• *${cleanLine}*:`;
              }
              return "";
            })
            .filter((line) => line !== "")
            .join("\n");

          text += `${formattedLines}\n\n`;
          text += `_*NOTA:* copiar este mensaje en su chat para llenar los datos aquí requeridos y volver a enviar. Es importante que no obvie ningún dato a menos que el dato a llenar diga (opcional)._`;
          navigator.clipboard.writeText(text).then(() => {
            copyBtn.innerHTML = '<i class="fas fa-check"></i> Copiado';
            setTimeout(() => {
              copyBtn.innerHTML =
                '<i class="fas fa-copy"></i> Copiar datos requeridos';
            }, 1500);
          });
        }
      }*/
    });

    // Evento global para copiar y mostrar tooltip (esto solo una vez, fuera de la clase si usas Stimulus)
    document.addEventListener("click", function (e) {
      const link = e.target.closest("a.custom-copy-link");
      if (link) {
        e.preventDefault();
        const url = link.getAttribute("href");
        navigator.clipboard.writeText(url).then(() => {
          // Elimina tooltips previos
          link.querySelectorAll(".copied-tooltip").forEach((t) => t.remove());
          // Crea el tooltip
          const tooltip = document.createElement("span");
          tooltip.className = "copied-tooltip";
          tooltip.textContent = "Copiado";
          link.appendChild(tooltip);
          // Forzar reflow y agregar la clase .show para activar la transición
          setTimeout(() => {
            tooltip.classList.add("show");
          }, 10);
          setTimeout(() => {
            tooltip.remove();
          }, 1300);
        });
      }
    });
  }

  loadService(serviceId, serviceDescription) {
    fetch(`/services/${serviceId}`)
      .then((response) => response.text())
      .then((html) => {
        this.modalBodyTarget.innerHTML = html;
        // Coloca la descripción directamente en el título del modal
        document.getElementById("serviceModalLabel").textContent =
          serviceDescription || "";
        // Inicializa los enlaces de copia en los pasos a seguir
        this.initializeCopyLinks();
      });
  }

  initializeCopyLinks() {
    const card = document.getElementById("personal-steps-card");
    if (card) {
      const cardBody = card.querySelector(".card-body");
      if (cardBody) {
        let html = cardBody.innerHTML;
        html = html.replace(/(https?:\/\/[^\s<]+)/g, function (url) {
          return `<a href="${url}" class="custom-copy-link">${url}</a>`;
        });
        cardBody.innerHTML = html;
      }
    }
  }
}
