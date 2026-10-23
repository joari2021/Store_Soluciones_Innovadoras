module BeerTicketLayoutHelper
  # Single source of truth for ticket overlay geometry.
  # Both preview and print views must consume these values.
  def beer_ticket_layout_config
    {
      product_left_pct: 19.5,
      product_top_pct: 25.5,
      product_height_pct: 48.0,
      product_scale: 1.3,
      product_translate_y_pct: 12.0,
      serial_right_pct: 15.5,
      serial_bottom_pct: 7.8,
      serial_font_cm: 0.25,
      serial_font_preview_rem: 0.82,
    }
  end
end
