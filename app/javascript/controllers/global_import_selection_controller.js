import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox", "toolbar", "count", "submitButton"];
  static values = {
    hiddenClass: { type: String, default: "hidden" },
  };

  connect() {
    this.refresh();
  }

  toggle() {
    this.refresh();
  }

  refresh() {
    const selectedCount = this.checkboxTargets.filter((checkbox) => checkbox.checked).length;

    if (this.hasCountTarget) {
      this.countTarget.textContent = String(selectedCount);
    }

    if (this.hasToolbarTarget) {
      this.toolbarTarget.classList.toggle(this.hiddenClassValue, selectedCount === 0);
      this.toolbarTarget.classList.toggle("flex", selectedCount > 0);
    }

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = selectedCount === 0;
    }
  }
}
