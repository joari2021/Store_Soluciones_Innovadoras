import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    const addButton = document.getElementById("add-appointment");
    const container = document.getElementById("appointments-container");
    const template = document.getElementById("appointment-template").innerHTML;

    // Nuevo contador para asegurar índices únicos
    let appointmentIndex = container.children.length;

    addButton.addEventListener("click", () => {
      const index = appointmentIndex;
      appointmentIndex++; // Incrementa para el siguiente

      // Reemplazar "INDEX" en la plantilla por el índice actual
      let newFields = template.replace(/INDEX/g, index);
      const newAppointment = document.createElement("div");
      newAppointment.innerHTML = newFields;

      // Establecer límites de fecha en el nuevo campo de fecha
      const dateInput = newAppointment.querySelector(".appointment-date");
      const today = new Date();
      const maxDate = new Date();
      maxDate.setMonth(today.getMonth() + 3);
      dateInput.min = today.toISOString().split("T")[0];
      dateInput.max = maxDate.toISOString().split("T")[0];

      // --- Lógica para asignar por defecto el tipo de cita ---
      const existingTypes = Array.from(
        document.querySelectorAll(".appointment-type")
      ).map((select) => select.value);
      let defaultType = "cedula";
      if (
        existingTypes.includes("cedula") &&
        !existingTypes.includes("civil")
      ) {
        defaultType = "civil";
      } else if (
        existingTypes.includes("cedula") &&
        existingTypes.includes("civil")
      ) {
        defaultType = "niño";
      }
      const typeSelect = newAppointment.querySelector(".appointment-type");
      Array.from(typeSelect.options).forEach((option) => {
        option.selected = option.value === defaultType;
      });
      // --- Fin de la lógica de tipo ---

      // Agregar evento para eliminar la cita

      newAppointment
        .querySelector(".remove-appointment")
        .addEventListener("click", () => {
          // En vez de remover el elemento, se marca para destrucción:
          const destroyField = newAppointment.querySelector(
            'input[name*="[_destroy]"]'
          );
          if (destroyField) {
            destroyField.value = "1";
          }
          // Opcional: ocultar el elemento para indicar la eliminación
          newAppointment.style.display = "none";
        });

      container.appendChild(newAppointment);
    });

    // Para las citas existentes, añade el evento de eliminar
    document.querySelectorAll(".remove-appointment").forEach((button) => {
      button.addEventListener("click", () => {
        const appointmentElem = button.closest(".appointment");
        // Busca un campo oculto _destroy
        const destroyInput = appointmentElem.querySelector(
          "input[name*='[_destroy]']"
        );
        if (destroyInput) {
          // Si existe, es una cita ya guardada: marca para destruir y oculta el elemento
          destroyInput.value = "1";
          appointmentElem.style.display = "none";
        } else {
          // Si es una cita nueva, simplemente remuévela del DOM
          appointmentElem.remove();
        }
      });
    });
  }
}
