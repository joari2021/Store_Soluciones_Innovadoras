import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    /*=============== SHOW MENU ===============*/
    const headerMenu = document.getElementById("header-menu"),
      navClose = document.getElementById("nav-close");

    /* Menu show */
    if (headerMenu) {
      console.log("headerMenu");
      headerMenu.addEventListener("click", () => {
        this.element.classList.add("show-menu");
      });
    }

    /* Menu hidden */
    if (navClose) {
      console.log("navClose");
      navClose.addEventListener("click", () => {
        this.element.classList.remove("show-menu");
      });
    }

    /* Apertura y cierre de listas dinamicas */
    let listElements = document.querySelectorAll(".list__button--click");

    listElements.forEach((listElement) => {
      listElement.addEventListener("click", (event) => {
        event.preventDefault();
        listElement.classList.toggle("arrow");

        let height = 0;
        let menu = listElement.nextElementSibling;
        if (menu.clientHeight == "0") {
          height = menu.scrollHeight;
        }

        menu.style.height = `${height}px`;
      });
    });
  }
}
