import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["content", "modal"];

  open(event) {
    event.preventDefault();
    const ventaId = event.currentTarget.dataset.ventaId;
    if (!ventaId) return;

    this.modalTarget.classList.remove("hidden");
    this.modalTarget.classList.add("flex");
    this.loadVentaResumen(ventaId);
  }

  close() {
    this.modalTarget.classList.add("hidden");
    this.modalTarget.classList.remove("flex");
    this.contentTarget.innerHTML = "";
  }

  loadVentaResumen(ventaId) {
    fetch(`/ventas/${ventaId}/resumen_modal`)
      .then((response) => response.text())
      .then((html) => {
        this.contentTarget.innerHTML = html;
      })
      .catch(() => {
        this.contentTarget.innerHTML =
          '<p class="text-sm text-rose-600">No se pudo cargar el resumen de la venta.</p>';
      });
  }
}
