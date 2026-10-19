class Api::Statistics::DeadlinesController < Api::BaseController
  include StatisticsSubject

  def index
    render json: statistics.deadlines
  end
end
