import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { tasaDolar: Number, persisted: Boolean };

  connect() {
    const tasaDolar =
      Number(this.hasTasaDolarValue ? this.tasaDolarValue : 0) || 0;
    const isPersisted = this.hasPersistedValue ? this.persistedValue : false;

    const precioVentaUSD = document.getElementById("producto_precio_venta_usd");
    const precioVentaBs = document.getElementById("precio_venta_bs_visual");
    const costoUnidVisual = document.getElementById("costo_unid_visual");
    const porcentajeGanancia = document.getElementById(
      "producto_porcentaje_ganancia",
    );
    const porcentajeGananciaFija = document.getElementById(
      "producto_profit_margin_preset_id",
    );
    const moneyMask = window.MoneyInputMask;
    let isSyncing = false;
    let refreshStoredMismatchState = () => {};

    const parseLocalizedNumber = (rawValue) => {
      const compact = String(rawValue || "")
        .replace(/\s/g, "")
        .replace(/[^\d.,-]/g, "");
      let normalized = compact;

      if (compact.includes(",")) {
        normalized = compact.replace(/\./g, "").replace(",", ".");
      } else if (/^\d{1,3}(\.\d{3})+$/.test(compact)) {
        normalized = compact.replace(/\./g, "");
      }

      const parsed = Number.parseFloat(normalized);
      return Number.isFinite(parsed) ? parsed : 0;
    };

    const formatLocalizedNumber = (value) => {
      if (!Number.isFinite(value)) return "0,00";

      return value.toLocaleString("es-VE", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
    };

    const roundToTwo = (value) => {
      const parsed = Number(value);
      if (!Number.isFinite(parsed)) return 0;
      return Math.round(parsed * 100) / 100;
    };

    const hasFixedGainSelected = () =>
      Boolean(
        porcentajeGananciaFija &&
        String(porcentajeGananciaFija.value || "").trim() !== "",
      );

    const selectedFixedGainPercentage = () => {
      if (!hasFixedGainSelected()) return null;

      const option = porcentajeGananciaFija.selectedOptions?.[0];
      const raw = option?.dataset?.fixedPercentage || option?.textContent || "";
      const parsed = parseLocalizedNumber(raw);
      return Number.isFinite(parsed) ? parsed : null;
    };

    const getNumericValue = (input) => parseLocalizedNumber(input?.value || "");

    const setLocalizedValue = (input, value) => {
      if (!input) return;
      if (input.dataset.moneyMask === "true" && moneyMask?.setValue) {
        const symbol = input.dataset.moneySymbol || "$";
        moneyMask.setValue(input, value, symbol);
        return;
      }

      input.value = formatLocalizedNumber(value);
    };

    const bindLocalizedInput = (input) => {
      if (!input) return;

      if (input.dataset.moneyMask === "true" && moneyMask?.setValue) {
        const symbol = input.dataset.moneySymbol || "$";
        moneyMask.setValue(input, parseLocalizedNumber(input.value), symbol);
        return;
      }

      input.addEventListener("blur", () => {
        input.value = formatLocalizedNumber(parseLocalizedNumber(input.value));
      });

      if (input.value) {
        input.value = formatLocalizedNumber(parseLocalizedNumber(input.value));
      }
    };

    const bindLotCostSelectors = (options = {}) => {
      const { syncOnChange = true, syncOnInitial = true } = options;
      const selectors = document.querySelectorAll(".lot-cost-selector");
      if (!selectors.length || !costoUnidVisual) return;

      const applyLotCost = (selector, applyOptions = {}) => {
        const { sync = true } = applyOptions;
        if (!selector) return;
        const unitCost = parseLocalizedNumber(selector.dataset.unitCost);
        setLocalizedValue(costoUnidVisual, unitCost);

        if (!sync) {
          refreshStoredMismatchState();
          return;
        }

        if (hasFixedGainSelected()) return syncBySource("fija");

        if (getNumericValue(precioVentaUSD) > 0) return syncBySource("usd");
        if (getNumericValue(precioVentaBs) > 0) return syncBySource("bs");
        syncBySource("ganancia");
        refreshStoredMismatchState();
      };

      selectors.forEach((selector) => {
        selector.addEventListener("change", () => {
          if (!selector.checked || selector.disabled) return;
          applyLotCost(selector, { sync: syncOnChange });
        });
      });

      const enabledSelectors = Array.from(selectors).filter(
        (selector) => !selector.disabled,
      );

      const selectedByDefault = enabledSelectors.reduce(
        (highestCostSelector, currentSelector) => {
          if (!highestCostSelector) return currentSelector;

          const currentCost = parseLocalizedNumber(
            currentSelector.dataset.unitCost,
          );
          const highestCost = parseLocalizedNumber(
            highestCostSelector.dataset.unitCost,
          );

          if (currentCost === highestCost) {
            const currentTimestamp = Number.parseInt(
              currentSelector.dataset.lotTimestamp || "0",
              10,
            );
            const highestTimestamp = Number.parseInt(
              highestCostSelector.dataset.lotTimestamp || "0",
              10,
            );

            return currentTimestamp > highestTimestamp
              ? currentSelector
              : highestCostSelector;
          }

          return currentCost > highestCost
            ? currentSelector
            : highestCostSelector;
        },
        null,
      );

      if (selectedByDefault) {
        selectedByDefault.checked = true;
        applyLotCost(selectedByDefault, { sync: syncOnInitial });
      }
    };

    const calcularGananciaPorcentaje = (ventaUsd, costoUnid) => {
      if (costoUnid <= 0) return 0;
      return ((ventaUsd - costoUnid) / costoUnid) * 100;
    };

    const syncFromUsd = () => {
      const ventaUsd = getNumericValue(precioVentaUSD);
      const costoUnid = getNumericValue(costoUnidVisual);
      const ventaBs = tasaDolar > 0 ? ventaUsd * tasaDolar : 0;
      const ganancia = calcularGananciaPorcentaje(ventaUsd, costoUnid);

      setLocalizedValue(precioVentaBs, ventaBs);
      setLocalizedValue(porcentajeGanancia, ganancia);
    };

    const syncFromBs = () => {
      const ventaBs = getNumericValue(precioVentaBs);
      const costoUnid = getNumericValue(costoUnidVisual);
      const ventaUsd = tasaDolar > 0 ? ventaBs / tasaDolar : 0;
      const ganancia = calcularGananciaPorcentaje(ventaUsd, costoUnid);

      setLocalizedValue(precioVentaUSD, ventaUsd);
      setLocalizedValue(porcentajeGanancia, ganancia);
    };

    const syncFromGanancia = () => {
      const costoUnid = getNumericValue(costoUnidVisual);
      const ganancia = getNumericValue(porcentajeGanancia);
      const ventaUsd = costoUnid > 0 ? costoUnid * (1 + ganancia / 100) : 0;
      const ventaBs = tasaDolar > 0 ? ventaUsd * tasaDolar : 0;

      setLocalizedValue(precioVentaUSD, ventaUsd);
      setLocalizedValue(precioVentaBs, ventaBs);
    };

    const syncFromFixedGain = () => {
      const costoUnid = getNumericValue(costoUnidVisual);
      const fixedGain = selectedFixedGainPercentage();

      if (!(fixedGain >= 0) || !(costoUnid > 0)) {
        setLocalizedValue(precioVentaUSD, 0);
        setLocalizedValue(precioVentaBs, 0);
        setLocalizedValue(porcentajeGanancia, 0);
        return;
      }

      const ventaUsdFinal = roundToTwo(costoUnid * (1 + fixedGain / 100));
      const ventaBsFinal = roundToTwo(ventaUsdFinal * tasaDolar);
      const gananciaReal = calcularGananciaPorcentaje(ventaUsdFinal, costoUnid);

      setLocalizedValue(precioVentaUSD, ventaUsdFinal);
      setLocalizedValue(precioVentaBs, ventaBsFinal);
      setLocalizedValue(porcentajeGanancia, gananciaReal);
    };

    const withSyncLock = (callback) => {
      if (isSyncing) return;
      isSyncing = true;
      callback();
      isSyncing = false;
    };

    const syncBySource = (source) => {
      withSyncLock(() => {
        if (source === "usd") syncFromUsd();
        if (source === "bs") syncFromBs();
        if (source === "ganancia") syncFromGanancia();
        if (source === "fija") syncFromFixedGain();
      });
    };

    const gananciaRealStatusBox = document.getElementById(
      "ganancia-real-status",
    );
    const gananciaRealMessage = document.getElementById(
      "ganancia-real-message",
    );
    const gananciaRealToggleBtn = document.getElementById(
      "ganancia-real-toggle-btn",
    );

    const originalValues = {
      precioUsd: getNumericValue(precioVentaUSD),
      precioBs: getNumericValue(precioVentaBs),
      gananciaReal: getNumericValue(porcentajeGanancia),
      fixedPresetId: porcentajeGananciaFija
        ? String(porcentajeGananciaFija.value || "")
        : "",
    };

    let hasStoredRealPercentageMismatch = false;
    let usingCalculatedRealPercentage = false;
    let hasManualFieldChanges = false;

    const updateGananciaRealStatusUI = () => {
      if (
        !gananciaRealStatusBox ||
        !gananciaRealMessage ||
        !gananciaRealToggleBtn
      )
        return;

      gananciaRealStatusBox.classList.remove(
        "hidden",
        "border-amber-200",
        "bg-amber-50",
        "border-emerald-200",
        "bg-emerald-50",
        "border-slate-200",
        "bg-slate-50",
      );
      gananciaRealMessage.classList.remove(
        "text-amber-700",
        "text-emerald-700",
        "text-slate-700",
      );
      gananciaRealToggleBtn.classList.remove(
        "border-amber-300",
        "bg-amber-100",
        "text-amber-700",
        "hover:bg-amber-200",
        "border-emerald-300",
        "bg-emerald-100",
        "text-emerald-700",
        "hover:bg-emerald-200",
        "border-slate-300",
        "bg-white",
        "text-slate-700",
        "hover:bg-slate-100",
      );

      if (isPersisted && hasManualFieldChanges) {
        gananciaRealStatusBox.classList.add("border-slate-200", "bg-slate-50");
        gananciaRealMessage.classList.add("text-slate-700");
        gananciaRealMessage.textContent =
          "Detectamos cambios manuales en los campos de ganancia/precio.";
        gananciaRealToggleBtn.textContent = "Revertir cambios";
        gananciaRealToggleBtn.classList.add(
          "border-slate-300",
          "bg-white",
          "text-slate-700",
          "hover:bg-slate-100",
        );
        return;
      }

      if (!isPersisted || !hasStoredRealPercentageMismatch) {
        gananciaRealStatusBox.classList.add("hidden");
        return;
      }

      if (usingCalculatedRealPercentage) {
        gananciaRealStatusBox.classList.add(
          "border-emerald-200",
          "bg-emerald-50",
        );
        gananciaRealMessage.classList.add("text-emerald-700");
        gananciaRealMessage.textContent =
          "Ya se esta usando el porcentaje real calculado con base en el costo unitario mostrado.";
        gananciaRealToggleBtn.textContent = "Revertir valores guardados";
        gananciaRealToggleBtn.classList.add(
          "border-emerald-300",
          "bg-emerald-100",
          "text-emerald-700",
          "hover:bg-emerald-200",
        );
        return;
      }

      gananciaRealStatusBox.classList.add("border-amber-200", "bg-amber-50");
      gananciaRealMessage.classList.add("text-amber-700");
      gananciaRealMessage.textContent =
        "El porcentaje real guardado no coincide con el valor calculado segun el costo unitario mostrado.";
      gananciaRealToggleBtn.textContent = "Calcular porcentaje real";
      gananciaRealToggleBtn.classList.add(
        "border-amber-300",
        "bg-amber-100",
        "text-amber-700",
        "hover:bg-amber-200",
      );
    };

    const calculateStoredMismatch = () => {
      const costoUnid = getNumericValue(costoUnidVisual);
      if (!(costoUnid > 0) || !(originalValues.precioUsd > 0)) return false;

      const gananciaEsperada = calcularGananciaPorcentaje(
        originalValues.precioUsd,
        costoUnid,
      );

      return Math.abs(gananciaEsperada - originalValues.gananciaReal) > 0.05;
    };

    refreshStoredMismatchState = () => {
      hasStoredRealPercentageMismatch = calculateStoredMismatch();
      if (!hasStoredRealPercentageMismatch) {
        usingCalculatedRealPercentage = false;
      }
      updateGananciaRealStatusUI();
    };

    const restoreStoredValues = () => {
      if (porcentajeGananciaFija) {
        porcentajeGananciaFija.value = originalValues.fixedPresetId;
      }

      setLocalizedValue(precioVentaUSD, originalValues.precioUsd);
      const restoredBs =
        tasaDolar > 0 ? roundToTwo(originalValues.precioUsd * tasaDolar) : 0;
      setLocalizedValue(precioVentaBs, restoredBs);
      setLocalizedValue(porcentajeGanancia, originalValues.gananciaReal);

      hasManualFieldChanges = false;
      usingCalculatedRealPercentage = false;
      refreshStoredMismatchState();
    };

    const calculateAndApplyRealPercentage = () => {
      if (hasFixedGainSelected()) {
        syncBySource("fija");
      } else if (getNumericValue(precioVentaUSD) > 0) {
        syncBySource("usd");
      } else if (getNumericValue(precioVentaBs) > 0) {
        syncBySource("bs");
      } else {
        syncBySource("ganancia");
      }

      hasManualFieldChanges = false;
      usingCalculatedRealPercentage = true;
      updateGananciaRealStatusUI();
    };

    const setManualFieldChanges = () => {
      if (!isPersisted) return;

      hasManualFieldChanges = true;
      usingCalculatedRealPercentage = false;
      updateGananciaRealStatusUI();
    };

    const syncBsFromCurrentUsd = () => {
      if (!precioVentaUSD || !precioVentaBs) return;

      const rawUsd = String(precioVentaUSD.value || "").trim();
      if (rawUsd === "") return;

      const ventaUsd = getNumericValue(precioVentaUSD);
      const ventaBs = tasaDolar > 0 ? ventaUsd * tasaDolar : 0;
      setLocalizedValue(precioVentaBs, ventaBs);
    };

    moneyMask?.init(this.element);
    bindLocalizedInput(precioVentaUSD);
    bindLocalizedInput(precioVentaBs);
    bindLocalizedInput(costoUnidVisual);
    bindLocalizedInput(porcentajeGanancia);
    bindLotCostSelectors({
      syncOnChange: !isPersisted,
      syncOnInitial: !isPersisted,
    });
    syncBsFromCurrentUsd();

    if (gananciaRealToggleBtn) {
      gananciaRealToggleBtn.addEventListener("click", () => {
        if (hasManualFieldChanges || usingCalculatedRealPercentage) {
          restoreStoredValues();
          return;
        }

        calculateAndApplyRealPercentage();
      });
    }

    if (porcentajeGananciaFija) {
      porcentajeGananciaFija.addEventListener("change", () => {
        setManualFieldChanges();

        if (hasFixedGainSelected()) {
          syncBySource("fija");
          return;
        }

        if (getNumericValue(precioVentaUSD) > 0) return syncBySource("usd");
        if (getNumericValue(precioVentaBs) > 0) return syncBySource("bs");
        syncBySource("ganancia");
      });
    }

    if (isPersisted) {
      refreshStoredMismatchState();
    } else if (hasFixedGainSelected()) {
      syncBySource("fija");
    } else {
      syncBySource("usd");
    }

    if (precioVentaUSD) {
      precioVentaUSD.addEventListener("input", () => {
        setManualFieldChanges();
        syncBySource("usd");
      });
      precioVentaUSD.addEventListener("blur", () => syncBySource("usd"));
    }

    if (precioVentaBs) {
      precioVentaBs.addEventListener("input", () => {
        setManualFieldChanges();
        syncBySource("bs");
      });
      precioVentaBs.addEventListener("blur", () => syncBySource("bs"));
    }

    if (porcentajeGanancia) {
      porcentajeGanancia.addEventListener("input", () => {
        setManualFieldChanges();
        syncBySource("ganancia");
      });
      porcentajeGanancia.addEventListener("blur", () =>
        syncBySource("ganancia"),
      );
    }

    if (this.element?.dataset?.formProductoSubmitBound !== "true") {
      this.element.dataset.formProductoSubmitBound = "true";
      this.element.addEventListener("submit", () => {
        [precioVentaUSD, precioVentaBs, porcentajeGanancia].forEach((input) => {
          if (!input) return;
          const numeric = getNumericValue(input);
          input.value = numeric.toFixed(2);
        });
      });
    }
  }
}
