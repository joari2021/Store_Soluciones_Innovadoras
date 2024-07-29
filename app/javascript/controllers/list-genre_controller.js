import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    const genreLinks = document.querySelectorAll(".genre-link");

    genreLinks.forEach((link) => {
      link.addEventListener("click", function () {
        // Elimina la clase activa de todos los enlaces
        genreLinks.forEach((link) => link.classList.remove("list__active"));
        genreLinks.forEach((link) => link.classList.add("list__inside"));

        // Añade la clase activa al enlace clicado.
        this.classList.remove("List__inside");
        this.classList.add("list__active");
      });
    });
  }
}
