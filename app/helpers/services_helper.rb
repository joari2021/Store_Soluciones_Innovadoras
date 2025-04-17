module ServicesHelper
  def link_to_add_service_managers(name, m, association)
    new_object = m.object.send(association).klass.new
    id = new_object.object_id
    fields = m.fields_for(association, new_object, child_index: id) do |builder|
      render(association.to_s.singularize + "_fields", m: builder)
    end
    link_to(name, "#", class: "badge bg-info", id: "add_fields_service_managers", data: { id: id, fields: fields.gsub("\n", "") })
  end
end
