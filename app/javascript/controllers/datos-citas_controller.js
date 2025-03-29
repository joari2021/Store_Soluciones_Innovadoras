import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.numberElement = this.element.querySelector(".number-aleatorio");
    this.copyElement = this.element.querySelector(".copy-number");
    this.numberElementTwo = this.element.querySelector(".number-aleatorio-two");
    this.copyElementTwo = this.element.querySelector(".copy-number-two");
    this.nombreElement = this.element.querySelector(".name-aleatorio");
    this.apellidoElement = this.element.querySelector(".last-name-aleatorio");
    this.copyNombreElement = this.element.querySelector(".copy-nombre");
    this.copyApellidoElement = this.element.querySelector(".copy-apellido");

    if (this.numberElement && this.copyElement) {
      this.generateRandomNumber();
    }

    if (this.numberElementTwo && this.copyElementTwo) {
      this.generateRandomNumber();
    }

    if (this.nombreElement && this.apellidoElement) {
      this.generateRandomData();
    }
  }

  generateRandomNumber() {
    if (this.numberElement && this.copyElement) {
      const randomNumber = Math.floor(Math.random() * 2500) + 1;
      this.numberElement.textContent = randomNumber;
      this.copyElement.setAttribute("data-dato", randomNumber);
    }

    if (this.numberElementTwo && this.copyElementTwo) {
      const randomNumber = Math.floor(Math.random() * 2500) + 1;
      this.numberElementTwo.textContent = randomNumber;
      this.copyElementTwo.setAttribute("data-dato", randomNumber);
    }
  }

  generateRandomData() {
    const nombres = [
      "José",
      "María",
      "Luis",
      "Ana",
      "Carlos",
      "Carmen",
      "Juan",
      "Pedro",
      "Francisco",
      "Andrés",
      "Jesús",
      "Margarita",
      "Sofía",
      "Antonio",
      "Alejandro",
      "Gabriela",
      "Ricardo",
      "Beatriz",
      "Fernando",
      "Patricia",
    ];

    const apellidos = [
      "García",
      "Pérez",
      "Rodríguez",
      "González",
      "Fernández",
      "López",
      "Martínez",
      "Sánchez",
      "Ramírez",
      "Torres",
      "Díaz",
      "Vargas",
      "Mendoza",
      "Rojas",
      "Moreno",
      "Jiménez",
      "Suárez",
      "Castro",
      "Gómez",
      "Ortega",
    ];

    const randomNombre = nombres[Math.floor(Math.random() * nombres.length)];
    const randomApellido =
      apellidos[Math.floor(Math.random() * apellidos.length)];

    if (this.nombreElement && this.apellidoElement) {
      this.nombreElement.textContent = randomNombre;
      this.apellidoElement.textContent = randomApellido;

      if (this.copyNombreElement) {
        this.copyNombreElement.setAttribute("data-dato", randomNombre);
      }
      if (this.copyApellidoElement) {
        this.copyApellidoElement.setAttribute("data-dato", randomApellido);
      }
    }
  }
}
