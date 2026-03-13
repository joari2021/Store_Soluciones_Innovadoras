module ApplicationHelper
  include Pagy::Frontend

  def truncated_name(name, length = 20, omission = "...")
    if name.length > length
      "#{name[0, length]}#{omission}"
    else
      name
    end
  end

  def format_money(value, unit: "", precision: 2)
    number_to_currency(
      value || 0,
      unit: unit,
      precision: precision,
      separator: ",",
      delimiter: ".",
      format: unit.present? ? "%u\u00A0%n" : "%n"
    )
  end

  def format_quantity(value, precision: 2)
    number_with_precision(
      value || 0,
      precision: precision,
      separator: ",",
      delimiter: ".",
      strip_insignificant_zeros: true
    )
  end
end
