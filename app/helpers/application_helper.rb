module ApplicationHelper
  include Pagy::Frontend

  def truncated_name(name, length = 20, omission = "...")
    if name.length > length
      "#{name[0, length]}#{omission}"
    else
      name
    end
  end
end
