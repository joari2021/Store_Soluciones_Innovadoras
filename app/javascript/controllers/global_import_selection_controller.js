import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "checkbox",
    "masterCheckbox",
    "toolbar",
    "count",
    "submitButton",
    "searchHiddenInputs",
    "importHiddenInputs",
  ];
  static values = {
    hiddenClass: { type: String, default: "hidden" },
    selectedIds: Array,
  };

  connect() {
    this.selectedSet = new Set(
      (this.selectedIdsValue || [])
        .map((value) => Number.parseInt(value, 10))
        .filter((value) => Number.isInteger(value) && value > 0),
    );

    this.checkboxTargets.forEach((checkbox) => {
      const productId = this.checkboxProductId(checkbox);
      if (!productId) return;

      if (checkbox.checked) {
        this.selectedSet.add(productId);
      } else if (this.selectedSet.has(productId)) {
        checkbox.checked = true;
      }
    });

    this.refresh();
  }

  toggle(event) {
    const checkbox = event?.currentTarget;
    const productId = this.checkboxProductId(checkbox);
    if (!productId) return;

    if (checkbox.checked) {
      this.selectedSet.add(productId);
    } else {
      this.selectedSet.delete(productId);
    }

    this.refresh();
  }

  toggleVisible(event) {
    const masterCheckbox = event?.currentTarget;
    const shouldSelect = Boolean(masterCheckbox?.checked);

    this.checkboxTargets.forEach((checkbox) => {
      const productId = this.checkboxProductId(checkbox);
      if (!productId) return;

      if (shouldSelect) {
        this.selectedSet.add(productId);
      } else {
        this.selectedSet.delete(productId);
      }
    });

    this.refresh();
  }

  refresh() {
    this.checkboxTargets.forEach((checkbox) => {
      const productId = this.checkboxProductId(checkbox);
      if (!productId) return;

      checkbox.checked = this.selectedSet.has(productId);
    });

    if (this.hasSearchHiddenInputsTarget) {
      this.renderHiddenInputs(
        this.searchHiddenInputsTarget,
        "selected_global_product_ids[]",
      );
    }

    if (this.hasImportHiddenInputsTarget) {
      this.renderHiddenInputs(
        this.importHiddenInputsTarget,
        "global_product_ids[]",
      );
    }

    const selectedCount = this.selectedSet.size;

    if (this.hasMasterCheckboxTarget) {
      const visibleProductIds = this.checkboxTargets
        .map((checkbox) => this.checkboxProductId(checkbox))
        .filter((productId) => Boolean(productId));

      const visibleCheckedCount = visibleProductIds.filter((productId) =>
        this.selectedSet.has(productId),
      ).length;

      this.masterCheckboxTarget.checked =
        visibleProductIds.length > 0 &&
        visibleCheckedCount === visibleProductIds.length;
      this.masterCheckboxTarget.indeterminate =
        visibleCheckedCount > 0 &&
        visibleCheckedCount < visibleProductIds.length;
      this.masterCheckboxTarget.disabled = visibleProductIds.length === 0;
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = String(selectedCount);
    }

    if (this.hasToolbarTarget) {
      this.toolbarTarget.classList.toggle(
        this.hiddenClassValue,
        selectedCount === 0,
      );
      this.toolbarTarget.classList.toggle("flex", selectedCount > 0);
    }

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = selectedCount === 0;
    }
  }

  renderHiddenInputs(container, name) {
    if (!container) return;

    container.innerHTML = "";
    Array.from(this.selectedSet)
      .sort((a, b) => a - b)
      .forEach((productId) => {
        const input = document.createElement("input");
        input.type = "hidden";
        input.name = name;
        input.value = String(productId);
        container.appendChild(input);
      });
  }

  checkboxProductId(checkbox) {
    const rawId = checkbox?.dataset?.globalProductId || checkbox?.value;
    const parsed = Number.parseInt(rawId, 10);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
  }
}
