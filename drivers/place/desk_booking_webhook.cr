module Place; end

require "http/client"

class Place::DeskBookingWebhook < PlaceOS::Driver
  descriptive_name "Desk Booking Webhook"
  generic_name :DeskBookingWebhook
  description %(sends a webhook with booking information as it changes)

  accessor staff_api : StaffAPI_1

  default_settings({
    post_uri: "https://remote-server/path",
    building: "zone-id",

    custom_headers: {
      "API_KEY" => "123456",
    },

    # how many days from now do we want to send
    days_from_now: 14,

    booking_category: "desk",
  })

  def on_load
    monitor("staff/booking/changed") do |_subscription, payload|
      logger.debug { "received booking changed event #{payload}" }
      fetch_and_post
    end
    schedule.every(24.hours) { fetch_and_post }
    on_update
  end

  @time_period : Time::Span = 14.days
  @booking_category : String = "desk"
  @custom_headers = {} of String => String
  @building = ""
  @post_uri = ""

  def on_update
    @post_uri = setting(String, :post_uri)
    @building = setting(String, :building)
    @custom_headers = setting(Hash(String, String), :custom_headers)
    @time_period = setting(Int32, :days_from_now).days
    @booking_category = setting(String, :booking_category)

    fetch_and_post
  end

  def fetch_and_post
    period_start = Time.utc.to_unix
    period_end = @time_period.from_now.to_unix
    zones = {@building}
    payload = staff_api.query_bookings(@booking_category, period_start, period_end, zones).get.to_json

    headers = HTTP::Headers.new
    @custom_headers.each { |key, value| headers[key] = value }
    headers["Content-Type"] = "application/json; charset=UTF-8"

    response = HTTP::Client.post @post_uri, headers, body: payload
    response.status_code
  end
end
