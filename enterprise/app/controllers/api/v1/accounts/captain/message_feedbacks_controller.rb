class Api::V1::Accounts::Captain::MessageFeedbacksController < Api::V1::Accounts::BaseController
  before_action :set_message

  def create
    service = Captain::MessageFeedbackService.new(@message, Current.user)
    result = service.record_feedback(
      rating: params[:rating].to_i,
      feedback_type: params[:feedback_type],
      notes: params[:notes]
    )

    if result[:success]
      render json: { feedback: result[:feedback] }, status: :created
    else
      render json: { errors: result[:errors] }, status: :unprocessable_entity
    end
  end

  def update
    feedback = CaptainMessageFeedback.find_by!(
      message_id: params[:message_id],
      rated_by: Current.user
    )

    if feedback.update(feedback_params)
      render json: { feedback: feedback }
    else
      render json: { errors: feedback.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_message
    @message = Message.find(params[:message_id])
    authorize @message.conversation.inbox, :show?
  end

  def feedback_params
    params.permit(:rating, :feedback_type, :notes, :issue_resolved, :resolution_method)
  end
end
