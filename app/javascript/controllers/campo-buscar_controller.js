import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    const inputField = document.getElementById("search-input");
    const form = document.getElementById("formulario_buscar");
    const clearButton = document.getElementById("clear-search");

    if (inputField) {
      // Aplicar debounce al evento input
      let debounceTimeout;
      inputField.addEventListener("input", (event) => {
        clearTimeout(debounceTimeout); // Limpiar el timeout anterior
        debounceTimeout = setTimeout(() => {
          form.requestSubmit(); // Enviar el formulario después del debounce
        }, 1000); // Esperar 300ms después de la última pulsación
      });

      // Mantener el focus sin manipular el valor
      inputField.addEventListener("focus", () => {
        inputField.setSelectionRange(
          inputField.value.length,
          inputField.value.length
        ); // Colocar el cursor al final
      });

      // Mostrar el botón de limpiar solo si hay texto
      inputField.addEventListener("input", () => {
        clearButton.style.display = inputField.value ? "inline" : "none";
      });

      // Limpiar el campo al hacer clic en el botón de limpiar
      clearButton.addEventListener("click", () => {
        inputField.value = "";
        clearButton.style.display = "none";
        form.requestSubmit(); // Enviar el formulario para resetear los resultados
      });
    }
  }
}
