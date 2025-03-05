import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.setMinDate();
    this.initializeTimeSelect();
    document
      .querySelector("#add-appointment")
      .addEventListener("click", this.addAppointment.bind(this));
    this.addRemoveEventListeners();
  }

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
  }
}
