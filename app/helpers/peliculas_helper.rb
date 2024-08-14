module PeliculasHelper
  def link_to_add_rankings(name, pf, association)
    new_object = pf.object.send(association).klass.new
    id = new_object.object_id
    fields = pf.fields_for(association, new_object, child_index: id) do |builder|
      render(association.to_s.singularize + "_fields", pf: builder)
    end
    link_to(name, "#", class: "add_fields_rankings", data: { id: id, fields: fields.gsub("\n", "") })
  end

  def link_to_add_video_details(name, vd, association)
    new_object = vd.object.send(association).klass.new
    id = new_object.object_id
    fields = vd.fields_for(association, new_object, child_index: id) do |builder|
      render(association.to_s.singularize + "_fields", vd: builder)
    end
    link_to(name, "#", class: "add_fields_video_details", data: { id: id, fields: fields.gsub("\n", "") })
  end
end
