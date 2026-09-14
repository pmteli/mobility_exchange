module Staff
  class EquipmentController < BaseController
    before_action -> { authorize!("inventory.read") }, only: [:index, :show]
    before_action -> { authorize!("inventory.write") }, only: [:new, :create, :edit, :update]
    before_action -> { authorize!("inventory.process") }, only: :process_item
    def index
      @equipment = Equipment.where(archived_at: nil).includes(:location).order(created_at: :desc)
      @equipment = @equipment.where(status_code: params[:status]) if params[:status].present?
      @equipment = @equipment.limit(100)
    end
    def show
      @equipment = Equipment.find(params[:id])
      @transitions = InventoryTransition.where(from_status: @equipment.status_code).where.not(to_status: %w[reserved distributed]).pluck(:to_status)
      @transitions = [] if @equipment.status_code == "reserved"
    end
    def new
      @equipment = Equipment.new(condition: "good")
    end
    def create
      item = Workflow.run do
        Workflow.authorize!(current_user, "inventory.write")
        record = Equipment.create!(equipment_params.merge(inventory_number: Workflow.reference("MX"), acquisition_kind: "legacy", received_at: Time.current, created_by: current_user.id, updated_by: current_user.id))
        Audit.record!(current_user, "equipment.created", record)
        record
      end
      redirect_to staff_equipment_path(item), notice: "Equipment received. Begin inspection next."
    end
    def edit
      @equipment = Equipment.find(params[:id])
    end
    def update
      Workflow.run do
        Workflow.authorize!(current_user, "inventory.write")
        item = Equipment.find(params[:id])
        attrs = equipment_params
        if item.status_code.in?(%w[reserved distributed]) && attrs[:location_id] != item.location_id
          raise Workflow::Error, "Reserved or distributed equipment cannot move locations."
        end
        item.update!(attrs.merge(updated_by: current_user.id))
        Audit.record!(current_user, "equipment.updated", item)
      end
      redirect_to staff_equipment_path(params[:id]), notice: "Equipment updated."
    end
    def process_item
      ProcessEquipment.call(current_user, params[:id], params[:target], params[:notes])
      redirect_to staff_equipment_path(params[:id]), notice: "Processing step recorded."
    end
    private
    def equipment_params
      params.require(:equipment).permit(:name, :type_id, :condition, :location_id, :manufacturer, :model, :serial_number, :description, :public_notes, :storage_position).to_h.symbolize_keys
    end
  end
end
