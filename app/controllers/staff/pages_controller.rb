module Staff
  class PagesController < BaseController
    before_action -> { authorize!("content.manage") }
    def index
      @pages = ContentPage.order(:title)
    end
    def edit
      @page = ContentPage.find(params[:id])
    end
    def update
      Workflow.run do
        Workflow.authorize!(current_user, "content.manage")
        page = ContentPage.find(params[:id])
        page.update!(params.require(:content_page).permit(:title, :body_markdown).to_h.merge("updated_by" => current_user.id, "published_at" => params[:publish] == "1" ? Time.current : nil))
        Audit.record!(current_user, "content.updated", page)
      end
      redirect_to staff_pages_path, notice: "Page saved."
    end
  end
end
