# Immutable UI examples only: never read accounts, evidence or private workflow data.
class DesignPreviewController < ApplicationController
  SCREENS = %w[catalog item donor recipient moderator donate edit registration signin].freeze
  before_action { @design_preview = true }

  def index; end

  def show
    @screen = params[:screen]
    @preview_item = params[:item].to_i.clamp(1, 7)
    raise ActiveRecord::RecordNotFound unless SCREENS.include?(@screen)
  end
end
