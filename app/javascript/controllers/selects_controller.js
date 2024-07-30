import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    const botonesSelect = document.querySelectorAll("#boton_select");

    botonesSelect.forEach((botonSelect) => {
      const nameSelect = botonSelect.dataset.select,
        optionMenu = document.querySelector(`#select_menu_${nameSelect}`),
        selectBtn = optionMenu.querySelector(`#select_btn_${nameSelect}`),
        options = optionMenu.querySelectorAll(`#option_${nameSelect}`),
        sBtn_text = optionMenu.querySelector(`#sBtn_text_${nameSelect}`);

      selectBtn.addEventListener("click", () =>
        optionMenu.classList.toggle("active")
      );

      options.forEach((option) => {
        option.addEventListener("click", () => {
          let selectedOption = option.querySelector(
            `#option_text_${nameSelect}`
          ).innerText;
          sBtn_text.innerText = selectedOption;

          optionMenu.classList.remove("active");
        });
      });
    });
  }
}
