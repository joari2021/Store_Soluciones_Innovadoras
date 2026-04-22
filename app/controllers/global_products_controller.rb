class GlobalProductsController < ApplicationController
  before_action :require_business
  before_action :require_admin

  def index
    @global_products = GlobalProduct
                       .includes(:source_business, :productos, :global_supplier_products)
                       .order(Arel.sql("LOWER(global_products.name) ASC"))
  end
end
