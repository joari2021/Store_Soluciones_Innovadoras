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
      dato_dolar = doc.at_css('#dolar strong')&.text&.strip
      dato_euro = doc.at_css('#euro strong')&.text&.strip

      # Extraer la fecha de validez
      fecha_texto = doc.at_css('.pull-right.dinpro.center .date-display-single')&.text&.strip

      if (dato_dolar.present? || dato_euro.present?) && fecha_texto.present?
        # Convertir la fecha extraída al formato de fecha
        fecha_validez = Date.parse(fecha_texto) rescue nil
        fecha_actual = Time.now.in_time_zone('Caracas').to_date

        # Comparar la fecha de validez con la fecha actual
        if fecha_validez == fecha_actual
          dato_dolar = dato_dolar.tr(',', '.')  # Reemplaza la coma por punto
          dato_dolar_clean = dato_dolar.gsub(/[^\d.]/, '')  # Elimina caracteres no numéricos, si los hubiera
          tasa_valor_dolar = BigDecimal(dato_dolar_clean).round(2)

          # Actualizar el registro en la base de datos
          tasa_bcv_dolar = TasaCambio.find_by(description: "Dolar BCV")
          #tasa_paralelo = TasaCambio.find_by(description: "Dolar Paralelo") 
          #tasa_promedio = TasaCambio.find_by(description: "Dolar Promedio")
          tasa_bcv_dolar.update(valor: tasa_valor_dolar)
          #new_promedio = (tasa_bcv.valor + tasa_paralelo.valor) / 2
          #tasa_promedio.update(valor: new_promedio)
          
          dato_euro = dato_euro.tr(',', '.')  # Reemplaza la coma por punto
          dato_euro_clean = dato_euro.gsub(/[^\d.]/, '')  # Elimina caracteres no numéricos, si los hubiera
          tasa_valor_euro = BigDecimal(dato_euro_clean).round(2)
          # Actualizar el registro en la base de datos
          tasa_bcv_euro = TasaCambio.find_by(description: "Euro BCV")
          tasa_bcv_euro.update(valor: tasa_valor_euro)
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