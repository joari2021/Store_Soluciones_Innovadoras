import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    const precioCostoPackUSD = document.getElementById("producto_precio_costo");
    const precioCostoPackBs = document.getElementById("precio_c_bs");
    const cantidadPack = document.getElementById("producto_cant_unidades");
    const precioCostoUnidadUSD = document.getElementById("costo_u_usd");
    const precioCostoUnidadBs = document.getElementById("costo_u_bs");
    const precioVentaUSD = document.getElementById("producto_precio_venta_usd");
    const precioVentaBs = document.getElementById("producto_precio_venta_bs");

    function editPrecioSugerido() {
      const nivelGanancia = document.querySelector(".form-select").value;
      const precioCostoUnidadUSD =
        parseFloat(document.getElementById("costo_u_usd").value) || 0;

      var precioSugeridoUSD = 0;

      switch (nivelGanancia) {
        case "Baja":
          precioSugeridoUSD = precioCostoUnidadUSD / (1 - 0.2);
          break;
        case "Media":
          precioSugeridoUSD = precioCostoUnidadUSD / (1 - 0.3);
          break;
        case "Alta":
          precioSugeridoUSD = precioCostoUnidadUSD / (1 - 0.5);
          break;
      }
      // Actualiza el valor del input de precio sugerido
      document.getElementById("precio_sugerido_usd").value =
        precioSugeridoUSD.toFixed(2);
      document.getElementById("precio_sugerido_bs").value = (
        precioSugeridoUSD.toFixed(2) * tasaDolar
      ).toFixed(2);
    }
    function calcularPrecioCosto() {
      // Convertir el valor del input a un número y calcular
      const valorPackUSD = parseFloat(precioCostoPackUSD.value) || 0; // Convierte o usa 0 si está vacío
      const valorPackEnBs = (valorPackUSD * tasaDolar).toFixed(2);
      const cantidadPackNumber = parseFloat(cantidadPack.value) || 0; // Convierte o usa 0 si está vacío
      const valorUnidadUSD = (valorPackUSD / cantidadPackNumber).toFixed(2);

      // Asignar el valor calculado al input
      precioCostoPackBs.value = valorPackEnBs;
      precioCostoUnidadUSD.value = valorUnidadUSD;
      precioCostoUnidadBs.value = (valorUnidadUSD * tasaDolar).toFixed(2);
    }
    function calcularPrecioVentaUSD() {
      const valorVentaUSD = parseFloat(precioVentaUSD.value) || 0; // Convierte o usa 0 si está vacío
      const valorVentaBs = (valorVentaUSD * tasaDolar).toFixed(2);

      // Asignar el valor calculado al input
      precioVentaBs.value = valorVentaBs;
    }
    function calcularPrecioVentaBs() {
      const valorVentaBs = parseFloat(precioVentaBs.value) || 0; // Convierte o usa 0 si está vacío
      const valorVentaUSD = (valorVentaBs / tasaDolar).toFixed(2);

      // Asignar el valor calculado al input
      precioVentaUSD.value = valorVentaUSD;
    }
    function rellenarCamposVistaEdit() {
      calcularPrecioCosto();
      editPrecioSugerido();
    }
    rellenarCamposVistaEdit();

    // Evento que se ejecuta al escribir en el input de USD
    precioCostoPackUSD.addEventListener("input", function () {
      calcularPrecioCosto();
      editPrecioSugerido();
    });

    cantidadPack.addEventListener("input", function () {
      calcularPrecioCosto();
      editPrecioSugerido();
    });

    precioVentaUSD.addEventListener("input", function () {
      calcularPrecioVentaUSD();
    });

    precioVentaBs.addEventListener("input", function () {
      calcularPrecioVentaBs();
    });
  }
}
