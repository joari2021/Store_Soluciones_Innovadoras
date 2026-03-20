import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["modalBody", "modalTitle"];

  connect() {
    this.handleDocumentClick = this.handleDocumentClick.bind(this);
    this.handleKeydown = this.handleKeydown.bind(this);
    document.addEventListener("click", this.handleDocumentClick);
    document.addEventListener("keydown", this.handleKeydown);
  }

  disconnect() {
    document.removeEventListener("click", this.handleDocumentClick);
    document.removeEventListener("keydown", this.handleKeydown);
  }

  handleDocumentClick(event) {
    const viewButton = event.target.closest(".view-service");
    if (viewButton) {
      const serviceId = viewButton.dataset.serviceId;
      const serviceDescription = viewButton.dataset.serviceDescription;
      const cautionService = viewButton.dataset.serviceCaution === "true";
      const userIsAdmin = viewButton.dataset.userAdmin === "true";

      if (cautionService && !userIsAdmin) {
        this.confirmCautionWarning().then((confirmed) => {
          if (!confirmed) return;

          this.loadService(serviceId, serviceDescription);
        });
        return;
      }

      this.loadService(serviceId, serviceDescription);
      return;
    }

    const closeButton = event.target.closest("[data-modal-service-close]");
    if (closeButton) {
      this.closeModal();
      return;
    }

    const copyButton = event.target.closest("[data-service-copy]");
    if (copyButton) {
      this.copyServiceInfo(copyButton);
      return;
    }

    const link = event.target.closest("a.custom-copy-link");
    if (link) {
      event.preventDefault();
      const url = link.getAttribute("href");
      if (!url) return;
      navigator.clipboard.writeText(url).then(() => {
        link.querySelectorAll(".copied-tooltip").forEach((t) => t.remove());
        const tooltip = document.createElement("span");
        tooltip.className = "copied-tooltip";
        tooltip.textContent = "Copiado";
        link.appendChild(tooltip);
        setTimeout(() => {
          tooltip.classList.add("show");
        }, 10);
        setTimeout(() => {
          tooltip.remove();
        }, 1300);
      });
    }
  }

  handleKeydown(event) {
    if (event.key !== "Escape") return;
    if (!this.isOpen()) return;
    this.closeModal();
  }

  loadService(serviceId, serviceDescription) {
    this.openModal(serviceDescription);
    this.modalBodyTarget.innerHTML = this.loadingTemplate();

    fetch(`/services/${serviceId}`)
      .then((response) => response.text())
      .then((html) => {
        this.modalBodyTarget.innerHTML = html;
        this.initializeCopyLinks();
        this.refreshIcons();
      })
      .catch(() => {
        this.modalBodyTarget.innerHTML =
          '<p class="text-sm text-slate-500">No se pudo cargar el servicio.</p>';
      });
  }

  initializeCopyLinks() {
    const card = document.getElementById("personal-steps-card");
    if (card) {
      const cardBody = card.querySelector("[data-service-text]");
      if (cardBody) {
        if (cardBody.querySelector(".custom-copy-link")) return;
        const html = cardBody.innerHTML.replace(
          /(https?:\/\/[^\s<]+)/g,
          (url) => `<a href="${url}" class="custom-copy-link">${url}</a>`,
        );
        cardBody.innerHTML = html;
      }
    }
  }

  openModal(serviceDescription) {
    this.element.classList.remove("hidden");
    this.element.classList.add("flex");
    requestAnimationFrame(() => {
      this.element.classList.add("is-open");
    });
    this.element.setAttribute("aria-hidden", "false");
    if (this.hasModalTitleTarget) {
      this.modalTitleTarget.textContent = serviceDescription || "";
    }
    document.body.classList.add("overflow-hidden");
  }

  closeModal() {
    this.element.classList.remove("is-open");
    this.element.setAttribute("aria-hidden", "true");
    document.body.classList.remove("overflow-hidden");
    setTimeout(() => {
      this.element.classList.add("hidden");
      this.element.classList.remove("flex");
      if (this.hasModalBodyTarget) this.modalBodyTarget.innerHTML = "";
      if (this.hasModalTitleTarget) this.modalTitleTarget.textContent = "";
    }, 180);
  }

  isOpen() {
    return this.element.classList.contains("is-open");
  }

  loadingTemplate() {
    return '<div class="animate-pulse space-y-3"><div class="h-4 w-40 rounded-full bg-slate-200"></div><div class="h-3 w-full rounded-full bg-slate-100"></div><div class="h-3 w-3/4 rounded-full bg-slate-100"></div></div>';
  }

  confirmCautionWarning() {
    const title = "Servicio con precaucion";
    const text =
      "Este servicio debe ofrecerse con prudencia y cuidando el entorno antes de continuar.";

    if (window.Swal && typeof window.Swal.fire === "function") {
      return window.Swal.fire({
        icon: "warning",
        title,
        text,
        confirmButtonText: "Continuar",
        cancelButtonText: "Cancelar",
        showCancelButton: true,
        reverseButtons: true,
      }).then((result) => result.isConfirmed);
    }

    return Promise.resolve(window.confirm(`${title}\n\n${text}`));
  }

  copyServiceInfo(button) {
    const text = this.buildCopyText();
    if (!text) return;

    const originalHtml = button.innerHTML;
    navigator.clipboard.writeText(text).then(() => {
      button.innerHTML = '<i data-lucide="check" class="h-4 w-4"></i> Copiado';
      this.refreshIcons();
      setTimeout(() => {
        button.innerHTML = originalHtml;
        this.refreshIcons();
      }, 1500);
    });
  }

  buildCopyText() {
    const title = this.hasModalTitleTarget
      ? this.modalTitleTarget.textContent.trim()
      : "";
    if (!title) return "";

    const underlineLength = Math.min(title.length, 30);
    const underline = "=".repeat(underlineLength);
    let text = `*${title}*\n${underline}\n\n`;

    const priceEl = this.element.querySelector("[data-service-price]");
    if (priceEl) {
      text += `💰 *PRECIO:* ${priceEl.textContent.trim()}\n\n`;
    }

    const sections = this.element.querySelectorAll("[data-service-section]");
    const sectionTexts = [];

    sections.forEach((section) => {
      if (section.dataset.copy === "false") return;
      const sectionTitle = section.dataset.title || "";
      const bodyEl = section.querySelector("[data-service-text]");
      const bodyText = this.htmlToText(bodyEl?.innerHTML || "");
      if (!sectionTitle || !bodyText) return;

      const format = section.dataset.format || "default";
      if (format === "required-data") {
        const formattedLines = bodyText
          .split("\n")
          .map((line) => {
            const cleanLine = line.trim().replace(/^\*+\s*/, "");
            return cleanLine ? ` 〽️ ${cleanLine}:` : "";
          })
          .filter((line) => line !== "")
          .join("\n");

        sectionTexts.push(
          `*${sectionTitle}*\n${formattedLines}\n\n_*Es importante que no obvie ningun dato a menos que el dato a llenar diga (opcional).*_`,
        );
      } else if (format === "inline") {
        sectionTexts.push(`*${sectionTitle}:* _${bodyText}_`);
      } else {
        sectionTexts.push(`*${sectionTitle}*\n${bodyText}`);
      }
    });

    if (sectionTexts.length > 0) {
      text += sectionTexts.join("\n\n") + "\n";
    }

    return text.trimEnd();
  }

  htmlToText(rawHtml) {
    return String(rawHtml || "")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<\/p>\s*<p>/gi, "\n")
      .replace(/<\/?p>/gi, "")
      .replace(/&nbsp;/g, " ")
      .replace(/<[^>]+>/g, "")
      .replace(/\n+/g, "\n")
      .trim();
  }

  refreshIcons() {
    if (window.lucide && typeof window.lucide.createIcons === "function") {
      window.lucide.createIcons();
    }
  }
}
