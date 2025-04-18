require 'open-uri'
require 'nokogiri'
require 'active_support/time'

class BcvScraperService
  # Este método realiza el scraping y devuelve el dato extraído.
  def self.call
    url = "https://www.bcv.org.ve"
    begin
      html = URI.open(url)
      doc = Nokogiri::HTML(html)

      # Extraer el valor del dólar
      dato = doc.at_css('#dolar strong')&.text&.strip

      # Extraer la fecha de validez
      fecha_texto = doc.at_css('.pull-right.dinpro.center .date-display-single')&.text&.strip

      if dato.present? && fecha_texto.present?
        # Convertir la fecha extraída al formato de fecha
        fecha_validez = Date.parse(fecha_texto) rescue nil
        fecha_actual = Time.now.in_time_zone('Caracas').to_date

        # Comparar la fecha de validez con la fecha actual
        if fecha_validez == fecha_actual
          dato = dato.tr(',', '.')  # Reemplaza la coma por punto
          dato_clean = dato.gsub(/[^\d.]/, '')  # Elimina caracteres no numéricos, si los hubiera
          tasa_valor = BigDecimal(dato_clean).round(2)

          # Actualizar el registro en la base de datos
          tasa_bcv = TasaCambio.find_by(description: "Dolar BCV")
          tasa_paralelo = TasaCambio.find_by(description: "Dolar Paralelo") 
          tasa_promedio = TasaCambio.find_by(description: "Dolar Promedio")
          tasa_bcv.update(valor: tasa_valor)
          new_promedio = (tasa_bcv.valor + tasa_paralelo.valor) / 2
          tasa_promedio.update(valor: new_promedio)
        else
          Rails.logger.info "La fecha de validez #{fecha_validez} no coincide con la fecha actual #{fecha_actual}. No se actualizó el dato."
        end
      end

      dato
    rescue => e
      Rails.logger.error "Error en BcvScraperService: #{e.message}"
      nil
    end
  end
end