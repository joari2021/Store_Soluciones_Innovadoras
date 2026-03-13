class BybitUsdtScrapeJob < ApplicationJob
  queue_as :default

  def perform(*)
    BybitUsdtScraperService.call
  end
end
