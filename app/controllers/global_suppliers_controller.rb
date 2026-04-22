class GlobalSuppliersController < ApplicationController
  before_action :require_business
  before_action :require_admin

  def index
    @global_suppliers = GlobalSupplier
                        .includes(:source_business, :suppliers, :global_supplier_products)
                        .order(Arel.sql("LOWER(global_suppliers.name) ASC"))
  end
end
