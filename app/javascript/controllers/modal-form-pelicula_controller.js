import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    // Función para cambiar el fondo del modal
    function changeModal() {
      var titleModal = document.getElementById("modal_title");
      titleModal.innerText = "Nueva Pelicula";

      var modalBody = document.getElementById("modalBody");

      modalBody.style.backgroundColor = "#000"; // Establece el color de fondo
      modalBody.style.backgroundImage = "none";
      modalBody.style.backgroundSize = "none";
      modalBody.style.backgroundPosition = "none";
    }
    changeModal();
  }
}
