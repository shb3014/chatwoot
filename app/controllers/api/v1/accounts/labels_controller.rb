class Api::V1::Accounts::LabelsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_label, except: [:index, :create, :reorder]
  before_action :check_authorization

  def index
    @labels = policy_scope(Current.account.labels)
  end

  def show; end

  def create
    @label = Current.account.labels.create!(permitted_params)
  end

  def update
    @label.update!(permitted_params)
  end

  def destroy
    @label.destroy!
    head :ok
  end

  def reorder
    positions = params.require(:positions).permit!.to_h
    ActiveRecord::Base.transaction do
      positions.each do |id, position|
        Current.account.labels.find(id).update!(position: position.to_i)
      end
    end
    head :ok
  end

  private

  def fetch_label
    @label = Current.account.labels.find(params[:id])
  end

  def permitted_params
    params.require(:label).permit(:title, :description, :color, :show_on_sidebar, :ai_learning_description, :exclusive, :position,
                                  hard_rules: [:attribute_key, :filter_operator, :query_operator, { values: [] }])
  end
end
