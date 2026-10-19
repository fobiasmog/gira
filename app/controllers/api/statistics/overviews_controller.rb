class Api::Statistics::OverviewsController < Api::BaseController
  include StatisticsSubject

  def show
    render json: statistics.overview
  end
end
