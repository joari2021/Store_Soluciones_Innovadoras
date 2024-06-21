// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";

// app/javascript/application.js
import "bootstrap";

// app/javascript/packs/application.js

$(document).on("turbolinks:load", function () {
  $("#new-pelicula-button").on("click", function (event) {
    $.ajax({
      url: "/peliculas/new",
      dataType: "script",
    });
  });

  // Esto permite enviar el formulario vía AJAX
  $("form").on("submit", function (event) {
    event.preventDefault();
    $.ajax({
      type: $(this).attr("method"),
      url: $(this).attr("action"),
      data: $(this).serialize(),
      dataType: "script",
    });
  });
});

// app/javascript/packs/application.js

$(document).on("turbolinks:load", function () {
  $("#new-pelicula-button").on("click", function (event) {
    $.ajax({
      url: "/peliculas/new",
      dataType: "script",
    });
  });

  // Esto permite enviar el formulario vía AJAX
  $("form").on("submit", function (event) {
    event.preventDefault();
    $.ajax({
      type: $(this).attr("method"),
      url: $(this).attr("action"),
      data: $(this).serialize(),
      dataType: "script",
    });
  });
});
