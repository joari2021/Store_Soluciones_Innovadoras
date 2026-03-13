import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { tasaDolar: Number };

  connect() {
    const tasaDolar =
      Number(this.hasTasaDolarValue ? this.tasaDolarValue : 0) || 0;

    const precioVentaUSD = document.getElementById("producto_precio_venta_usd");
    const precioVentaBs = document.getElementById("precio_venta_bs_visual");
    const costoUnidVisual = document.getElementById("costo_unid_visual");
    const porcentajeGanancia = document.getElementById(
      "producto_porcentaje_ganancia",
    );
    let isSyncing = false;

    const parseLocalizedNumber = (rawValue) => {
      const compact = String(rawValue || "").replace(/\s/g, "");
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

    const getNumericValue = (input) => parseLocalizedNumber(input?.value || "");

    const setLocalizedValue = (input, value) => {
      if (!input) return;
      input.value = formatLocalizedNumber(value);
    };

    const bindLocalizedInput = (input) => {
      if (!input) return;

      input.addEventListener("blur", () => {
        input.value = formatLocalizedNumber(parseLocalizedNumber(input.value));
      });

      if (input.value) {
        input.value = formatLocalizedNumber(parseLocalizedNumber(input.value));
      }
    };

    const bindLotCostSelectors = () => {
      const selectors = document.querySelectorAll(".lot-cost-selector");
      if (!selectors.length || !costoUnidVisual) return;

      const applyLotCost = (selector) => {
        if (!selector) return;
        const unitCost = parseLocalizedNumber(selector.dataset.unitCost);
        costoUnidVisual.value = formatLocalizedNumber(unitCost);

        if (getNumericValue(precioVentaUSD) > 0) return syncBySource("usd");
        if (getNumericValue(precioVentaBs) > 0) return syncBySource("bs");
        syncBySource("ganancia");
      };

      selectors.forEach((selector) => {
        selector.addEventListener("change", () => {
          if (!selector.checked || selector.disabled) return;
          applyLotCost(selector);
        });
      });

      const selectedByDefault = Array.from(selectors).find(
        (selector) => !selector.disabled,
      );

      if (selectedByDefault) {
        selectedByDefault.checked = true;
        applyLotCost(selectedByDefault);
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
      });
    };

    bindLocalizedInput(precioVentaUSD);
    bindLocalizedInput(precioVentaBs);
    bindLocalizedInput(costoUnidVisual);
    bindLocalizedInput(porcentajeGanancia);
    bindLotCostSelectors();

    syncBySource("usd");

    if (precioVentaUSD) {
      precioVentaUSD.addEventListener("input", () => syncBySource("usd"));
      precioVentaUSD.addEventListener("blur", () => syncBySource("usd"));
    }

    if (precioVentaBs) {
      precioVentaBs.addEventListener("input", () => syncBySource("bs"));
      precioVentaBs.addEventListener("blur", () => syncBySource("bs"));
    }

    if (porcentajeGanancia) {
      porcentajeGanancia.addEventListener("input", () =>
        syncBySource("ganancia"),
      );
      porcentajeGanancia.addEventListener("blur", () =>
        syncBySource("ganancia"),
      );
    }
  }
}
