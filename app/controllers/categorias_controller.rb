class CategoriasController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_categoria, only: %i[edit update destroy]

  def index
    @categoria = current_business.categorias.new
    @categorias = current_business.categorias.order(nombre: :asc)
    @product_counts_by_categoria_id = current_business.productos.group(:categoria_id).count
  end

  def create
    @categoria = current_business.categorias.new(categoria_params)

    if @categoria.save
      redirect_to categorias_path, notice: 'Categoria creada exitosamente.'
    else
      @categorias = current_business.categorias.order(nombre: :asc)
      @product_counts_by_categoria_id = current_business.productos.group(:categoria_id).count
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @categorias = current_business.categorias.where.not(id: @categoria.id).order(nombre: :asc)
    @product_counts_by_categoria_id = current_business.productos.group(:categoria_id).count
  end

  def update
    if @categoria.update(categoria_params)
      redirect_to categorias_path, notice: 'Categoria actualizada exitosamente.'
    else
      @categorias = current_business.categorias.where.not(id: @categoria.id).order(nombre: :asc)
      @product_counts_by_categoria_id = current_business.productos.group(:categoria_id).count
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @categoria.destroy
      redirect_to categorias_path, notice: 'Categoria eliminada exitosamente.'
    else
      message = @categoria.errors.full_messages.to_sentence.presence || 'No se pudo eliminar la categoria.'
      redirect_to categorias_path, alert: message
    end
  end

  private

  def set_categoria
    @categoria = current_business.categorias.find(params[:id])
  end

  def categoria_params
    params.require(:categoria).permit(:nombre)
  end
end
