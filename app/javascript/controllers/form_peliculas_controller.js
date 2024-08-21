import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    document.querySelectorAll(".add_fields_rankings").forEach((button) => {
      button.addEventListener("click", function (e) {
        e.preventDefault();
        let time = new Date().getTime();
        let link = this;
        let regexp = new RegExp(link.dataset.id, "g");
        document
          .querySelector("#rankings")
          .insertAdjacentHTML(
            "beforeend",
            link.dataset.fields.replace(regexp, time)
          );
      });
    });

    document.addEventListener("click", function (event) {
      if (event.target.matches(".remove_fields_ranking")) {
        event.preventDefault();
        let field = event.target.closest(".field_ranking");
        field.querySelector("input[type='hidden']").value = "1";
        field.style.display = "none";
      }
    });

    document.querySelectorAll(".add_fields_video_details").forEach((button) => {
      button.addEventListener("click", function (e) {
        e.preventDefault();
        let time = new Date().getTime();
        let link = this;
        let regexp = new RegExp(link.dataset.id, "g");
        document
          .querySelector("#video_details")
          .insertAdjacentHTML(
            "beforeend",
            link.dataset.fields.replace(regexp, time)
          );
      });
    });

    document.addEventListener("click", function (event) {
      if (event.target.matches(".remove_fields_video_detail")) {
        event.preventDefault();
        let field = event.target.closest(".field_video_detail");
        field.querySelector("input[type='hidden']").value = "1";
        field.style.display = "none";
      }
    });

    // Toma el valor del input hidden al cargar la página
    let selectedGenres = document
      .getElementById("genero_ids_order")
      .value.split(",")
      .filter((value) => value !== ""); // Evita valores vacíos

    document.querySelectorAll(".form-check-input").forEach(function (input) {
      input.addEventListener("change", function () {
        let genreId = input.dataset.index;

        if (input.checked) {
          // Agregar el género al array si está seleccionado
          if (!selectedGenres.includes(genreId)) {
            selectedGenres.push(genreId);
          }
        } else {
          // Remover el género del array si se desmarca
          selectedGenres = selectedGenres.filter(function (id) {
            return id !== genreId;
          });
        }

        // Actualizar el valor del input hidden
        document.getElementById("genero_ids_order").value =
          selectedGenres.join(",");
      });
    });
  }
}
