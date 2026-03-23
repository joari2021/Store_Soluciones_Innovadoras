class HeaderNotificationsController < ApplicationController
  before_action :require_business

  def destroy
    kind = params[:id].to_s
    active_kinds = @header_notifications.map { |notification| notification[:kind].to_s }

    dismissed_kinds = dismissed_header_notification_kinds
    dismissed_kinds << kind if active_kinds.include?(kind)
    persist_dismissed_header_notification_kinds(dismissed_kinds.uniq)

    set_header_notifications

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            'notifications-indicator',
            view_context.tag.span(
              view_context.render(partial: 'shared/header_notifications_indicator').html_safe,
              id: 'notifications-indicator'
            )
          ),
          turbo_stream.replace(
            'notifications-list',
            view_context.render(partial: 'shared/header_notifications_list')
          )
        ]
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end
end
