=begin
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
=end
require 'selenium-webdriver'
require 'nokogiri'

class BcvScraperService
  def self.call
    url = "https://monitordolarvenezuela.com/"
    begin
      # Configurar Selenium con Chrome
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless') # Ejecutar en modo headless (sin interfaz gráfica)
      options.add_argument('--disable-gpu')
      options.add_argument('--no-sandbox')

      driver = Selenium::WebDriver.for(:chrome, options: options)
      driver.navigate.to(url)

      # Esperar a que el contenido se cargue
      sleep 5 # Ajusta el tiempo según sea necesario

      # Obtener el HTML renderizado
      html = driver.page_source
      doc = Nokogiri::HTML(html)

     # Extraer el div padre que contiene ambos valores
      parent_div = doc.at_css("div.grid.grid-cols-6.gap-2.my-2")

      # Extraer el valor del Dólar BCV (primer hijo)
      bcv_div = parent_div&.at_css("div:has(h3:contains('Dólar BCV (Oficial)'))")
      bcv_value = bcv_div&.at_css("p.font-bold.text-xl")&.text&.strip if bcv_div

      # Extraer el valor del Dólar Paralelo (segundo hijo)
      paralelo_div = parent_div&.at_css("div:has(h3:contains('Dólar Paralelo'))")
      paralelo_value = paralelo_div&.at_css("p.font-bold.text-xl")&.text&.strip if paralelo_div

      # Depuración
      puts "BCV Value: #{bcv_value}"
      puts "Paralelo Value: #{paralelo_value}"

      # Limpiar los valores extraídos
      bcv_value_clean = clean_value(bcv_value)
      paralelo_value_clean = clean_value(paralelo_value)

      # Actualizar los valores en la base de datos
      update_tasa_cambio("Dolar BCV", bcv_value_clean)
      update_tasa_cambio("Dolar Paralelo", paralelo_value_clean)

      # Cerrar el navegador
      driver.quit

      { bcv: bcv_value_clean, paralelo: paralelo_value_clean }
    rescue => e
      Rails.logger.error "Error en BcvScraperService: #{e.message}"
      nil 
    end
  end

  private

  def self.clean_value(value)
    return nil unless value
    value = value.tr(',', '.') # Reemplazar coma por punto
    value.gsub(/[^\d.]/, '')   # Eliminar caracteres no numéricos
  end

  def self.update_tasa_cambio(description, value)
    return unless value.present?
    tasa_valor = BigDecimal(value).round(2)
    TasaCambio.find_by(description: description)&.update(valor: tasa_valor)
  end
end