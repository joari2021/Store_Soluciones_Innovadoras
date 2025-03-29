import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.assignRemoveListenersToExisting();
    this.initializeAddAppointment();

    // Agregar listener al submit del formulario para quitar min, max y required de las citas

    const saveButton = document.getElementById("btnFormSaime");
    if (saveButton) {
      saveButton.addEventListener("click", (event) => {
        event.preventDefault(); // Prevenir el envío inmediato del formulario
        const form = saveButton.closest("form");
        console.log(form);

        if (form) {
          // Quitar los atributos min, max y required de todos los campos de fecha dentro del formulario
          form.querySelectorAll(".appointment-date").forEach((input) => {
            input.removeAttribute("min");
            input.removeAttribute("max");
            input.removeAttribute("required");
          });
          // Enviar el formulario
          form.requestSubmit();
        }
      });
    }

    document.addEventListener("turbo:submit-end", (event) => {
      // Si la sumisión NO fue exitosa, reestablecer los atributos en los campos de fecha
      if (!event.detail.success) {
        document.querySelectorAll(".appointment-date").forEach((input) => {
          const today = new Date();
          const maxDate = new Date();
          maxDate.setMonth(today.getMonth() + 3);
          input.min = today.toISOString().split("T")[0];
          input.max = maxDate.toISOString().split("T")[0];
          input.required = true;
        });
      }
    });
  }

  // Asigna el listener de eliminar a los botones de citas existentes
  assignRemoveListenersToExisting() {
    document.querySelectorAll(".remove-appointment").forEach((button) => {
      button.addEventListener("click", () => {
        const appointmentElem = button.closest(".appointment");
        this.removeAppointment(appointmentElem);
      });
    });
  }

  // Inicializa el botón para agregar nuevas citas
  initializeAddAppointment() {
    const addButton = document.getElementById("add-appointment");
    const container = document.getElementById("appointments-container");
    const template = document.getElementById("appointment-template").innerHTML;

    // Contador para índices únicos
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

      // Asignar el listener para eliminar la cita en la nueva cita
      const removeBtn = newAppointment.querySelector(".remove-appointment");
      removeBtn.addEventListener("click", () => {
        this.removeAppointment(newAppointment);
      });

      container.appendChild(newAppointment);
    });
  }

  // Función para eliminar una cita
  removeAppointment(appointmentElem) {
    if (!appointmentElem) return;
    // Buscar el campo hidden _destroy
    const destroyInput = appointmentElem.querySelector(
      "input[name*='[_destroy]']"
    );
    if (destroyInput) {
      // Si existe, es una cita ya guardada: marca para destrucción y oculta el elemento
      destroyInput.value = "1";
      appointmentElem.style.display = "none";
    } else {
      // Si es una cita nueva, elimínala completamente del DOM
      appointmentElem.remove();
    }
    // Quitar el atributo required de todos los campos en la cita eliminada
    appointmentElem
      .querySelectorAll("input, select, textarea")
      .forEach((el) => {
        el.removeAttribute("required");
      });
  }
}
