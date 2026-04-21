window.addEventListener("turbo:load", () => {
  const removeProductRowsFromIndex = (productId) => {
    if (!productId) return;

    const selectors = [
      `tr[data-product-row-id="${productId}"]`,
      `tr[data-product-detail-for="${productId}"]`,
      `tr[data-product-lot-for="${productId}"]`,
      `tr[data-product-empty-for="${productId}"]`,
    ];

    document.querySelectorAll(selectors.join(",")).forEach((row) => row.remove());
  };

  const updateProductsCounters = () => {
    const loadedNode = document.querySelector("[data-products-loaded-count='true']");
    const totalNode = document.querySelector("[data-products-total-count='true']");
    const totalLabelNode = document.querySelector("[data-products-total-label='true']");

    if (loadedNode) {
      const current = Number(loadedNode.textContent || 0);
      loadedNode.textContent = String(Math.max(0, current - 1));
    }

    if (totalNode) {
      const current = Number(totalNode.textContent || 0);
      const next = Math.max(0, current - 1);
      totalNode.textContent = String(next);
      if (totalLabelNode) {
        totalLabelNode.textContent = next === 1 ? "producto" : "productos";
      }
    }
  };

  const renderCountBadge = (count, title) => {
    const numeric = Number(count || 0);
    if (!(numeric > 0)) return "";

    return `<span class="inline-flex min-w-[1.5rem] items-center justify-center rounded-full bg-rose-600 px-2 py-0.5 text-xs font-bold text-white" title="${title}">${numeric}</span>`;
  };

  const updateProductsBadges = (payload) => {
    const lowStockBadge = document.getElementById("products-low-stock-badge");
    const belowTargetBadge = document.getElementById("products-below-target-badge");

    if (lowStockBadge && Object.prototype.hasOwnProperty.call(payload, "low_stock_total_count")) {
      lowStockBadge.innerHTML = renderCountBadge(payload.low_stock_total_count, "Productos con stock bajo");
    }

    if (belowTargetBadge && Object.prototype.hasOwnProperty.call(payload, "below_target_margin_total_count")) {
      belowTargetBadge.innerHTML = renderCountBadge(payload.below_target_margin_total_count, "Productos por debajo del objetivo");
    }
  };

  const submitAjaxDeleteForProducts = async (form) => {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content");
    const response = await fetch(form.action, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "X-Requested-With": "XMLHttpRequest",
        ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
      },
      credentials: "same-origin",
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok || payload.success !== true) {
      throw new Error(payload.error || "No se pudo eliminar el registro.");
    }

    const productId = String(payload.product_id || form.dataset.productId || "").trim();
    removeProductRowsFromIndex(productId);
    updateProductsCounters();
    updateProductsBadges(payload);
  };

  document.addEventListener("submit", (event) => {
    if (event.target && event.target.classList.contains("delete-alertbox")) {
      event.preventDefault();
      const form = event.target;
      const isProductsAjaxDelete = form.dataset.productsAjaxDelete === "true";

      Swal.fire({
        title: "¿Estás seguro?",
        text: "¡No podrás revertir esto!",
        icon: "warning",
        target: "body",
        heightAuto: false,
        showCancelButton: true,
        confirmButtonColor: "#3085d6",
        cancelButtonColor: "#d33",
        cancelButtonText: "Cancelar",
        confirmButtonText: "Sí, eliminarlo",
      }).then(async (result) => {
        if (result.isConfirmed) {
          if (isProductsAjaxDelete) {
            try {
              await submitAjaxDeleteForProducts(form);
              Swal.fire({
                title: "Eliminado!",
                text: "El producto fue eliminado correctamente.",
                icon: "success",
                target: "body",
                heightAuto: false,
              });
            } catch (error) {
              Swal.fire({
                title: "Error",
                text: error.message || "No se pudo eliminar el producto.",
                icon: "error",
                target: "body",
                heightAuto: false,
              });
            }
            return;
          }

          Swal.fire({
            title: "Eliminado!",
            text: "El registro ha sido eliminado.",
            icon: "success",
            target: "body",
            heightAuto: false,
          });
          form.submit();
        }
      });
    }
  });
});
