class PagesController < ApplicationController
  def show
    @page = ContentPage.where("published_at <= ?", Time.current).find_by!(slug: params[:slug])
  end
end
