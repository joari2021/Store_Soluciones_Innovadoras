import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.toggleFields(); // Llama a la función al cargar la página
    this.initializeManagers(); // Configura los managers al cargar la página

    document
      .getElementById("add_fields_service_managers")
      .addEventListener("click", function (e) {
        e.preventDefault();
        let time = new Date().getTime();
        let link = this;
        let regexp = new RegExp(link.dataset.id, "g");
        document
          .querySelector("#service_managers")
          .insertAdjacentHTML(
            "beforeend",
            link.dataset.fields.replace(regexp, time)
          );
      });

    document.addEventListener("click", function (event) {
      if (event.target.matches(".remove_fields_service_manager")) {
        event.preventDefault();
        let field = event.target.closest(".field_service_manager");
        field.querySelector("input[type='hidden']").value = "1";
        field.style.display = "none";
      }
    });
  }
  toggleFields() {
    const currencySelect = this.element.querySelector(
      "select[name='service[currency_base_price]']"
    );
    const valueUnitsField = this.element.querySelector("#value-units-field");
    const salePriceField = this.element.querySelector("#sale-price-field");
    const valueUnitsInput = valueUnitsField.querySelector("input");
    const salePriceInput = salePriceField.querySelector("input");

    if (currencySelect) {
      const currency = currencySelect.value;

      if (currency === "Bs") {
        valueUnitsField.style.display = "block";
        salePriceField.style.display = "none";
        if (salePriceInput) salePriceInput.value = ""; // Borra el valor del campo oculto
      } else if (currency === "$") {
        valueUnitsField.style.display = "none";
        salePriceField.style.display = "block";
        if (valueUnitsInput) valueUnitsInput.value = ""; // Borra el valor del campo oculto
      } else {
        // Si no se selecciona ninguna opción
        valueUnitsField.style.display = "none";
        salePriceField.style.display = "none";
        if (valueUnitsInput) valueUnitsInput.value = ""; // Borra ambos valores
        if (salePriceInput) salePriceInput.value = "";
      }
    }
  }
  toggleManagers(event) {
    const isChecked = event.target.checked;
    const serviceManagersDiv = this.element.querySelector("#service_managers");
    const addManagerLink = this.element.querySelector("#add-manager-link");

    if (isChecked) {
      // Mostrar el div de service_managers y el enlace para añadir gestores
      serviceManagersDiv.style.display = "block";
      addManagerLink.style.display = "block";

      // Añadir un nuevo gestor solo si no hay ninguno visible
      const visibleManagers = serviceManagersDiv.querySelectorAll(
        ".field_service_manager:not([style*='display: none'])"
      );
      if (visibleManagers.length === 0) {
        const addManagerButton = addManagerLink.querySelector("a");
        if (addManagerButton) {
          addManagerButton.click();
        }
      }
    } else {
      // Ocultar el div de service_managers y el enlace para añadir gestores
      serviceManagersDiv.style.display = "none";
      addManagerLink.style.display = "none";
    }
  }
  initializeManagers() {
    const costCheckbox = this.element.querySelector("#cost");
    const serviceManagersDiv = this.element.querySelector("#service_managers");
    const addManagerLink = this.element.querySelector("#add-manager-link");

    if (costCheckbox && costCheckbox.checked) {
      // Si el checkbox está marcado, mostrar los managers asociados
      serviceManagersDiv.style.display = "block";
      addManagerLink.style.display = "block";
    } else {
      // Si no está marcado, ocultar los managers
      serviceManagersDiv.style.display = "none";
      addManagerLink.style.display = "none";
    }
  }
}
