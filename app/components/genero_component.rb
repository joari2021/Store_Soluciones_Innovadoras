# frozen_string_literal: true

class GeneroComponent < ViewComponent::Base
  attr_reader :genero

  def initialize(genero: nil)
    @genero = genero
  end

  def title
    genero ? genero.name : "Todos"
  end

  def link
    genero ? peliculas_path(genero_id: genero.id) : peliculas_path
  end

  def classes
    "genero nav__link nav__link--inside"
  end

  def classesTwo
    "genre-link #{active}"
  end

  def active
    genero&.name == title ? "list__inside" : "list__active"
  end
end
