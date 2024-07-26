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
  }
}
