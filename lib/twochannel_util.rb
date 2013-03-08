#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'net/http'
require 'uri'
require 'stringio'
require 'zlib'
require 'nkf'

module TwoChannelParser
  BBSTABLE_URL = "http://menu.2ch.net/bbstable.html"

  def bbstable_to_hashmap
    res = fetch_url(BBSTABLE_URL)
    bbstable = {}

    case res
    when Net::HTTPOK
      bbstable["result"] = true
      body = extract_gz(res.body)
      board_map = parse_bbstable_body(body)
      bbstable["board"] = board_map
      bbstable["count"] = board_map.length
    else
      bbstable["result"] = false
    end

    return bbstable
  end

  def subject_to_hashmap(board_url)
    subject_url = get_subject_url(board_url)
    res = fetch_url(subject_url)
    subject = {"board_url" => board_url}

    case res
    when Net::HTTPOK
      subject["result"] = true
      body = extract_gz(res.body)
      subject_map = parse_subject_body(body)
      subject["subject"] = subject_map
      subject["count"] = subject_map.length
    else
      subject["result"] = false
    end

    return subject
  end

  def thread_to_hashmap(thread_url, show_aa, escape_nl, show_refs)
    dat_url, kako_url = get_dat_url(thread_url)
    res = fetch_url(dat_url)
    thread = {"thread_url" => thread_url}

    case res
    when Net::HTTPOK
      thread["result"] = true
      thread["archived"] = false
      body = extract_gz(res.body)
      res_map, title = parse_dat_body(body, show_aa, escape_nl, show_refs)
      thread["title"] = title
      thread["res"] = res_map
      thread["count"] = res_map.length
    when Net::HTTPNonAuthoritativeInformation
      kako_res = fetch_url(kako_url)

      case kako_res
      when Net::HTTPSuccess # dat 落ち
        thread["result"] = true
        thread["archived"] = true
        body = extract_gz(kako_res.body)
        res_map, title = parse_dat_body(body, show_aa, escape_nl, show_refs)
        thread["title"] = title
        thread["res"] = res_map
        thread["count"] = res_map.length
      else
        thread["result"] = false
      end
    else
      thread["result"] = false
    end

    return thread
  end

  private
  def get_subject_url(board_url)
    if board_url && validate_board_url(board_url)
      arr = board_url.split('/')
      host = arr[2]
      board = arr[3]

      subject_url =
        "http://#{host}/#{board}/subject.txt"

      return subject_url
    else
      return nil
    end
  end

  def get_dat_url(thread_url)
    if thread_url && validate_thread_url(thread_url)
      arr = thread_url.split('/')
      host = arr[2]
      board = arr[5]
      thread_no = arr[6]

      dat_url =
        "http://#{host}/#{board}/dat/#{thread_no}.dat"
      kako_url =
        "http://mimizun.com/log/2ch/#{board}/#{thread_no}.dat"

      return dat_url, kako_url
    else
      return nil
    end
  end

  def validate_board_url(board_url)
    return (/http:\/\/[0-9a-z.]+\.2ch\.net\/[0-9a-z]+.*/ =~ board_url)
  end

  def validate_thread_url(thread_url)
    return (/http:\/\/[0-9a-z.]+\.2ch\.net\/test\/read\.cgi\/[0-9a-z]+\/\d+.*/ =~ thread_url)
  end

  def fetch_url(dat_url)
    uri = URI.parse(dat_url)
    req = Net::HTTP::Get.new(uri.path)
    # http://info.2ch.net/wiki/index.php?monazilla%2Fdevelop%2Faccess
    req.add_field("User-Agent", "Monazilla/1.00")
    req.add_field("Accept-Encoding", "gzip")
    res = Net::HTTP.start(uri.host, uri.port) do |http|
      http.request(req)
    end

    return res
  end

  def extract_gz(body_gz)
    body = StringIO.open(body_gz, 'rb') do |sio|
      Zlib::GzipReader.wrap(sio).read
    end

    return body
  end

  def parse_bbstable_body(body)
    # Shift-JIS -> UTF-8
    bbstable_body = NKF.nkf("-w", body)
    board = {}

    if /<font size=2>(.*)<\/font>/m =~ bbstable_body
      bbstable_body = $1
      category = "no category"
      board = {category => []}

      bbstable_body.each_line do |line|
        # 空行を弾く
        if /^\s+$/ =~ line
          next
        end

        if /【<B>(.+)<\/B>】/ =~ line
          category = $1
          board[category] = []
          next
        end

        if /<A HREF=(.+) TARGET=_blank>(.+)<\/A>/ =~ line ||
            /<A HREF=(.+)>(.+)<\/A>/ =~ line
          url = $1
          board_name = $2
          board[category] << {"url" => url, "title" => board_name}
        end
      end
    end

    return board
  end

  def parse_subject_body(body)
    # Shift-JIS -> UTF-8
    subject_body = NKF.nkf("-w", body)
    subject_map = []

    subject_body.each_line do |line|
      dat, subject, count = parse_subject_line(line)
      subject_map << {"dat" => dat, "title" => subject, "res_count" => count}
    end

    return subject_map
  end

  def parse_dat_body(body, show_aa, escape_nl, show_refs)
    # Shift-JIS -> UTF-8
    thread_body = NKF.nkf("-w", body)
    thread_title = ""

    i = 1
    res_map = {}

    thread_body.each_line do |line|
      name, email, date, id, body, refs, title =
        parse_res_line(line, show_aa, escape_nl, show_refs)

      if show_refs
        res_map[i] = {"name" => name, "email" => email, "date" => date, "id" => id,
          "body" => body, "refs" => refs.uniq.sort}
      else
        res_map[i] = {"name" => name, "email" => email, "date" => date, "id" => id,
          "body" => body}
      end

      thread_title = title if title != ""

      i = i.next
    end

    return res_map, thread_title
  end

  def parse_subject_line(line)
    line_arr = line.split("<>")
    dat = line_arr[0]
    subject = ""
    count = nil

    if /(.*)\((\d+)\)/ =~ line_arr[1]
      subject = $1.strip
      count = $2.to_i
    end

    return dat, subject, count
  end

  def parse_res_line(line, show_aa, escape_nl, show_refs)
    line_arr = line.split("<>")
    name = line_arr[0].gsub(/<\/?b>/, "")
    email = line_arr[1]
    date_and_id = line_arr[2]
    date = ""
    id = ""
    title = ""

    if date_and_id == "あぼーん"
      date = "あぼーん"
      id = "あぼーん"
    else
      if /((?:\d{4}|\d{2})\/\d{2}\/\d{2}\(.\) \d{2}:\d{2}(?::\d{2}(?:\.\d{2})*)*)/ =~ date_and_id
        date = $1
      end

      if /ID:([0-9a-zA-Z+?]{1,8})/ =~ date_and_id
        id = $1
      end
    end

    body = line_arr[3].strip

    # http://d.hatena.ne.jp/awef/20110412/1302605740
    if !show_aa && /　 (?!<br>|$)/i =~ body
      body = "<AA>"
    end

    if escape_nl
      body = body.gsub(/\s*<br>\s*/i, "\\\\n")
    else
      body = body.gsub(/\s*<br>\s*/i, " ")
    end

    body = body
      .gsub("&lt;", "<")
      .gsub("&gt;", ">")
      .gsub("&quot;", "\"")

    refs = []
    if show_refs
      body.scan(/(?:>|＞)+(\d{1,4})/).each do |match|
        refs << match[0]
      end
    end

    body = body.gsub(/<a href="(.*?)" target="_blank">(>>\d{1,4})<\/a>/i){$2}
    body = body.gsub(/<a href="(.*?)" target="_blank">/i){$1}

    if line_arr.length > 4
      thread_title = line_arr[4]
    end

    return name, email, date, id, body, refs, thread_title
  end
end
