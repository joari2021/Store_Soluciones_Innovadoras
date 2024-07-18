import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.element.addEventListener("turbo:submit-end", (event) => {
      const url = event.detail.fetchResponse.response.url;
      const form = document.querySelector("#form-peliculas");

      // Verifica que no sea la acción de editar o actualizar
      if (event.detail.success && !url.includes("/edit")) {
        if (form != null && form.dataset.visit === "false") {
          Turbo.visit(url);
        } else if (form === null) {
          Turbo.visit(url);
        }
      }
    });
  }
}
