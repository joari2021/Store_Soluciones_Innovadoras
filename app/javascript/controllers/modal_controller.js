import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.element.addEventListener("turbo:submit-end", (event) => {
      if (event.detail.success) {
        Turbo.visit(event.detail.fetchResponse.response.url);
      }
    });
  }
}
