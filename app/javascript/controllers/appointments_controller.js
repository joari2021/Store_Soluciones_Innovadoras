import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    /*
    this.setMinDate();
    this.initializeTimeSelect();
    document
      .querySelector("#add-appointment")
      .addEventListener("click", this.addAppointment.bind(this));
    this.addRemoveEventListeners();*/
    const addButton = document.getElementById("add-appointment");
    const container = document.getElementById("appointments-container");
    const template = document.getElementById("appointment-template").innerHTML;

    addButton.addEventListener("click", () => {
      // Calcular el índice para la nueva cita
      const index = container.children.length;
      // Reemplazar la palabra INDEX en la plantilla por el índice actual
      let newFields = template.replace(/INDEX/g, index);
      // Crear un nuevo elemento div para la nueva cita
      const newAppointment = document.createElement("div");
      newAppointment.innerHTML = newFields;

      // Establecer límites de fecha en el nuevo campo de fecha
      const dateInput = newAppointment.querySelector(".appointment-date");
      const today = new Date();
      const maxDate = new Date();
      maxDate.setMonth(today.getMonth() + 3);
      dateInput.min = today.toISOString().split("T")[0];
      dateInput.max = maxDate.toISOString().split("T")[0];

      // Agregar el evento para eliminar la cita
      newAppointment
        .querySelector(".remove-appointment")
        .addEventListener("click", () => {
          newAppointment.remove();
        });

      container.appendChild(newAppointment);
    });

    // Para las citas existentes, añade el evento de eliminar
    document.querySelectorAll(".remove-appointment").forEach((button) => {
      button.addEventListener("click", () => {
        button.closest(".appointment").remove();
      });
    });
  }
  /*
  setMinDate() {
    const today = new Date();
    const maxDate = new Date();
    maxDate.setMonth(today.getMonth() + 3);

    document.querySelectorAll(".appointment-date").forEach((input) => {
      input.min = today.toISOString().split("T")[0];
      input.max = maxDate.toISOString().split("T")[0];
    });
  }

  initializeTimeSelect() {
    document.querySelectorAll(".appointment-time").forEach((select) => {
      select.innerHTML = "";
      this.addTimeOptions(select);
    });
  }

  addTimeOptions(select) {
    const timeSlots = [
      "08:00 am",
      "09:00 am",
      "10:00 am",
      "11:00 am",
      "1:00 pm",
      "2:00 pm",
      "3:00 pm",
      "4:00 pm",
      "5:00 pm",
      "6:00 pm",
    ];
    timeSlots.forEach((time) => {
      let option = document.createElement("option");
      option.value = time;
      option.textContent = time;
      select.appendChild(option);
    });
  }

  addAppointment() {
    const container = document.querySelector("#appointments-container");
    const newAppointment = container.firstElementChild.cloneNode(true);

    newAppointment.querySelector(".appointment-date").value = "";
    newAppointment.querySelector(".appointment-time").innerHTML = "";
    this.addTimeOptions(newAppointment.querySelector(".appointment-time"));

    const appointmentTypes = ["cedula", "civil", "niño"];
    const existingTypes = Array.from(
      container.querySelectorAll(".appointment-type")
    ).map((select) => select.value);

    let nextType =
      appointmentTypes.find((type) => !existingTypes.includes(type)) || "niño";
    newAppointment.querySelector(".appointment-type").value = nextType;

    // Añadir evento de eliminar
    newAppointment
      .querySelector(".remove-appointment")
      .addEventListener("click", () => {
        newAppointment.remove();
      });

    container.appendChild(newAppointment);
  }

  addRemoveEventListeners() {
    document.querySelectorAll(".remove-appointment").forEach((button) => {
      button.addEventListener("click", (event) => {
        event.target.closest(".appointment").remove();
      });
    });
  }*/
}
