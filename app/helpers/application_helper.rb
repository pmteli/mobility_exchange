module ApplicationHelper
  def status_badge(status)
    tag.span(status.to_s.humanize, class: "badge badge-#{status.to_s.parameterize}")
  end
  def local_time(time, timezone = "America/Los_Angeles")
    time&.in_time_zone(timezone)&.strftime("%b %-d, %Y · %-I:%M %p %Z")
  end
  def staff_access?
    %w[inventory.read intake.review distribution.manage shifts.manage content.manage reports.read users.manage].any? { |permission| allowed?(permission) }
  end
end
