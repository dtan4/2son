require 'json'
require "twochannel_util"

include TwoChannelParser

class ApplicationController < ActionController::Base
  protect_from_forgery

  def thread
    url = params[:url]

    show_aa = str_to_bool(params[:showaa], true)
    escape_nl = str_to_bool(params[:escapenl], false)
    callback = params[:callback]

    map = thread_to_hashmap(url, show_aa, escape_nl)
    json = JSON.generate(map)

    res =
      if callback # JSONP
        "#{callback}(#{json});"
      else        # JSON
        json
      end

    render({:content_type => :js, :text => res})
  end

  private
  def str_to_bool(str, default)
    if str
      if str.downcase == "true"
        return true
      else
        return false
      end
    end

    return default
  end
end
