import "@hotwired/turbo-rails";
import "controllers";
import "plugins/money_input_mask";
import "izitoast";
import Swal from "sweetalert2";
window.Swal = Swal;

const iziToast = window.iziToast;

const normalizeToastType = (value) => {
  const normalized = String(value || "").toLowerCase();

  if (["success", "notice", "ok"].includes(normalized)) return "success";
  if (["error", "danger", "alert", "fail"].includes(normalized)) return "error";
  if (["warning", "warn"].includes(normalized)) return "warning";
  return "info";
};

const toastTitleByType = {
  success: "Éxito",
  error: "Error",
  warning: "Atención",
  info: "Información",
};

const baseToastOptions = {
  position: "topRight",
  timeout: 4500,
  closeOnEscape: true,
  closeOnClick: true,
  close: true,
  progressBar: true,
  pauseOnHover: true,
  drag: true,
  maxWidth: 420,
  zindex: 10050,
};

const showAppToast = (type, message, customOptions = {}) => {
  const cleanMessage = String(message || "").trim();
  if (!cleanMessage) return;

  const toastType = normalizeToastType(type);
  const toastOptions = {
    ...baseToastOptions,
    title: toastTitleByType[toastType],
    message: cleanMessage,
    ...customOptions,
  };

  if (iziToast && typeof iziToast[toastType] === "function") {
    iziToast[toastType](toastOptions);
    return;
  }

  if (window.Swal) {
    window.Swal.fire({
      toast: true,
      icon: toastType,
      title: cleanMessage,
      position: "top-end",
      timer: Number(toastOptions.timeout) || 4500,
      showConfirmButton: false,
      target: "body",
      heightAuto: false,
    });
    return;
  }

  console.log(`[${toastType.toUpperCase()}] ${cleanMessage}`);
};

const displayFlashToasts = () => {
  const flashNodes = document.querySelectorAll(".js-flash-toast");
  flashNodes.forEach((node) => {
    if (node.dataset.toastRendered === "true") return;

    const message = node.dataset.toastMessage;
    const type = node.dataset.toastType;
    showAppToast(type, message);

    node.dataset.toastRendered = "true";
    node.remove();
  });
};

const displayBalanceInsufficientAlerts = () => {
  const nodes = document.querySelectorAll(
    "[data-balance-insufficient-alert='true']",
  );

  nodes.forEach((node) => {
    if (node.dataset.balanceAlertRendered === "true") return;

    const message = String(
      node.dataset.balanceInsufficientMessage || "",
    ).trim();
    if (!message) return;

    if (window.Swal) {
      window.Swal.fire({
        icon: "warning",
        title: "Saldo insuficiente",
        text: message,
        confirmButtonText: "Entendido",
        target: "body",
        heightAuto: false,
      });
    } else {
      showAppToast("warning", message, { title: "Saldo insuficiente" });
    }

    node.dataset.balanceAlertRendered = "true";
  });
};

window.AppToast = {
  show: showAppToast,
  success: (message, options = {}) => showAppToast("success", message, options),
  error: (message, options = {}) => showAppToast("error", message, options),
  warning: (message, options = {}) => showAppToast("warning", message, options),
  info: (message, options = {}) => showAppToast("info", message, options),
};

const parseDisplayDate = (value) => {
  if (!value) return null;

  const normalized = String(value).trim();

  const isoMatch = normalized.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (isoMatch) {
    const year = Number(isoMatch[1]);
    const month = Number(isoMatch[2]);
    const day = Number(isoMatch[3]);
    const date = new Date(year, month - 1, day);

    if (
      date.getFullYear() !== year ||
      date.getMonth() !== month - 1 ||
      date.getDate() !== day
    ) {
      return null;
    }

    return date;
  }

  const match = normalized.match(/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/);
  if (!match) return null;

  const day = Number(match[1]);
  const month = Number(match[2]);
  const year = Number(match[3]);
  const date = new Date(year, month - 1, day);

  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    return null;
  }

  return date;
};

const padDatePart = (value) => String(value).padStart(2, "0");

const formatDisplayDate = (date) => {
  if (!(date instanceof Date)) return "";
  return `${padDatePart(date.getDate())}-${padDatePart(date.getMonth() + 1)}-${date.getFullYear()}`;
};

const formatIsoDate = (date) => {
  if (!(date instanceof Date)) return "";
  return `${date.getFullYear()}-${padDatePart(date.getMonth() + 1)}-${padDatePart(date.getDate())}`;
};

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
  return Number.isFinite(parsed) ? Math.max(parsed, 0) : 0;
};

const formatBsAmount = (value) => {
  const numeric = Number.isFinite(Number(value))
    ? Math.max(Number(value), 0)
    : 0;
  return `Bs ${numeric.toLocaleString("es-VE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
};

const setFacturaRateDisplay = (rateInput, value) => {
  if (!rateInput) return;
  rateInput.value = formatBsAmount(parseLocalizedNumber(value));
};

const notifyRateInputChanged = (rateInput) => {
  if (!rateInput) return;
  rateInput.dispatchEvent(new Event("input", { bubbles: true }));
  rateInput.dispatchEvent(new Event("change", { bubbles: true }));
};

const updateFacturaRateByDate = (input, selectedDate) => {
  if (!(selectedDate instanceof Date)) return;
  if (input.name !== "purchase_invoice[fecha_emision]") return;

  const tasaInput = document.getElementById("purchase_invoice_tasa_dolar");
  if (!tasaInput) return;

  const isoDate = formatIsoDate(selectedDate);

  fetch(`/tasa_cambios/bcv_por_fecha?fecha=${encodeURIComponent(isoDate)}`)
    .then(async (response) => {
      const data = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(
          data.error ||
            "No existe una tasa del dolar con esa fecha, por favor registrela manualmente",
        );
      }

      if (typeof data.valor === "number" || typeof data.valor === "string") {
        setFacturaRateDisplay(tasaInput, data.valor);
        notifyRateInputChanged(tasaInput);
      }
    })
    .catch(() => {
      setFacturaRateDisplay(tasaInput, 0);
      notifyRateInputChanged(tasaInput);

      showAppToast(
        "warning",
        "No existe una tasa del dolar con esa fecha, por favor registrela manualmente",
        { title: "Tasa no encontrada" },
      );
    });
};

const normalizeDatepickerHeaderText = () => {
  const headers = document.querySelectorAll(
    "#materialize-datepicker-portal .datepicker-date-display .date-text",
  );

  headers.forEach((header) => {
    const currentText = header.textContent?.trim();
    if (!currentText) return;

    const match = currentText.match(
      /^([^,]+),\s*([A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+)\s+(\d{1,2})$/,
    );
    if (!match) return;

    const weekday = match[1];
    const month = match[2];
    const day = match[3];
    header.textContent = `${weekday}, ${day} ${month}`;
  });
};

const ensureTodayButton = (input) => {
  const instance = window.M?.Datepicker?.getInstance(input);
  if (!instance?.modalEl) return;

  const footer = instance.modalEl.querySelector(".datepicker-footer");
  if (!footer) return;

  let todayButton = footer.querySelector(".datepicker-today");
  if (!todayButton) {
    todayButton = document.createElement("button");
    todayButton.type = "button";
    todayButton.className = "btn-flat datepicker-today";
    todayButton.textContent = "Hoy";
    footer.insertBefore(todayButton, footer.firstChild);
  }

  if (todayButton.dataset.boundTodayClick === "true") return;
  todayButton.dataset.boundTodayClick = "true";

  todayButton.addEventListener("click", () => {
    const currentInstance = window.M?.Datepicker?.getInstance(input);
    if (!currentInstance) return;

    const today = new Date();
    currentInstance.setDate(today);
    input.value = formatDisplayDate(today);
    updateFacturaRateByDate(input, today);
    normalizeDatepickerHeaderText();
    currentInstance.close();
  });
};

const initializeMaterializeDatepickers = (scope = document) => {
  if (!window.M?.Datepicker) return;

  const root =
    scope instanceof Element || scope instanceof Document ? scope : document;
  const container = document.getElementById("materialize-datepicker-portal");
  const dateInputs = root.querySelectorAll(".js-materialize-datepicker");

  dateInputs.forEach((input) => {
    if (window.M.Datepicker.getInstance(input)) return;

    const defaultDate = parseDisplayDate(input.value);

    window.M.Datepicker.init(input, {
      autoClose: true,
      format: "dd-mm-yyyy",
      defaultDate,
      setDefaultDate: Boolean(defaultDate),
      container,
      showClearBtn: false,
      showTodayBtn: true,
      onOpen: () => {
        normalizeDatepickerHeaderText();
        ensureTodayButton(input);
      },
      onDraw: () => {
        normalizeDatepickerHeaderText();
        ensureTodayButton(input);
      },
      onSelect: (selectedDate) => {
        input.value = formatDisplayDate(selectedDate);
        updateFacturaRateByDate(input, selectedDate);
        normalizeDatepickerHeaderText();
      },
      i18n: {
        cancel: "↩",
        clear: "⌫",
        today: "Hoy",
        done: "✓",
        previousMonth: "Mes anterior",
        nextMonth: "Mes siguiente",
        months: [
          "Enero",
          "Febrero",
          "Marzo",
          "Abril",
          "Mayo",
          "Junio",
          "Julio",
          "Agosto",
          "Septiembre",
          "Octubre",
          "Noviembre",
          "Diciembre",
        ],
        monthsShort: [
          "Ene",
          "Feb",
          "Mar",
          "Abr",
          "May",
          "Jun",
          "Jul",
          "Ago",
          "Sep",
          "Oct",
          "Nov",
          "Dic",
        ],
        weekdays: [
          "Domingo",
          "Lunes",
          "Martes",
          "Miércoles",
          "Jueves",
          "Viernes",
          "Sábado",
        ],
        weekdaysShort: ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"],
        weekdaysAbbrev: ["D", "L", "M", "M", "J", "V", "S"],
      },
    });
  });
};

const destroyMaterializeDatepickers = (scope = document) => {
  if (!window.M?.Datepicker) return;

  const root =
    scope instanceof Element || scope instanceof Document ? scope : document;
  const dateInputs = root.querySelectorAll(".js-materialize-datepicker");

  dateInputs.forEach((input) => {
    const instance = window.M.Datepicker.getInstance(input);
    if (instance) instance.destroy();
  });
};

const initializeTailwindDatepickers = (scope = document) => {
  const root =
    scope instanceof Element || scope instanceof Document ? scope : document;

  root
    .querySelectorAll(
      'input[type="date"]:not([data-tailwind-datepicker="false"])',
    )
    .forEach((input) => {
      if (input.dataset.tailwindDatepickerBound === "true") return;
      input.dataset.tailwindDatepickerBound = "true";
      input.dataset.tailwindDatepicker = "true";
      input.classList.add("tailwind-datepicker-input");

      const normalizedDate = parseDisplayDate(input.value);
      if (normalizedDate) {
        input.value = formatIsoDate(normalizedDate);
      }

      const tryShowPicker = () => {
        if (input.disabled) return;
        if (typeof input.showPicker !== "function") return;

        try {
          input.showPicker();
        } catch (_error) {}
      };

      input.addEventListener("focus", tryShowPicker);
      input.addEventListener("click", tryShowPicker);
      input.addEventListener("change", () => {
        const selectedDate = parseDisplayDate(input.value);
        if (!selectedDate) return;

        input.value = formatIsoDate(selectedDate);
        updateFacturaRateByDate(input, selectedDate);
      });
    });
};

window.initializeMaterializeDatepickers = initializeMaterializeDatepickers;
window.initializeTailwindDatepickers = initializeTailwindDatepickers;

const initializeMoneyMasks = () => {
  window.MoneyInputMask?.init(document);
};

const initializeLucideIcons = (attemptsRemaining = 20) => {
  if (window.lucide && typeof window.lucide.createIcons === "function") {
    window.lucide.createIcons();
    return;
  }

  if (attemptsRemaining <= 0) return;

  window.setTimeout(() => initializeLucideIcons(attemptsRemaining - 1), 150);
};

document.addEventListener("turbo:load", () =>
  initializeTailwindDatepickers(document),
);
document.addEventListener("DOMContentLoaded", () =>
  initializeTailwindDatepickers(document),
);
document.addEventListener("turbo:render", () =>
  initializeTailwindDatepickers(document),
);
document.addEventListener("turbo:frame-load", (event) =>
  initializeTailwindDatepickers(event.target),
);
document.addEventListener("turbo:load", () =>
  initializeMaterializeDatepickers(document),
);
document.addEventListener("DOMContentLoaded", () =>
  initializeMaterializeDatepickers(document),
);
document.addEventListener("turbo:render", () =>
  initializeMaterializeDatepickers(document),
);
document.addEventListener("turbo:frame-load", (event) =>
  initializeMaterializeDatepickers(event.target),
);
document.addEventListener("turbo:before-cache", () =>
  destroyMaterializeDatepickers(document),
);
document.addEventListener("turbo:load", initializeMoneyMasks);
document.addEventListener("DOMContentLoaded", initializeMoneyMasks);
document.addEventListener("turbo:render", initializeMoneyMasks);
document.addEventListener("turbo:frame-load", initializeMoneyMasks);
document.addEventListener("turbo:load", initializeLucideIcons);
document.addEventListener("DOMContentLoaded", initializeLucideIcons);
document.addEventListener("turbo:render", initializeLucideIcons);
document.addEventListener("turbo:frame-load", initializeLucideIcons);
document.addEventListener("turbo:before-stream-render", (event) => {
  const streamRender = event.detail?.render;
  if (typeof streamRender !== "function") return;

  event.detail.render = (streamElement) => {
    streamRender(streamElement);
    initializeLucideIcons();
  };
});
document.addEventListener("turbo:load", displayFlashToasts);
document.addEventListener("DOMContentLoaded", displayFlashToasts);
document.addEventListener("turbo:render", displayFlashToasts);
document.addEventListener("turbo:frame-load", displayFlashToasts);
document.addEventListener("turbo:load", displayBalanceInsufficientAlerts);
document.addEventListener("DOMContentLoaded", displayBalanceInsufficientAlerts);
document.addEventListener("turbo:render", displayBalanceInsufficientAlerts);
document.addEventListener("turbo:frame-load", displayBalanceInsufficientAlerts);

document.addEventListener(
  "submit",
  (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;

    const dateInputs = form.querySelectorAll(".js-materialize-datepicker");
    dateInputs.forEach((input) => {
      const parsed = parseDisplayDate(input.value);
      if (parsed) {
        input.value = formatIsoDate(parsed);
      }
    });
  },
  true,
);

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
        // Guardamos el contenido original
        const originalHTML = link.innerHTML;

        // Añadimos una clase para desactivar el enlace (defínela en CSS si lo deseas)
        link.classList.add("disabled");

        // Cambiar el contenido del enlace a "Copiado" con estilo en letras pequeñas y color blanco.
        link.innerHTML =
          '<span class="fs-6 text-black fst-italic">Copiado!</span>';

        // Después de 5 segundos, restaurar el contenido original y remover la clase
        setTimeout(() => {
          link.innerHTML = originalHTML;
          link.classList.remove("disabled");
        }, 5000);
      })
      .catch((err) => {
        console.error("Falla al copiar!", err);
      });
  }
});

document.addEventListener(
  "click",
  (event) => {
    const clickedElement = event.target;
    if (!(clickedElement instanceof Element)) return;

    const deleteLink = clickedElement.closest(
      "a[data-swal-delete], a[data-turbo-method='delete'], a[data-method='delete']",
    );
    if (!deleteLink) return;

    event.preventDefault();
    event.stopPropagation();
    if (typeof event.stopImmediatePropagation === "function") {
      event.stopImmediatePropagation();
    }

    const deleteType = deleteLink.dataset.swalDelete;
    const messages = {
      supplier: {
        title: "¿Eliminar proveedor?",
        text: "Esta acción eliminará el proveedor y sus asociaciones directas. El historial de lotes/facturas se conservará.",
      },
      account: {
        title: "¿Eliminar cuenta?",
        text: "Esta acción eliminará la cuenta financiera seleccionada.",
      },
      business: {
        title: "Eliminar negocio?",
        text: "Esta accion eliminara el negocio y sus datos asociados.",
      },
      cliente: {
        title: "¿Eliminar cliente?",
        text: "Esta accion eliminara el cliente y su relacion con ventas.",
      },
      tasa_cambio: {
        title: "¿Eliminar tasa de cambio?",
        text: "Esta acción eliminará la tasa seleccionada.",
      },
      service: {
        title: "¿Eliminar servicio?",
        text: "Esta accion eliminara el servicio seleccionado.",
      },
      system_service: {
        title: "¿Eliminar sistema de servicios?",
        text: "Esta accion eliminara el sistema de servicios seleccionado.",
      },
      manager: {
        title: "¿Eliminar gestor?",
        text: "Esta accion eliminara el gestor seleccionado.",
      },
      expense: {
        title: "¿Eliminar gasto?",
        text: "Esta accion eliminara el gasto y sus pagos asociados.",
      },
      purchase_invoice: {
        title: "¿Eliminar factura de compra?",
        text: "Esta accion eliminara la factura y revertira sus efectos asociados: pagos, deudas pendientes y lotes de inventario.",
      },
      unpack_history: {
        title: "¿Eliminar desempaque?",
        text: "Esta accion revertira el desempaque y restaurara el stock de origen si aplica.",
      },
      venta: {
        title: "¿Eliminar venta?",
        text: "Esta accion eliminara la venta y todo lo asociado: items, pagos, movimientos y reposicion de stock.",
      },
      cambio_efectivo: {
        title: "¿Eliminar operacion de pasarela?",
        text: "Esta accion eliminara la operacion y revertira sus movimientos asociados.",
      },
      internal_usage: {
        title: "¿Eliminar uso interno?",
        text: "Esta accion eliminara el registro y restaurara el stock del producto en los lotes descontados.",
      },
      manual_movement: {
        title: "¿Eliminar movimiento manual?",
        text: "Esta accion eliminara el movimiento manual seleccionado de la cuenta.",
      },
      account_movement: {
        title: "¿Eliminar movimiento?",
        text: "Esta accion eliminara el movimiento seleccionado de la cuenta.",
      },
      logout: {
        title: "¿Cerrar sesion?",
        text: "Tu sesion actual se cerrara en este dispositivo.",
        confirmButtonText: "Si, cerrar sesion",
      },
    };

    if (!window.Swal) {
      return;
    }

    const submitDeleteForm = (extraFields = {}) => {
      const form = document.createElement("form");
      form.method = "post";
      form.action = deleteLink.href;
      form.style.display = "none";

      const methodInput = document.createElement("input");
      methodInput.type = "hidden";
      methodInput.name = "_method";
      methodInput.value = "delete";
      form.appendChild(methodInput);

      const csrfToken = document
        .querySelector('meta[name="csrf-token"]')
        ?.getAttribute("content");
      if (csrfToken) {
        const csrfInput = document.createElement("input");
        csrfInput.type = "hidden";
        csrfInput.name = "authenticity_token";
        csrfInput.value = csrfToken;
        form.appendChild(csrfInput);
      }

      Object.entries(extraFields).forEach(([key, value]) => {
        const input = document.createElement("input");
        input.type = "hidden";
        input.name = key;
        input.value = String(value);
        form.appendChild(input);
      });

      document.body.appendChild(form);
      form.submit();
    };

    if (deleteType === "debt") {
      const confirmDebtDeleteMode = (deleteMode) => {
        const config =
          deleteMode === "with_movements"
            ? {
                title: "¿Eliminar deuda y movimientos?",
                text: "Se eliminará la deuda y también todos los movimientos de cuentas vinculados a esa deuda. Esta acción no se puede deshacer.",
                confirmButtonColor: "#dc2626",
              }
            : {
                title: "¿Eliminar solo deuda?",
                text: "Se eliminará solo la deuda. Los movimientos de cuentas vinculados se conservarán. Esta acción no se puede deshacer.",
                confirmButtonColor: "#2563eb",
              };

        Swal.fire({
          title: config.title,
          text: config.text,
          icon: "warning",
          showCancelButton: true,
          confirmButtonText: "Sí, eliminar",
          cancelButtonText: "Volver",
          confirmButtonColor: config.confirmButtonColor,
          cancelButtonColor: "#64748b",
          target: "body",
          heightAuto: false,
        }).then((result) => {
          if (result.isConfirmed) {
            submitDeleteForm({ delete_mode: deleteMode });
            return;
          }

          if (result.dismiss === Swal.DismissReason.cancel) {
            openDebtDeleteModeSelector();
          }
        });
      };

      const openDebtDeleteModeSelector = () => {
        Swal.fire({
          title: "¿Eliminar deuda?",
          html: "Selecciona cómo deseas eliminarla:<br><br><b>1)</b> Eliminar deuda y movimientos en cuentas.<br><b>2)</b> Eliminar solo deuda y conservar movimientos.",
          icon: "warning",
          showCancelButton: true,
          showDenyButton: true,
          confirmButtonText: "Deuda + movimientos",
          denyButtonText: "Solo deuda",
          cancelButtonText: "Cancelar",
          confirmButtonColor: "#dc2626",
          denyButtonColor: "#2563eb",
          cancelButtonColor: "#64748b",
          target: "body",
          heightAuto: false,
        }).then((result) => {
          if (result.isConfirmed) {
            confirmDebtDeleteMode("with_movements");
            return;
          }

          if (result.isDenied) {
            confirmDebtDeleteMode("debt_only");
          }
        });
      };

      openDebtDeleteModeSelector();

      return;
    }

    const config = messages[deleteType] || {
      title: "¿Eliminar registro?",
      text: "Esta acción no se puede deshacer.",
      confirmButtonText: "Sí, eliminar",
    };

    Swal.fire({
      title: config.title,
      text: config.text,
      icon: "warning",
      showCancelButton: true,
      confirmButtonText: config.confirmButtonText || "Sí, eliminar",
      cancelButtonText: "Cancelar",
      confirmButtonColor: "#dc2626",
      cancelButtonColor: "#64748b",
      target: "body",
      heightAuto: false,
    }).then((result) => {
      if (!result.isConfirmed) return;

      submitDeleteForm();
    });
  },
  true,
);
