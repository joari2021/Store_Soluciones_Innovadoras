require 'prawn'
require 'tempfile'

class BeerTicketsPdfGenerator
  CM_TO_PT = 28.3464567
  TICKET_WIDTH = 5.0 * CM_TO_PT
  TICKET_HEIGHT = 2.0 * CM_TO_PT

  SERIAL_STYLE = {
    size: 10,
    style: :italic,
    align: :right,
  }.freeze

  def initialize(batch:, view_context: nil)
    @batch = batch
    @view_context = view_context
    @product = batch.producto
  end

  def render
    Prawn::Document.new(page_size: 'LETTER', margin: 0) do |pdf|
      draw_pages(pdf)
    end.render
  end

  private

  attr_reader :batch, :view_context, :product

  def draw_pages(pdf)
    serials = (batch.start_serial..batch.end_serial).to_a
    tickets_per_page = grid_columns(pdf) * grid_rows(pdf)

    serials.each_slice(tickets_per_page).with_index do |slice, page_index|
      pdf.start_new_page unless page_index.zero?
      draw_slice(pdf, slice)
    end
  end

  def draw_slice(pdf, serials)
    cols = grid_columns(pdf)
    rows = grid_rows(pdf)
    left_margin = ((pdf.bounds.width - (cols * TICKET_WIDTH)) / 2.0).round(4)
    top_margin = ((pdf.bounds.height - (rows * TICKET_HEIGHT)) / 2.0).round(4)

    serials.each_with_index do |serial, index|
      col = index % cols
      row = index / cols

      x = left_margin + (col * TICKET_WIDTH)
      y = pdf.bounds.top - top_margin - (row * TICKET_HEIGHT)
      draw_ticket(pdf, x:, y:, serial: serial)
    end
  end

  def draw_ticket(pdf, x:, y:, serial:)
    box_height = TICKET_HEIGHT

    draw_background(pdf, x: x, y: y, width: TICKET_WIDTH, height: box_height)
    draw_product_image(pdf, x: x, y: y, width: TICKET_WIDTH, height: box_height)
    draw_serial(pdf, x: x, y: y, width: TICKET_WIDTH, height: box_height, serial: serial)
  end

  def draw_background(pdf, x:, y:, width:, height:)
    background_path = Rails.root.join('app/assets/images/ticket cervezas.jpg')
    return unless File.exist?(background_path)

    pdf.image background_path.to_s,
              at: [x, y],
              width: width,
              height: height,
              fit: [width, height]
  end

  def draw_product_image(pdf, x:, y:, width:, height:)
    image_path = product_image_path
    return if image_path.blank?

    diameter = height * 0.86
    circle_x = x + (width * 0.20)
    circle_y = y - (height * 0.20)

    # Draw a white circular base and place the product image inside.
    # Using simple positioning here avoids unsupported clipping APIs in production.
    pdf.save_graphics_state do
      previous_fill_color = pdf.fill_color
      pdf.fill_color 'FFFFFF'
      pdf.fill_circle [circle_x, circle_y], diameter / 2.0
      pdf.fill_color previous_fill_color

      image_w = diameter * 0.72
      image_h = diameter * 1.05
      image_x = circle_x - (image_w / 2.0)
      image_y = circle_y + (image_h / 2.0) - (diameter * 0.08)
      pdf.image image_path, at: [image_x, image_y], width: image_w, height: image_h
    end
  end

  def draw_serial(pdf, x:, y:, width:, height:, serial:)
    serial_text = format('%04d', serial.to_i)
    serial_x = x + (width * 0.77)
    serial_y = y - (height * 0.79)

    pdf.font('Times-Roman') do
      pdf.text_box serial_text,
                   at: [serial_x, serial_y],
                   width: width * 0.19,
                   height: 14,
                   size: SERIAL_STYLE[:size],
                   style: SERIAL_STYLE[:style],
                   align: SERIAL_STYLE[:align]
    end
  end

  def product_image_path
    return @product_image_path if defined?(@product_image_path)
    @product_image_path = nil
    return @product_image_path unless product&.foto&.attached?

    extension = product.foto.blob.filename.extension_with_delimiter.presence || '.jpg'
    @product_image_tempfile = Tempfile.new(['beer-ticket-product', extension])
    @product_image_tempfile.binmode
    @product_image_tempfile.write(product.foto.download)
    @product_image_tempfile.flush
    @product_image_path = @product_image_tempfile.path
  rescue StandardError
    nil
  end

  def grid_columns(pdf)
    [(pdf.bounds.width / TICKET_WIDTH).floor, 1].max
  end

  def grid_rows(pdf)
    [(pdf.bounds.height / TICKET_HEIGHT).floor, 1].max
  end
end
