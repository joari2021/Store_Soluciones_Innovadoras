import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.element.addEventListener("turbo:submit-end", (event) => {
      if (event.detail.success) {
        console.log(event.detail.fetchResponse);
        Turbo.visit(event.detail.fetchResponse.response.url);
        if (event.detail.fetchResponse.response.redirected == true) {
          //Turbo.visit(event.detail.fetchResponse.response.url);
        }
      }
    });
  }
}
