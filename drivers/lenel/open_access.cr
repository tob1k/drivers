require "placeos-driver"
require "time"

class Lenel::OpenAccess < PlaceOS::Driver; end
require "./open_access/client"

class Lenel::OpenAccess < PlaceOS::Driver
  include OpenAccess::Models

  generic_name :Security
  descriptive_name "Lenel OpenAccess"
  description "Bindings for Lenel OnGuard physical security system"
  uri_base "https://example.com/api/access/onguard/openaccess"
  default_settings({
    application_id: "",
    directory_id:   "",
    username:       "",
    password:       "",
  })

  private getter client : OpenAccess::Client do
    transport = PlaceOS::HTTPClient.new self
    app_id = setting String, :application_id
    OpenAccess::Client.new transport, app_id
  end

  def on_load
    schedule.every 5.minutes do
      logger.debug { "checking service connectivity" }
      version
    end
  end

  def on_update
    authenticate!
  end

  def connected
    authenticate! if client.token.nil?
  end

  def authenticate! : Nil
    username  = setting String, :username
    password  = setting String, :password
    directory = setting String, :directory_id

    logger.debug { "requesting access token for #{username}" }

    begin
      auth = client.add_authentication username, password, directory
      client.token = auth[:session_token]

      renewal_time = auth[:token_expiration_time] - 5.minutes
      schedule.at renewal_time, &->authenticate!

      logger.info { "authenticated - renews at #{renewal_time}" }

      set_connected_state true
    rescue e
      logger.error { "authentication failed" }
      client.token = nil
      set_connected_state false
      raise e
    end
  end

  # Gets the version of the attached OnGuard system.
  def version
    client.version
  end

  # TODO: remove me, temp for testing
  def get_test
    client.get_instances Lnl_AccessGroup
  end
end


################################################################################
#
# FIXME
#
# Warning: nasty hacks below. These are intended as a _temporary_ measure to
# modify the behaviour of the driver framework as a POC.
#
# The intent is to provide a `HTTP::Client`-ish object that uses the underlying
# queue and config. This provides a familiar interface for users, but
# importantly also allows it to be passed as a compatible object to client libs
# that may already exist for the service being integrated.
#

abstract class PlaceOS::Driver::Transport
  def before_request(&callback : HTTP::Request ->)
    before_request = @before_request ||= [] of (HTTP::Request ->)
    before_request << callback
  end

  private def install_middleware(client : HTTP::Client)
    client.before_request do |req|
      @before_request.try &.each &.call(req)
    end
  end
end

class PlaceOS::Driver::TransportTCP
  def new_http_client(uri, context)
    previous_def.tap &->install_middleware(HTTP::Client)
  end
end

class PlaceOS::Driver::TransportHTTP
  def new_http_client(uri, context)
    previous_def.tap &->install_middleware(HTTP::Client)
  end
end

class PlaceOS::HTTPClient < HTTP::Client
  def initialize(@driver : PlaceOS::Driver)
    @host = ""
    @port = -1
  end

  delegate get, post, put, patch, delete, to: @driver

  def before_request(&block : HTTP::Request ->)
    @driver.transport.before_request &block
  end
end
