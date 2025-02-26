# app/jobs/bcv_scrape_job.rb
class BcvScrapeJob < ApplicationJob
  queue_as :default

  def perform(*args)
    # Llama al service object para realizar el scraping
    BcvScraperService.call
  end
end
