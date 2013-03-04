require 'json'
require "twochannel_util"

include TwoChannelParser

class ApplicationController < ActionController::Base
  protect_from_forgery

  def bbstable
    callback = params[:jsonp]

    map = bbstable_to_hashmap()
    res = generate_response(map, callback)

    render({:content_type => :js, :text => res})
  end

  def subject
    url = params[:url]
    callback = params[:jsonp]

    map = subject_to_hashmap(url)
    res = generate_response(map, callback)

    render({:content_type => :js, :text => res})
  end

  def thread
    url = params[:url]

    show_aa = str_to_bool(params[:show_aa], true)
    escape_nl = str_to_bool(params[:escape_nl], false)
    refs = str_to_bool(params[:refs], false)
    callback = params[:jsonp]

    map = thread_to_hashmap(url, show_aa, escape_nl, refs)
    res = generate_response(map, callback)

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

  def generate_response(map, callback)
    json = JSON.generate(map)

    res =
      if callback # JSONP
        "#{callback}(#{json});"
      else        # JSON
        json
      end

    return res
  end
end
