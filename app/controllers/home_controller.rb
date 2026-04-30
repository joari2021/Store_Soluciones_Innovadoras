class HomeController < ApplicationController
  def index
    redirect_to default_authenticated_path
  end
end