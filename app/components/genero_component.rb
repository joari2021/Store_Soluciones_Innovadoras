# frozen_string_literal: true

class GeneroComponent < ViewComponent::Base
  attr_reader :genero

  def initialize(genero: nil)
    @genero = genero
  end

  def title
    genero ? genero.genero : t('.all')
  end

  def link
    genero ? peliculas_path(genero_id: genero.id) : peliculas_path
  end

  def active?
    return true if !genero && !params[:genero_id]
    genero&.id == params[:genero_id].to_i
  end

  def classes
    "genero text-gray-600 px-4 py-2 rounded-2xl drop-shadow-sm hover:bg-gray-300 #{background}"
  end

  private

  def background
    active? ? "bg-gray-300" : "bg-white"
  end
end
