import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.bcvRate = this.parseRate(this.element.dataset.bcvRate);

    this.handleClickBound = this.handleClick.bind(this);
    this.handleInputBound = this.handleInput.bind(this);
    this.handleChangeBound = this.handleChange.bind(this);
    this.handleKeydownBound = this.handleKeydown.bind(this);
    this.handleWheelBound = this.handleWheel.bind(this);
    this.handleDocumentClickBound = this.handleDocumentClick.bind(this);

    this.element.addEventListener("click", this.handleClickBound);
    this.element.addEventListener("input", this.handleInputBound);
    this.element.addEventListener("change", this.handleChangeBound);
    this.element.addEventListener("keydown", this.handleKeydownBound);
    this.element.addEventListener("wheel", this.handleWheelBound, {
      passive: false,
    });
    document.addEventListener("click", this.handleDocumentClickBound);

    this.updatePricingModeVisibility();
    this.updateFixedCurrencyVisibility();
    this.updateExpensesVisibility();
    this.initializeStructureCards();
    this.syncAllProductSearchRows();
    this.syncAllExpenseReferenceRows();
    this.syncAllNestedServiceRows();
    this.refreshAllStructureTotals();
    this.refreshLucideIcons();

    window.MoneyInputMask?.init(this.element);
  }

  disconnect() {
    this.element.removeEventListener("click", this.handleClickBound);
    this.element.removeEventListener("input", this.handleInputBound);
    this.element.removeEventListener("change", this.handleChangeBound);
    this.element.removeEventListener("keydown", this.handleKeydownBound);
    this.element.removeEventListener("wheel", this.handleWheelBound);
    document.removeEventListener("click", this.handleDocumentClickBound);
  }

  handleClick(event) {
    const openStructureModalButton = event.target.closest(
      "[data-open-structure-modal]",
    );
    if (openStructureModalButton) {
      event.preventDefault();
      const structureRow = openStructureModalButton.closest(
        "[data-structure-item]",
      );
      this.openStructureModal(structureRow);
      return;
    }

    const closeStructureModalButton = event.target.closest(
      "[data-close-structure-modal]",
    );
    if (closeStructureModalButton) {
      event.preventDefault();
      const structureRow = closeStructureModalButton.closest(
        "[data-structure-item]",
      );
      this.closeStructureModal(structureRow);
      return;
    }

    const addStructureButton = event.target.closest(
      "[data-add-expense-structure]",
    );
    if (addStructureButton) {
      event.preventDefault();
      this.addExpenseStructure();
      return;
    }

    const addNestedButton = event.target.closest("[data-add-nested-row]");
    if (addNestedButton) {
      event.preventDefault();
      this.addNestedRow(addNestedButton);
      return;
    }

    const removeStructureButton = event.target.closest(
      "[data-remove-structure]",
    );
    if (removeStructureButton) {
      event.preventDefault();
      const structureRow = removeStructureButton.closest(
        "[data-structure-item]",
      );
      this.removeRecordRow(structureRow);
      this.refreshAllStructureTotals();
      return;
    }

    const productResultOption = event.target.closest(
      "[data-product-result-option]",
    );
    if (productResultOption) {
      event.preventDefault();
      this.applyProductSelection(productResultOption);
      return;
    }

    const productSearchInput = event.target.closest("[data-product-search]");
    if (productSearchInput) {
      this.openProductResults(productSearchInput);
      return;
    }

    const removeNestedButton = event.target.closest("[data-remove-nested-row]");
    if (removeNestedButton) {
      event.preventDefault();
      const nestedRow = removeNestedButton.closest("[data-nested-row]");
      this.removeRecordRow(nestedRow);
      this.refreshAllStructureTotals();
    }
  }

  handleInput(event) {
    const target = event.target;
    if (!(target instanceof HTMLElement)) return;

    if (target.matches("[data-expense-reference-amount]")) {
      this.syncExpenseReferenceRow(target);
    }

    if (target.matches("[data-product-search]")) {
      this.renderProductResults(target);
    }

    if (target.matches("[data-nested-agree-amount]")) {
      this.syncNestedServiceRow(target);
    }

    if (target.matches("[data-structure-description]")) {
      this.refreshStructureSummaryFromInput(target);
    }

    this.refreshAllStructureTotals();
  }

  handleChange(event) {
    const target = event.target;
    if (!(target instanceof HTMLElement)) return;

    if (target.matches("[data-pricing-mode-select]")) {
      this.updatePricingModeVisibility();
      this.updateFixedCurrencyVisibility();
    }

    if (target.matches("[data-fixed-currency-select]")) {
      this.updateFixedCurrencyVisibility();
    }

    if (target.matches("[data-expense-currency-select]")) {
      this.syncExpenseReferenceRow(target);
    }

    if (target.matches("[data-expense-toggle]")) {
      this.updateExpensesVisibility();
    }

    if (target.matches("[data-product-select]")) {
      const row = target.closest("[data-nested-row]");
      this.syncProductSearchRow(row);
    }

    if (target.matches("[data-product-variation-select]")) {
      this.syncProductVariationRow(target.closest("[data-nested-row]"));
    }

    if (target.matches("[data-nested-service-select]")) {
      this.syncNestedServiceRow(target);
    }

    if (target.matches("[data-nested-agree-currency-select]")) {
      this.syncNestedServiceRow(target);
    }

    if (target.matches("[data-structure-active-toggle]")) {
      this.enforceSingleActiveStructure(target);
    }

    this.refreshAllStructureTotals();
  }

  handleDocumentClick(event) {
    if (this.element.contains(event.target)) return;
    this.closeAllProductResults();
  }

  handleKeydown(event) {
    const target = event.target;
    if (!(target instanceof HTMLElement)) return;
    if (!this.isStepLockedInput(target)) return;
    if (!["ArrowUp", "ArrowDown"].includes(event.key)) return;

    event.preventDefault();
  }

  handleWheel(event) {
    const target = event.target;
    if (!(target instanceof HTMLElement)) return;
    if (!this.isStepLockedInput(target)) return;
    if (document.activeElement !== target) return;

    event.preventDefault();
  }

  isStepLockedInput(target) {
    if (!(target instanceof HTMLElement)) return false;

    if (target.matches("[data-product-qty], [data-nested-qty]")) {
      return true;
    }

    return target.matches("[data-fixed-sale-price][data-plain-decimal='true']");
  }

  addExpenseStructure() {
    const container = this.element.querySelector("#service-expense-structures");
    const template = this.element.querySelector(
      "#service-expense-structure-template",
    );
    if (!container || !template) return;

    const html = this.buildTemplateHtml(template);
    if (!html) return;

    container.insertAdjacentHTML("beforeend", html);
    const addedStructure = container.querySelector(
      "[data-structure-item]:last-of-type",
    );
    if (addedStructure) {
      window.MoneyInputMask?.init(addedStructure);
      this.refreshLucideIcons(addedStructure);
      this.initializeStructureCard(addedStructure);
      this.syncAllProductSearchRows(addedStructure);
      this.syncAllExpenseReferenceRows(addedStructure);
      this.syncAllNestedServiceRows(addedStructure);
      this.openStructureModal(addedStructure);
    }

    this.refreshAllStructureTotals();
  }

  addNestedRow(button) {
    const structure = button.closest("[data-structure-item]");
    if (!structure) return;

    const key = button.dataset.addNestedRow;
    if (!key) return;

    const container = structure.querySelector(
      `[data-nested-container="${key}"]`,
    );
    const template = structure.querySelector(`[data-nested-template="${key}"]`);
    if (!container || !template) return;

    const html = this.buildTemplateHtml(template);
    if (!html) return;

    container.insertAdjacentHTML("beforeend", html);
    const addedRow = container.querySelector("[data-nested-row]:last-of-type");
    if (addedRow) {
      window.MoneyInputMask?.init(addedRow);
      this.syncProductSearchRow(addedRow);
      this.syncExpenseReferenceRow(addedRow);
      this.syncNestedServiceRow(addedRow);
    }

    this.refreshAllStructureTotals();
  }

  buildTemplateHtml(template) {
    const placeholder = template.dataset.placeholder;
    const raw = template.innerHTML || "";
    if (!placeholder || !raw) return "";

    const uniqueToken = `${Date.now()}${Math.floor(Math.random() * 1000)}`;
    return raw.split(placeholder).join(uniqueToken);
  }

  removeRecordRow(row) {
    if (!row) return;

    const destroyInput = row.querySelector('input[data-destroy-input="true"]');
    const destroyInputName = String(destroyInput?.name || "");
    const persistedByDataset =
      String(row.dataset.structurePersisted || "") === "true";
    const persistedByNestedDataset =
      String(row.dataset.nestedPersisted || "") === "true";
    const persistedIdInput = row.querySelector(
      'input[type="hidden"][name$="[id]"]',
    );
    const persistedById =
      persistedIdInput &&
      String(persistedIdInput.value || "").trim().length > 0;

    let persistedByPairedId = false;
    if (destroyInputName.endsWith("[_destroy]")) {
      const idInputName = destroyInputName.replace(/\[_destroy\]$/, "[id]");
      const pairedIdInput = Array.from(
        this.element.querySelectorAll('input[type="hidden"][name$="[id]"]'),
      ).find((input) => String(input.name || "") === idInputName);

      persistedByPairedId =
        !!pairedIdInput && String(pairedIdInput.value || "").trim().length > 0;
    }

    const persisted =
      persistedByDataset ||
      persistedByNestedDataset ||
      persistedById ||
      persistedByPairedId;

    if (persisted && destroyInput) {
      destroyInput.value = "1";
      this.closeStructureModal(row);
      this.closeProductResults(row);
      row.style.display = "none";
      return;
    }

    row.remove();
  }

  updatePricingModeVisibility() {
    const pricingModeSelect = this.element.querySelector(
      "[data-pricing-mode-select]",
    );
    const salePriceField = this.element.querySelector(
      "#service-sale-price-field",
    );
    const salePriceInput = this.element.querySelector(
      "[data-fixed-sale-price]",
    );
    const currencyHelp = this.element.querySelector(
      "[data-fixed-currency-help]",
    );
    if (!pricingModeSelect || !salePriceField) return;

    const isFixed = pricingModeSelect.value === "fixed";
    salePriceField.classList.toggle("hidden", !isFixed);
    salePriceField.style.display = isFixed ? "block" : "none";

    if (salePriceInput) {
      salePriceInput.disabled = !isFixed;
    }

    if (currencyHelp) {
      currencyHelp.textContent = isFixed
        ? "Define la moneda de referencia del precio fijo."
        : "Esta moneda se usara para pedir el precio a convenir en ventas.";
    }
  }

  updateFixedCurrencyVisibility() {
    const currencySelect = this.element.querySelector(
      "[data-fixed-currency-select]",
    );
    const salePriceInput = this.element.querySelector(
      "[data-fixed-sale-price]",
    );
    const amountLabel = this.element.querySelector("[data-fixed-amount-label]");
    if (!currencySelect || !salePriceInput || !amountLabel) return;

    const selectedOption =
      currencySelect.options?.[currencySelect.selectedIndex];
    const referenceName =
      String(selectedOption?.dataset?.currencyName || "").trim() ||
      String(currencySelect.value || "").trim() ||
      "Referencia";
    const symbol =
      String(selectedOption?.dataset?.moneySymbol || "").trim() || "$";
    const referenceValue = String(currencySelect.value || "").trim();
    const isUnidadVI =
      referenceName === "Unidad VI" || referenceValue === "Unidad VI";

    amountLabel.textContent = `Monto (${referenceName})`;

    const currentValue = this.parseMoneyInput(salePriceInput);

    if (isUnidadVI) {
      this.configureFixedPriceAsPlainDecimal(salePriceInput, currentValue);
      return;
    }

    this.configureFixedPriceAsMoneyMask(salePriceInput, currentValue, symbol);
  }

  configureFixedPriceAsPlainDecimal(input, value) {
    if (!input) return;

    input.type = "number";
    input.step = "0.01";
    input.min = "0.01";
    input.inputMode = "decimal";
    input.dataset.moneyMask = "false";
    input.dataset.plainDecimal = "true";
    input.dataset.disableNumberSteppers = "true";
    delete input.dataset.moneyCents;
    input.value = this.formatPlainDecimal(value);
  }

  configureFixedPriceAsMoneyMask(input, value, symbol) {
    if (!input) return;

    input.type = "text";
    input.removeAttribute("step");
    input.removeAttribute("min");
    input.removeAttribute("inputmode");
    input.dataset.moneyMask = "true";
    input.dataset.moneySymbol = symbol;
    input.dataset.plainDecimal = "false";
    input.dataset.disableNumberSteppers = "false";

    this.setMoneyInputValue(input, value, symbol);
  }

  updateExpensesVisibility() {
    const toggle = this.element.querySelector("[data-expense-toggle]");
    const wrapper = this.element.querySelector(
      "#service-expense-structures-wrapper",
    );
    const container = this.element.querySelector("#service-expense-structures");
    if (!toggle || !wrapper || !container) return;

    const enabled = toggle.checked;
    wrapper.style.display = enabled ? "block" : "none";

    const fields = wrapper.querySelectorAll("input, select, textarea, button");
    fields.forEach((field) => {
      field.disabled = !enabled;
    });

    if (!enabled) {
      this.closeAllStructureModals();
    }

    if (enabled && this.visibleStructureRows().length === 0) {
      this.addExpenseStructure();
    }
  }

  initializeStructureCards(scope = this.element) {
    if (!scope) return;

    scope.querySelectorAll("[data-structure-item]").forEach((structureRow) => {
      this.initializeStructureCard(structureRow);
    });
  }

  initializeStructureCard(structureRow) {
    if (!structureRow) return;

    this.closeStructureModal(structureRow);
    this.refreshStructureSummaryTitle(structureRow);
  }

  openStructureModal(structureRow) {
    const modal = structureRow?.querySelector("[data-structure-modal]");
    if (!modal) return;

    modal.classList.remove("hidden");
    modal.classList.add("flex");
    document.body.classList.add("overflow-hidden");
  }

  closeStructureModal(structureRow) {
    const modal = structureRow?.querySelector("[data-structure-modal]");
    if (!modal) return;

    modal.classList.add("hidden");
    modal.classList.remove("flex");

    const anyOpen = this.element.querySelector("[data-structure-modal].flex");
    if (!anyOpen) {
      document.body.classList.remove("overflow-hidden");
    }
  }

  closeAllStructureModals() {
    this.element.querySelectorAll("[data-structure-item]").forEach((row) => {
      this.closeStructureModal(row);
    });
  }

  refreshStructureSummaryFromInput(input) {
    const structureRow = input.closest("[data-structure-item]");
    this.refreshStructureSummaryTitle(structureRow);
  }

  refreshStructureSummaryTitle(structureRow) {
    if (!structureRow) return;

    const input = structureRow.querySelector("[data-structure-description]");
    const summary = structureRow.querySelector(
      "[data-structure-summary-title]",
    );
    if (!input || !summary) return;

    const title = String(input.value || "").trim();
    summary.textContent =
      title.length > 0 ? title : "Estructura sin descripcion";
  }

  syncExpenseReferenceRow(source) {
    const row = source?.matches?.("[data-money-pair]")
      ? source
      : source?.closest("[data-money-pair]");
    if (!row) return;

    const currencySelect = row.querySelector("[data-expense-currency-select]");
    const referenceInput = row.querySelector("[data-expense-reference-amount]");
    const usdInput = row.querySelector('[data-money-role="usd"]');
    const bsInput = row.querySelector('[data-money-role="bs"]');
    const usdDisplay = row.querySelector("[data-expense-usd-display]");
    const referenceLabel = row.querySelector("[data-expense-reference-label]");

    if (!currencySelect || !referenceInput || !usdInput || !bsInput) return;

    const selectedOption =
      currencySelect.options?.[currencySelect.selectedIndex];
    const referenceName =
      String(selectedOption?.dataset?.currencyName || "").trim() ||
      String(currencySelect.value || "").trim() ||
      "Referencia";
    const symbol =
      String(selectedOption?.dataset?.moneySymbol || "").trim() || "$";

    if (referenceLabel) {
      referenceLabel.textContent = `Monto ${referenceName}`;
    }

    const referenceValue = this.parseMoneyInput(referenceInput);
    this.setMoneyInputValue(referenceInput, referenceValue, symbol);

    const rateBsRaw = Number.parseFloat(selectedOption?.dataset?.rateBs || "0");
    const rateBs = Number.isFinite(rateBsRaw) && rateBsRaw > 0 ? rateBsRaw : 0;

    const bsValue = this.round(referenceValue * rateBs, 2);
    const usdValue =
      this.bcvRate > 0 ? this.round(bsValue / this.bcvRate, 2) : 0;

    bsInput.value = bsValue.toFixed(2);
    usdInput.value = usdValue.toFixed(2);

    if (usdDisplay) {
      this.setMoneyInputValue(usdDisplay, usdValue, "$");
    }
  }

  syncAllExpenseReferenceRows(scope = this.element) {
    if (!scope) return;

    scope.querySelectorAll("[data-money-pair]").forEach((row) => {
      this.syncExpenseReferenceRow(row);
    });
  }

  syncAllProductSearchRows(scope = this.element) {
    if (!scope) return;

    scope.querySelectorAll("[data-product-select]").forEach((select) => {
      const row = select.closest("[data-nested-row]");
      this.syncProductSearchRow(row);
    });
  }

  syncAllNestedServiceRows(scope = this.element) {
    if (!scope) return;

    scope.querySelectorAll("[data-nested-row]").forEach((row) => {
      if (!row.querySelector("[data-nested-service-select]")) return;
      this.syncNestedServiceRow(row);
    });
  }

  syncNestedServiceRow(source) {
    const row = source?.matches?.("[data-nested-row]")
      ? source
      : source?.closest("[data-nested-row]");
    if (!row) return;

    this.calculateNestedExpenseSubtotal(row);
  }

  calculateNestedExpenseSubtotal(row) {
    const select = row.querySelector("[data-nested-service-select]");
    if (!select) {
      return { subtotalUsd: 0, subtotalBs: 0 };
    }

    const selectedOption = select.options?.[select.selectedIndex];
    const isToAgree =
      String(selectedOption?.dataset?.toAgree || "") === "true" ||
      String(selectedOption?.dataset?.pricingMode || "") === "to_agree";

    this.toggleNestedAgreeFields(row, isToAgree);

    if (isToAgree) {
      return this.calculateNestedAgreeSubtotal(row);
    }

    return this.calculateNestedFixedSubtotal(row, selectedOption);
  }

  toggleNestedAgreeFields(row, isToAgree) {
    const qtyWrapper = row.querySelector("[data-nested-qty-wrapper]");
    const currencyWrapper = row.querySelector(
      "[data-nested-agree-currency-wrapper]",
    );
    const amountWrapper = row.querySelector(
      "[data-nested-agree-amount-wrapper]",
    );
    const currencySelect = row.querySelector(
      "[data-nested-agree-currency-select]",
    );
    const amountInput = row.querySelector("[data-nested-agree-amount]");

    if (qtyWrapper) qtyWrapper.classList.toggle("opacity-70", isToAgree);

    if (currencyWrapper) {
      currencyWrapper.classList.toggle("hidden", !isToAgree);
    }

    if (amountWrapper) {
      amountWrapper.classList.toggle("hidden", !isToAgree);
    }

    if (currencySelect) {
      currencySelect.disabled = !isToAgree;
      if (!currencySelect.value) {
        currencySelect.value = "Bs";
      }
    }

    if (amountInput) {
      amountInput.disabled = !isToAgree;
    }
  }

  calculateNestedAgreeSubtotal(row) {
    const currencySelect = row.querySelector(
      "[data-nested-agree-currency-select]",
    );
    const amountInput = row.querySelector("[data-nested-agree-amount]");
    const amountLabel = row.querySelector("[data-nested-agree-amount-label]");

    if (!currencySelect || !amountInput) {
      return { subtotalUsd: 0, subtotalBs: 0 };
    }

    const selectedCurrencyOption =
      currencySelect.options?.[currencySelect.selectedIndex];
    const referenceName =
      String(selectedCurrencyOption?.dataset?.currencyName || "").trim() ||
      String(currencySelect.value || "").trim() ||
      "Referencia";
    const symbol =
      String(selectedCurrencyOption?.dataset?.moneySymbol || "").trim() || "Bs";

    if (amountLabel) {
      amountLabel.textContent = `Monto ${referenceName}`;
    }

    const amountValue = this.parseMoneyInput(amountInput);
    this.setMoneyInputValue(amountInput, amountValue, symbol);

    const rateBsRaw = Number.parseFloat(
      selectedCurrencyOption?.dataset?.rateBs || "0",
    );
    const rateBs = Number.isFinite(rateBsRaw) && rateBsRaw > 0 ? rateBsRaw : 0;

    const subtotalBs = this.round(amountValue * rateBs, 2);
    const subtotalUsd =
      this.bcvRate > 0 ? this.round(subtotalBs / this.bcvRate, 2) : 0;

    return { subtotalUsd, subtotalBs };
  }

  calculateNestedFixedSubtotal(row, selectedOption) {
    const qtyInput = row.querySelector("[data-nested-qty]");
    const qty = this.parseQuantity(qtyInput?.value, 1);

    const unitUsd =
      Number.parseFloat(selectedOption?.dataset?.priceUsd || "0") || 0;
    const unitBs =
      Number.parseFloat(selectedOption?.dataset?.priceBs || "0") || 0;

    const subtotalUsd = this.round(unitUsd * qty, 2);
    const subtotalBs = this.round(unitBs * qty, 2);

    return { subtotalUsd, subtotalBs };
  }

  syncProductSearchRow(row) {
    if (!row) return;

    const select = row.querySelector("[data-product-select]");
    const searchInput = row.querySelector("[data-product-search]");
    const label = row.querySelector("[data-product-selected-label]");
    if (!select || !searchInput || !label) {
      this.syncProductVariationRow(row);
      return;
    }

    const selectedOption = select.options?.[select.selectedIndex];
    const selectedText =
      selectedOption && String(selectedOption.value || "").length > 0
        ? String(selectedOption.textContent || "").trim()
        : "";

    if (selectedText.length > 0) {
      searchInput.value = selectedText;
      label.textContent = `Seleccionado: ${selectedText}`;
      this.syncProductOldestCostDisplay(row, selectedOption);
      this.syncProductVariationRow(row);
      return;
    }

    searchInput.value = "";
    label.textContent = "Sin producto seleccionado";
    this.syncProductOldestCostDisplay(row, null);
    this.syncProductVariationRow(row);
  }

  syncProductOldestCostDisplay(row, selectedOption) {
    if (!row) return;

    const target = row.querySelector("[data-product-oldest-cost]");
    if (!target) return;

    const usd = Number.parseFloat(
      selectedOption?.dataset?.oldestLotCostUsd || "0",
    );
    const bs = Number.parseFloat(
      selectedOption?.dataset?.oldestLotCostBs || "0",
    );

    const safeUsd = Number.isFinite(usd) && usd > 0 ? usd : 0;
    const safeBs = Number.isFinite(bs) && bs > 0 ? bs : 0;

    target.value = `${this.formatMoney(safeUsd, "$")} · ${this.formatMoney(safeBs, "Bs")}`;
  }

  syncProductVariationRow(row) {
    if (!row) return;

    const productSelect = row.querySelector("[data-product-select]");
    const variationSelect = row.querySelector(
      "[data-product-variation-select]",
    );
    const hint = row.querySelector("[data-product-variation-hint]");
    if (!productSelect || !variationSelect) return;

    const selectedProductOption =
      productSelect.options?.[productSelect.selectedIndex];
    const selectedProductId = String(selectedProductOption?.value || "").trim();
    const variations = this.parseProductVariationsFromOption(
      selectedProductOption,
    );

    const currentValue = String(variationSelect.value || "").trim();
    const currentStillValid = variations.some(
      (variation) => String(variation.id) === currentValue,
    );

    let selectedVariation = currentStillValid ? currentValue : "";
    if (!selectedVariation && variations.length === 1) {
      selectedVariation = String(variations[0].id);
    }

    const variationOptionsHtml = [
      '<option value="">Selecciona variacion</option>',
      ...variations.map(
        (variation) =>
          `<option value="${this.escapeHtml(String(variation.id))}">${this.escapeHtml(variation.description)}</option>`,
      ),
    ].join("");

    variationSelect.innerHTML = variationOptionsHtml;
    variationSelect.value = selectedVariation;
    variationSelect.disabled =
      selectedProductId.length === 0 || variations.length === 0;

    if (!hint) return;

    if (selectedProductId.length === 0) {
      hint.textContent = "Selecciona un producto para ver variaciones.";
      return;
    }

    if (variations.length === 0) {
      hint.textContent = "El producto no tiene variaciones disponibles.";
      return;
    }

    const selectedVariationText = variations.find(
      (variation) =>
        String(variation.id) === String(variationSelect.value || ""),
    )?.description;

    hint.textContent = selectedVariationText
      ? `Variacion seleccionada: ${selectedVariationText}`
      : "Selecciona una variacion para el insumo.";
  }

  parseProductVariationsFromOption(option) {
    const raw = String(option?.dataset?.variations || "").trim();
    if (!raw.length) return [];

    try {
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];

      return parsed
        .map((row) => ({
          id: row?.id,
          description: String(row?.description || "").trim(),
        }))
        .filter(
          (row) =>
            String(row.id || "").trim().length > 0 &&
            row.description.length > 0,
        );
    } catch (_error) {
      return [];
    }
  }

  openProductResults(searchInput) {
    if (!searchInput) return;
    this.renderProductResults(searchInput);
  }

  renderProductResults(searchInput) {
    const row = searchInput.closest("[data-nested-row]");
    const select = row?.querySelector("[data-product-select]");
    const resultsBox = row?.querySelector("[data-product-results]");
    if (!row || !select || !resultsBox) return;

    const query = this.normalizeText(searchInput.value);
    const selectedValue = String(select.value || "");
    const options = Array.from(select.options || []).filter(
      (option, index) => index > 0,
    );

    const filtered =
      query.length === 0
        ? options
        : options.filter((option) => {
            const text = this.normalizeText(option.textContent);
            return text.includes(query);
          });

    const visibleOptions = filtered.slice(0, 25);

    if (visibleOptions.length === 0) {
      resultsBox.innerHTML =
        '<p class="px-3 py-2 text-xs text-slate-500">Sin resultados</p>';
      resultsBox.classList.remove("hidden");
      return;
    }

    resultsBox.innerHTML = visibleOptions
      .map((option) => {
        const value = String(option.value || "");
        const text = this.escapeHtml(String(option.textContent || "").trim());
        const selectedBadge =
          value === selectedValue
            ? '<span class="rounded-full bg-emerald-100 px-2 py-0.5 text-[10px] font-semibold text-emerald-700">Seleccionado</span>'
            : "";

        return `
          <button type="button"
                  class="flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm text-slate-700 hover:bg-sky-50"
                  data-product-result-option="${this.escapeHtml(value)}">
            <span class="truncate">${text}</span>
            ${selectedBadge}
          </button>
        `;
      })
      .join("");

    resultsBox.classList.remove("hidden");
  }

  applyProductSelection(resultOption) {
    const row = resultOption.closest(
      "[data-nested-row], [data-print-material-surcharge-row], [data-lamination-material-row]",
    );
    const select = row?.querySelector("[data-product-select]");
    const searchInput = row?.querySelector("[data-product-search]");
    const label = row?.querySelector("[data-product-selected-label]");
    const resultsBox = row?.querySelector("[data-product-results]");
    if (!row || !select || !searchInput || !label || !resultsBox) return;

    const selectedValue = String(
      resultOption.dataset.productResultOption || "",
    );
    select.value = selectedValue;

    const selectedOption = Array.from(select.options || []).find(
      (option) => String(option.value || "") === selectedValue,
    );

    const selectedText = String(selectedOption?.textContent || "").trim();
    searchInput.value = selectedText;
    label.textContent =
      selectedText.length > 0
        ? `Seleccionado: ${selectedText}`
        : "Sin producto seleccionado";

    resultsBox.classList.add("hidden");
    select.dispatchEvent(new Event("change", { bubbles: true }));
  }

  closeProductResults(row) {
    if (!row) return;
    const resultsBox = row.querySelector("[data-product-results]");
    if (resultsBox) resultsBox.classList.add("hidden");
  }

  closeAllProductResults() {
    this.element
      .querySelectorAll("[data-product-results]")
      .forEach((resultsBox) => {
        resultsBox.classList.add("hidden");
      });
  }

  refreshAllStructureTotals() {
    this.syncAllExpenseReferenceRows();

    this.visibleStructureRows().forEach((row) =>
      this.refreshStructureTotals(row),
    );
  }

  refreshStructureTotals(structureRow) {
    if (!structureRow) return;

    let totalUsd = 0;
    let totalBs = 0;

    this.visibleNestedRows(structureRow, "manager_expense").forEach((row) => {
      totalUsd += this.parseMoneyInput(
        row.querySelector('[data-money-role="usd"]'),
      );
      totalBs += this.parseMoneyInput(
        row.querySelector('[data-money-role="bs"]'),
      );
    });

    this.visibleNestedRows(structureRow, "variable_expense").forEach((row) => {
      totalUsd += this.parseMoneyInput(
        row.querySelector('[data-money-role="usd"]'),
      );
      totalBs += this.parseMoneyInput(
        row.querySelector('[data-money-role="bs"]'),
      );
    });

    this.visibleNestedRows(structureRow, "nested_expense").forEach((row) => {
      const { subtotalUsd, subtotalBs } =
        this.calculateNestedExpenseSubtotal(row);

      totalUsd += subtotalUsd;
      totalBs += subtotalBs;

      this.renderLineTotals(row, subtotalUsd, subtotalBs);
    });

    this.visibleNestedRows(structureRow, "product_expense").forEach((row) => {
      const select = row.querySelector("[data-product-select]");
      const qtyInput = row.querySelector("[data-product-qty]");
      const qty = this.parseQuantity(qtyInput?.value, 1);

      const selectedOption = select?.options?.[select.selectedIndex];
      const unitUsd =
        Number.parseFloat(selectedOption?.dataset?.priceUsd || "0") || 0;
      const unitBs =
        Number.parseFloat(selectedOption?.dataset?.priceBs || "0") || 0;

      const subtotalUsd = this.round(unitUsd * qty, 2);
      const subtotalBs = this.round(unitBs * qty, 2);

      totalUsd += subtotalUsd;
      totalBs += subtotalBs;

      this.renderLineTotals(row, subtotalUsd, subtotalBs);
    });

    const usdEl = structureRow.querySelector("[data-structure-total-usd]");
    const bsEl = structureRow.querySelector("[data-structure-total-bs]");
    if (usdEl) usdEl.textContent = this.formatMoney(totalUsd, "$");
    if (bsEl) bsEl.textContent = this.formatMoney(totalBs, "Bs");

    this.refreshStructureSummaryTitle(structureRow);
  }

  renderLineTotals(row, subtotalUsd, subtotalBs) {
    const usdEl = row.querySelector("[data-line-total-usd]");
    const bsEl = row.querySelector("[data-line-total-bs]");

    this.writeMoneyDisplay(usdEl, subtotalUsd, "$");
    this.writeMoneyDisplay(bsEl, subtotalBs, "Bs");
  }

  writeMoneyDisplay(target, amount, symbol) {
    if (!target) return;

    if (target instanceof HTMLInputElement) {
      this.setMoneyInputValue(target, amount, symbol);
      return;
    }

    target.textContent = this.formatMoney(amount, symbol);
  }

  visibleStructureRows() {
    return Array.from(
      this.element.querySelectorAll("[data-structure-item]"),
    ).filter((row) => this.isVisibleRow(row));
  }

  enforceSingleActiveStructure(input) {
    if (!(input instanceof HTMLInputElement)) return;
    if (!input.checked) return;

    this.visibleStructureRows().forEach((row) => {
      const toggle = row.querySelector("[data-structure-active-toggle]");
      if (!(toggle instanceof HTMLInputElement)) return;
      if (toggle === input) return;

      toggle.checked = false;
    });
  }

  visibleNestedRows(structureRow, key) {
    const container = structureRow.querySelector(
      `[data-nested-container="${key}"]`,
    );
    if (!container) return [];

    return Array.from(container.querySelectorAll("[data-nested-row]")).filter(
      (row) => this.isVisibleRow(row),
    );
  }

  isVisibleRow(row) {
    if (!row) return false;

    const destroyInput = row.querySelector('input[data-destroy-input="true"]');
    const markedForDestroy =
      destroyInput && String(destroyInput.value || "") === "1";
    if (markedForDestroy) return false;

    return row.style.display !== "none";
  }

  parseRate(value) {
    const parsed = Number.parseFloat(String(value || "").replace(",", "."));
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  }

  parseMoneyInput(input) {
    if (!input) return 0;
    if (window.MoneyInputMask?.parseValue)
      return window.MoneyInputMask.parseValue(input) || 0;

    const raw = String(input.value || "")
      .replace(/\s/g, "")
      .replace(/[^\d.,-]/g, "");
    const normalized = raw.includes(",")
      ? raw.replace(/\./g, "").replace(",", ".")
      : raw;
    const parsed = Number.parseFloat(normalized);
    return Number.isFinite(parsed) ? Math.max(parsed, 0) : 0;
  }

  setMoneyInputValue(input, value, symbol) {
    if (!input) return;

    if (window.MoneyInputMask?.setValue) {
      window.MoneyInputMask.setValue(input, value, symbol);
      return;
    }

    input.value = this.formatMoney(value, symbol);
  }

  parseQuantity(rawValue, fallback = 0) {
    const parsed = Number.parseFloat(String(rawValue || "").replace(",", "."));
    if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
    return parsed;
  }

  formatMoney(value, symbol) {
    const amount = Number.isFinite(Number(value))
      ? Math.max(Number(value), 0)
      : 0;
    const formatted = amount.toLocaleString("es-VE", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
    return `${symbol} ${formatted}`;
  }

  formatPlainDecimal(value) {
    const amount = Number.isFinite(Number(value))
      ? Math.max(Number(value), 0)
      : 0;

    if (Number.isInteger(amount)) return String(amount);

    return String(this.round(amount, 2)).replace(/\.0+$/, "");
  }

  normalizeText(value) {
    return String(value || "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .trim();
  }

  round(value, precision = 2) {
    const factor = 10 ** precision;
    return Math.round((Number(value) || 0) * factor) / factor;
  }

  escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  refreshLucideIcons(scope = this.element) {
    if (!scope?.querySelector?.("[data-lucide]")) return;
    if (!window.lucide || typeof window.lucide.createIcons !== "function") {
      return;
    }

    window.lucide.createIcons();
  }
}
