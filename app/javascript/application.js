import "@hotwired/turbo-rails";
import "controllers";
import "bootstrap";
import "notify";

/*=============== ADD BLUR HEADER ===============*/
const blurHeader = () => {
  const header = document.getElementById("header");
  // Add a class if the bottom offset is greater than 50 of the viewport
  window.scrollY >= 50
    ? header.classList.add("blur-header")
    : header.classList.remove("blur-header");
};
window.addEventListener("scroll", blurHeader);

document.addEventListener("click", (event) => {
  // Verificar si el elemento clickeado tiene la clase .copy
  const link = event.target.closest(".copy");
  if (!link) return; // Si no es un elemento .copy, salir

  event.preventDefault();
  const datoValue = link.dataset.dato;

  if (datoValue) {
    navigator.clipboard
      .writeText(datoValue)
      .then(() => {
        alert("Se ha copiado al Portapapeles!");
      })
      .catch((err) => {
        console.error("Falla al Copiar!", err);
      });
  }
});
