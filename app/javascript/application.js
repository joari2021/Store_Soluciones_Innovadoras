import "@hotwired/turbo-rails";
import "controllers";
import "bootstrap";

/*=============== ADD BLUR HEADER ===============*/
const blurHeader = () => {
  const header = document.getElementById("header");
  // Add a class if the bottom offset is greater than 50 of the viewport
  window.scrollY >= 50
    ? header.classList.add("blur-header")
    : header.classList.remove("blur-header");
};
window.addEventListener("scroll", blurHeader);

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".copy-entry").forEach((link) => {
    link.addEventListener("click", (event) => {
      event.preventDefault();
      const entryValue = link.dataset.entry;
      navigator.clipboard
        .writeText(entryValue)
        .then(() => {
          // Puedes mostrar una notificación, por ejemplo con alert o con una librería de notificaciones
          alert("Entry copied to clipboard!");
        })
        .catch((err) => {
          console.error("Failed to copy!", err);
        });
    });
  });
});
