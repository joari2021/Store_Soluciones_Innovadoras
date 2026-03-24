const DEFAULT_LOCALE = "es-VE";
const boundRoots = new WeakSet();
const HANDLED_EVENT_KEYS = {
  keydown: "__moneyMaskHandledKeydown",
  paste: "__moneyMaskHandledPaste",
};

const eventAlreadyHandled = (event, key) => {
  if (!event || !key) return false;
  if (event[key]) return true;
  event[key] = true;
  return false;
};

const parseCurrencyNumber = (rawValue) => {
  const compact = String(rawValue || "")
    .replace(/\s/g, "")
    .replace(/[^\d.,-]/g, "");

  let normalized = compact;
  if (compact.includes(",")) {
    normalized = compact.replace(/\./g, "").replace(",", ".");
  } else if (
    compact.split(".").length > 2 &&
    compact
      .split(".")
      .slice(1)
      .every((group) => group.length === 3)
  ) {
    normalized = compact.replace(/\./g, "");
  }

  const parsed = Number.parseFloat(normalized);
  if (!Number.isFinite(parsed)) return 0;
  return parsed < 0 ? 0 : parsed;
};

const formatMoney = (value, symbol) => {
  const safeValue = Number.isFinite(Number(value))
    ? Math.max(Number(value), 0)
    : 0;
  const number = safeValue.toLocaleString(DEFAULT_LOCALE, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return `${symbol} ${number}`;
};

const getSymbol = (input, explicitSymbol) => {
  if (explicitSymbol) return explicitSymbol;
  return input?.dataset.moneySymbol || "$";
};

const getCents = (input) => {
  if (!input) return 0;
  const fromData = Number.parseInt(input.dataset.moneyCents || "", 10);
  if (Number.isFinite(fromData)) return Math.max(fromData, 0);
  return Math.round(parseCurrencyNumber(input.value) * 100);
};

const keepCaretAtEnd = (input) => {
  if (!input || typeof input.setSelectionRange !== "function") return;
  const end = input.value.length;
  input.setSelectionRange(end, end);
};

const setValue = (input, value, explicitSymbol) => {
  if (!input) return;
  const symbol = getSymbol(input, explicitSymbol);
  const safeValue = Number.isFinite(Number(value))
    ? Math.max(Number(value), 0)
    : 0;
  input.value = formatMoney(safeValue, symbol);
  input.dataset.moneySymbol = symbol;
  input.dataset.moneyCents = String(Math.round(safeValue * 100));
};

const setCents = (input, cents, explicitSymbol) => {
  const safeCents = Math.max(Number.parseInt(cents, 10) || 0, 0);
  setValue(input, safeCents / 100, explicitSymbol);
};

const parseValue = (input) => parseCurrencyNumber(input?.value);

const normalizeInput = (input) => {
  if (!input) return;
  const symbol = getSymbol(input);
  const value = parseCurrencyNumber(input.value);
  setValue(input, value, symbol);
};

const emitMaskedInputEvent = (input) => {
  if (!input) return;
  input.dispatchEvent(new Event("input", { bubbles: true }));
};

const handleMoneyKeydown = (event) => {
  if (eventAlreadyHandled(event, HANDLED_EVENT_KEYS.keydown)) return;

  const input = event.target;
  if (!(input instanceof HTMLInputElement)) return;
  if (input.dataset.moneyMask !== "true") return;

  const key = event.key;
  const isDigit = /^\d$/.test(key);
  const allowedKeys = [
    "Tab",
    "Enter",
    "ArrowLeft",
    "ArrowRight",
    "ArrowUp",
    "ArrowDown",
    "Home",
    "End",
  ];

  if (allowedKeys.includes(key)) return;

  if (isDigit) {
    event.preventDefault();
    const nextCents = getCents(input) * 10 + Number.parseInt(key, 10);
    setCents(input, nextCents);
    emitMaskedInputEvent(input);
    keepCaretAtEnd(input);
    return;
  }

  if (key === "Backspace") {
    event.preventDefault();
    const nextCents = Math.floor(getCents(input) / 10);
    setCents(input, nextCents);
    emitMaskedInputEvent(input);
    keepCaretAtEnd(input);
    return;
  }

  if (key === "Delete") {
    event.preventDefault();
    setCents(input, 0);
    emitMaskedInputEvent(input);
    keepCaretAtEnd(input);
    return;
  }

  if (key === "," || key === ".") {
    event.preventDefault();
    keepCaretAtEnd(input);
    return;
  }

  if (key.length === 1) {
    event.preventDefault();
  }
};

const handleMoneyPaste = (event) => {
  if (eventAlreadyHandled(event, HANDLED_EVENT_KEYS.paste)) return;

  const input = event.target;
  if (!(input instanceof HTMLInputElement)) return;
  if (input.dataset.moneyMask !== "true") return;

  event.preventDefault();
  const pasted = event.clipboardData ? event.clipboardData.getData("text") : "";
  setValue(input, parseCurrencyNumber(pasted));
  emitMaskedInputEvent(input);
  keepCaretAtEnd(input);
};

const handleMoneyFocus = (event) => {
  const input = event.target;
  if (!(input instanceof HTMLInputElement)) return;
  if (input.dataset.moneyMask !== "true") return;
  keepCaretAtEnd(input);
};

const bindMoneyMask = (root = document) => {
  if (!root) return;

  root.querySelectorAll('input[data-money-mask="true"]').forEach((input) => {
    normalizeInput(input);
  });

  if (boundRoots.has(root)) return;
  boundRoots.add(root);

  root.addEventListener("focusin", handleMoneyFocus);
  root.addEventListener("click", (event) => {
    const input = event.target;
    if (!(input instanceof HTMLInputElement)) return;
    if (input.dataset.moneyMask !== "true") return;
    setTimeout(() => keepCaretAtEnd(input), 0);
  });
  root.addEventListener("keydown", handleMoneyKeydown);
  root.addEventListener("paste", handleMoneyPaste);
};

const MoneyInputMask = {
  init: bindMoneyMask,
  setValue,
  setCents,
  parseValue,
  formatMoney,
};

window.MoneyInputMask = MoneyInputMask;

export default MoneyInputMask;
