class ExpenseCategoriesController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_expense_category, only: %i[edit update destroy]

  def index
    @expense_category = current_business.expense_categories.new
    @expense_categories = current_business.expense_categories.order(name: :asc)
    @expense_counts_by_category_id = current_business.expenses.group(:expense_category_id).count
  end

  def create
    @expense_category = current_business.expense_categories.new(expense_category_params)

    if @expense_category.save
      redirect_to expense_categories_path, notice: 'Categoria de gasto creada exitosamente.'
    else
      @expense_categories = current_business.expense_categories.order(name: :asc)
      @expense_counts_by_category_id = current_business.expenses.group(:expense_category_id).count
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @expense_categories = current_business.expense_categories.where.not(id: @expense_category.id).order(name: :asc)
    @expense_counts_by_category_id = current_business.expenses.group(:expense_category_id).count
  end

  def update
    if @expense_category.update(expense_category_params)
      redirect_to expense_categories_path, notice: 'Categoria de gasto actualizada exitosamente.'
    else
      @expense_categories = current_business.expense_categories.where.not(id: @expense_category.id).order(name: :asc)
      @expense_counts_by_category_id = current_business.expenses.group(:expense_category_id).count
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @expense_category.destroy
      redirect_to expense_categories_path, notice: 'Categoria de gasto eliminada exitosamente.'
    else
      message = @expense_category.errors.full_messages.to_sentence.presence || 'No se pudo eliminar la categoria de gasto.'
      redirect_to expense_categories_path, alert: message
    end
  end

  private

  def set_expense_category
    @expense_category = current_business.expense_categories.find(params[:id])
  end

  def expense_category_params
    params.require(:expense_category).permit(:name)
  end
end
