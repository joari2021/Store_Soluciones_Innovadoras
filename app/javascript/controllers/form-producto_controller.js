import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    const precioCostoPackUSD = document.getElementById("producto_precio_costo");
    const precioCostoPackBs = document.getElementById("precio_c_bs");
    const cantidadPack = document.getElementById("producto_cant_unidades");
    const precioCostoUnidadUSD = document.getElementById("costo_u_usd");
    const precioCostoUnidadBs = document.getElementById("costo_u_bs");
    const precioVentaUSD = document.getElementById("producto_precio_venta");
    const precioVentaBs = document.getElementById("precio_venta_bs");

    // Evento que se ejecuta al escribir en el input de USD
    precioCostoPackUSD.addEventListener("input", function () {
      // Convertir el valor del input a un número y calcular
      const valorPackUSD = parseFloat(precioCostoPackUSD.value) || 0; // Convierte o usa 0 si está vacío
      const valorPackEnBs = (valorPackUSD * tasaDolar).toFixed(2);

      // calcular valor de unidad en $
      const cantidadPackInteger = parseFloat(cantidadPack.value) || 0; // Convierte o usa 0 si está vacío
      const valorUnidadUSD = (valorPackUSD / cantidadPackInteger).toFixed(2);

      // Asignar el valor calculado al input
      precioCostoPackBs.value = valorPackEnBs;
      precioCostoUnidadUSD.value = valorUnidadUSD;
    });

    cantidadPack.addEventListener("input", function () {
      // calcular valor de unidad en $
      const cantidadPackNumber = parseFloat(cantidadPack.value) || 0; // Convierte o usa 0 si está vacío
      const valorPackUSD = parseFloat(precioCostoPackUSD.value) || 0; // Convierte o usa 0 si está vacío
      const valorUnidadUSD = (valorPackUSD / cantidadPackNumber).toFixed(2);

      // Asignar el valor calculado al input
      precioCostoUnidadUSD.value = valorUnidadUSD;
      precioCostoUnidadBs.value = (valorUnidadUSD * tasaDolar).toFixed(2);
    });

    precioVentaUSD.addEventListener("input", function () {
      const valorVentaUSD = parseFloat(precioVentaUSD.value) || 0; // Convierte o usa 0 si está vacío
      const valorVentaBs = (valorVentaUSD * tasaDolar).toFixed(2);

      // Asignar el valor calculado al input
      precioVentaBs.value = valorVentaBs;
    });
  }
}
