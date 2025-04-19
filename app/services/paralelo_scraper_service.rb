=begin
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
    tasa_paralelo = TasaCambio.find_by(description: description)
    tasa_bcv = TasaCambio.find_by(description: "Dolar BCV")
    tasa_promedio = TasaCambio.find_by(description: "Dolar Promedio")

    tasa_paralelo.update(valor: tasa_valor)
    new_promedio = BigDecimal((tasa_bcv.valor + tasa_paralelo.valor) / 2).round(2)
    tasa_promedio.update(valor: new_promedio)
  end
end
=end
require 'selenium-webdriver'
require 'nokogiri'

class ParaleloScraperService
  def self.call
    url = "https://alcambio.app" # Cambia esta URL por la correcta

    begin
      # Configurar Selenium con Chrome
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless') # Ejecutar en modo headless (sin interfaz gráfica)
      options.add_argument('--disable-gpu')
      options.add_argument('--no-sandbox')
      options.add_argument('--disable-dev-shm-usage')

      # Inicializar el navegador
      driver = Selenium::WebDriver.for(:chrome, options: options)
      driver.navigate.to(url)

      # Esperar a que el contenido se cargue (ajusta el tiempo según sea necesario)
      sleep 5

      # Obtener el HTML renderizado
      html = driver.page_source
      doc = Nokogiri::HTML(html)

      # Extraer el segundo valor del dólar paralelo
      paralelo_element = doc.css('div.change-text-container p.change-text')[1] # Selecciona el segundo <p>
      if paralelo_element.present?
        # Extraer el texto completo del <p> y limpiar el valor
        texto = paralelo_element.text.strip
        match_data = texto.match(/BS\s([\d,]+)/)

        if match_data
          dato = match_data[1]
          dato = dato.tr(',', '.') # Reemplaza la coma por punto
          dato_clean = dato.gsub(/[^\d.]/, '') # Elimina caracteres no numéricos
          tasa_valor = BigDecimal(dato_clean).round(2)

          # Actualizar el registro en la base de datos
          tasa_paralelo = TasaCambio.find_by(description: "Dolar Paralelo")
          tasa_paralelo.update(valor: tasa_valor)

          Rails.logger.info "Tasa Dólar Paralelo actualizada a #{tasa_valor}"
        else
          Rails.logger.info "El texto no coincide con el formato esperado: #{texto}"
        end
      else
        Rails.logger.info "No se pudo encontrar el elemento con el valor del dólar paralelo."
      end

      # Cerrar el navegador
      driver.quit

      dato
    rescue => e
      Rails.logger.error "Error en ParaleloScraperService: #{e.message}"
      nil
    end
  end
end