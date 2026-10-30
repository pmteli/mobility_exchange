class PhotoScreeningsController < AuthenticatedController
  def create
    Journeys::Workflow.new(current_account).member!
    photo = EquipmentMedia::Photos.prepare(params[:photo])
    result = EquipmentMedia::Moderation.check(EquipmentMedia::Photos.path(photo[:sanitized_object_key]), current_account)
    response.headers["Cache-Control"] = "no-store"
    render json: result, status: result[:state] == "unavailable" ? :service_unavailable : :ok
  rescue Journeys::Error => error
    render json: {state: "unavailable", message: error.message}, status: :unprocessable_entity
  ensure
    FileUtils.rm_f(EquipmentMedia::Photos.path(photo[:sanitized_object_key])) if photo
  end
end
