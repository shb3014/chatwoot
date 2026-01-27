class Api::V1::Accounts::Captain::LearnedConversationsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  before_action :set_current_page, only: [:index]
  before_action :set_learning, only: [:show, :destroy]

  RESULTS_PER_PAGE = 25

  def index
    filtered_query = apply_filters(base_scope)
    @learned_conversations_count = filtered_query.count
    @learned_conversations = filtered_query.page(@current_page).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    conversation = Current.account.conversations.find_by!(display_id: permitted_params[:conversation_id])
    force = ActiveModel::Type::Boolean.new.cast(permitted_params[:force])

    @learning = Captain::ConversationLearningService.new(conversation).learn!(force: force)
    return render json: { error: 'Conversation learning failed' }, status: :unprocessable_entity if @learning.blank?

    render :show
  end

  def destroy
    @learning.update!(
      status: :forgotten,
      issue_summary: nil,
      resolution_summary: nil,
      quality_rating: nil,
      rejection_reason: nil,
      rejected_at: nil,
      learned_at: nil,
      embedding: nil
    )
    @learning.conversation&.touch(:updated_at)
    head :no_content
  end

  private

  def base_scope
    Current.account.captain_conversation_learnings.includes(:conversation, :assistant).ordered
  end

  def apply_filters(base_query)
    base_query = base_query.where(assistant_id: permitted_params[:assistant_id]) if permitted_params[:assistant_id].present?
    base_query = base_query.where(status: permitted_params[:status]) if permitted_params[:status].present?

    if permitted_params[:conversation_id].present?
      base_query = base_query.joins(:conversation).where(conversations: { display_id: permitted_params[:conversation_id] })
    end

    if permitted_params[:search].present?
      search_term = "%#{permitted_params[:search]}%"
      base_query = base_query.where('issue_summary ILIKE :search OR resolution_summary ILIKE :search', search: search_term)
    end

    base_query
  end

  def set_learning
    @learning = Current.account.captain_conversation_learnings.find(permitted_params[:id])
  end

  def set_current_page
    @current_page = permitted_params[:page] || 1
  end

  def permitted_params
    params.permit(:id, :page, :assistant_id, :status, :search, :conversation_id, :force)
  end
end
