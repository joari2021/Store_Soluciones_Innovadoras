import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    // Función para cambiar el fondo del modal
    function changeModal(namePelicula, imageUrl) {
      var titleModal = document.getElementById("modal_title");
      titleModal.innerText = namePelicula;

      var modalBody = document.getElementById("modalBody");
      modalBody.style.backgroundColor = "none";
      modalBody.style.backgroundImage = "url(" + imageUrl + ")";
      modalBody.style.backgroundSize = "cover";
      modalBody.style.backgroundPosition = "center";
    }

    var namePelicula = document.getElementById("namePelicula").innerText;
    var imageBackdropUrl =
      document.getElementById("imageBackdroupUrl").innerText;

    changeModal(namePelicula, imageBackdropUrl);

    /* trailer pelicula script */
    const $botonVentanaModal = $("#botonVentanaModal");
    const $ventanaModal = $("#ventanaModal");
    const $iframeVideo = $("#iframeVideo");
    const $btnClosedModalTrailer = $("btn_closed_modal_trailer");

    function getLastSegment(url) {
      // Divide la URL en segmentos utilizando '/' como delimitador
      var segments = url.split("/");

      // Retorna el último segmento
      return segments[segments.length - 1];
    }

    $botonVentanaModal.on("click", function (event) {
      event.preventDefault();
      $ventanaModal.modal("show");
      var url = $botonVentanaModal.attr("href");
      var videoSrc = getLastSegment(url);
      $iframeVideo.attr(
        "src",
        "https://youtube.com/embed/" + videoSrc + "?autoplay=1"
      );
      $ventanaModal.modal("show");
    });

    $botonVentanaModal.on("click", function (event) {
      event.preventDefault();
      $ventanaModal.modal("hide");
    });

    $ventanaModal.on("hidden.bs.modal", function (event) {
      $iframeVideo.attr("src", null);
    });
  }
}
