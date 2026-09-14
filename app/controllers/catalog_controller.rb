class CatalogController < ApplicationController
  def index
    @categories = EquipmentCategory.where(active: true).order(:name)
    @items = CatalogItem.all
    @items = @items.where(category: params[:category]) if params[:category].present?
    if params[:q].present?
      @items = @items.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(100))}%")
    end
    @page = [params[:page].to_i, 1].max
    @items = @items.order(:name, :id).limit(24).offset((@page - 1) * 24)
  end
  def show
    @item = CatalogItem.find(params[:id])
  end
end
