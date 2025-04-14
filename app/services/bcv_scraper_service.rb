# app/services/bcv_scraper_service.rb
require 'open-uri'
require 'nokogiri'

class BcvScraperService
  # Este método realiza el scraping y devuelve el dato extraído.
  def self.call
    url = "https://www.bcv.org.ve"
    begin
      html = URI.open(url)
      doc = Nokogiri::HTML(html)
      # Ajusta el selector según la página y el dato que necesites
      # Ejemplo: extraer el valor de una tasa que se encuentre en un span con id "tasa-dolar"
      #dato = doc.at_css("#tasa-dolar")&.text&.strip
      dato = doc.at_css('#dolar strong')&.text&.strip



      # Aquí podrías actualizar un registro en la base de datos o devolver el dato
      # Por ejemplo, si tienes un modelo TasaCambio:
      if dato.present?
        dato = dato.tr(',', '.')  # Reemplaza la coma por punto
        dato_clean = dato.gsub(/[^\d.]/, '')  # Elimina caracteres no numéricos, si los hubiera
        tasa_valor = BigDecimal(dato_clean).round(2)

        TasaCambio.find_by(name: "Dolar BCV").update(valor: tasa_valor)
      end

      dato
    rescue => e
      Rails.logger.error "Error en BcvScraperService: #{e.message}"
      nil
    end
  end
end
