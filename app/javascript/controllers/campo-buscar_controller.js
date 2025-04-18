import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    const inputField = document.getElementById("search-input");
    const form = document.getElementById("formulario_buscar");

    inputField.addEventListener("input", function (event) {
      form.requestSubmit();
    });

    if (inputField) {
      inputField.focus();
      const value = inputField.value;
      inputField.value = "";
      inputField.value = value;
    }
  }
}
