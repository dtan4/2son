require 'json'
require "twochannel_util"

include TwoChannelParser

class ApplicationController < ActionController::Base
  protect_from_forgery

  def thread
    url = params[:url]

    skip_aa = params[:showaa]
    skip_nl = params[:shownl]
    callback = params[:callback]

    map = thread_to_hashmap(url, skip_aa, skip_nl)
    json = JSON.generate(map)

    res =
      if callback
        "#{callback}(#{json});"
      else
        json
      end

    render({:content_type => :js, :text => res})
  end
end
