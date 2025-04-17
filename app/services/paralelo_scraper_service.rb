require 'selenium-webdriver'
require 'nokogiri'

class ParaleloScraperService
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

      # Extraer el valor del Dólar Paralelo (segundo hijo)
      paralelo_div = parent_div&.at_css("div:has(h3:contains('Dólar Paralelo'))")
      paralelo_value = paralelo_div&.at_css("p.font-bold.text-xl")&.text&.strip if paralelo_div

      # Depuración
      
      puts "Paralelo Value: #{paralelo_value}"

      # Limpiar los valores extraídos
      paralelo_value_clean = clean_value(paralelo_value)

      # Actualizar los valores en la base de datos
      update_tasa_cambio("Dolar Paralelo", paralelo_value_clean)

      # Cerrar el navegador
      driver.quit

      { paralelo: paralelo_value_clean }
    rescue => e
      Rails.logger.error "Error en ParaleloScraperService: #{e.message}"
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