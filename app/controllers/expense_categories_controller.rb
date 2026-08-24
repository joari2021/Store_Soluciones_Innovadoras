class ExpenseCategoriesController < ApplicationController
  before_action :require_business
  before_action :require_admin
  before_action :set_expense_category, only: %i[edit update destroy]

  def index
    @expense_category = ExpenseCategory.new
    @expense_categories = ExpenseCategory.order(Arel.sql('LOWER(name) ASC'))
    @expense_counts_by_category_id = current_business.expenses.group(:expense_category_id).count
  end

  def create
    @expense_category = ExpenseCategory.new(expense_category_params)
    @expense_category.business = current_business if @expense_category.business_id.blank?

    if @expense_category.save
      redirect_to expense_categories_path, notice: 'Categoria de gasto creada exitosamente.'
    else
      @expense_categories = ExpenseCategory.order(Arel.sql('LOWER(name) ASC'))
      @expense_counts_by_category_id = current_business.expenses.group(:expense_category_id).count
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @expense_categories = ExpenseCategory.where.not(id: @expense_category.id).order(Arel.sql('LOWER(name) ASC'))
    @expense_counts_by_category_id = current_business.expenses.group(:expense_category_id).count
  end

  def update
    if @expense_category.update(expense_category_params)
      redirect_to expense_categories_path, notice: 'Categoria de gasto actualizada exitosamente.'
    else
      @expense_categories = ExpenseCategory.where.not(id: @expense_category.id).order(Arel.sql('LOWER(name) ASC'))
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
    @expense_category = ExpenseCategory.find(params[:id])
  end

  def expense_category_params
    params.require(:expense_category).permit(:name)
  end
end
