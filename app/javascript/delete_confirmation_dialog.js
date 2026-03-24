window.addEventListener("turbo:load", () => {
  document.addEventListener("submit", (event) => {
    if (event.target && event.target.classList.contains("delete-alertbox")) {
      event.preventDefault();
      Swal.fire({
        title: "¿Estás seguro?",
        text: "¡No podrás revertir esto!",
        icon: "warning",
        target: "body",
        heightAuto: false,
        showCancelButton: true,
        confirmButtonColor: "#3085d6",
        cancelButtonColor: "#d33",
        cancelButtonText: "Cancelar",
        confirmButtonText: "Sí, eliminarlo",
      }).then((result) => {
        if (result.isConfirmed) {
          Swal.fire({
            title: "Eliminado!",
            text: "El registro ha sido eliminado.",
            icon: "success",
            target: "body",
            heightAuto: false,
          });
          event.target.submit();
        }
      });
    }
  });
});
