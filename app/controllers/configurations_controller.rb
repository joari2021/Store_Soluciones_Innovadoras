class ConfigurationsController < ApplicationController
  before_action :require_business
  before_action :require_admin

  def index
  end
end
