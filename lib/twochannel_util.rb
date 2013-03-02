#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'net/http'
require 'uri'
require 'stringio'
require 'zlib'
require 'nkf'

module TwoChannelParser
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

  def thread_to_hashmap(thread_url, skip_aa, skip_nl)
    dat_url, kako_url = get_dat_url(thread_url)
    res = fetch_url(dat_url)
    thread = {"thread_url" => thread_url}

    case res
    when Net::HTTPOK
      thread["result"] = true
      thread["archived"] = false
      body = extract_gz(res.body)
      res_map = parse_dat_body(body, skip_aa, skip_nl)
      thread["res"] = res_map
      thread["count"] = res_map.length
    when Net::HTTPNonAuthoritativeInformation
      kako_res = fetch_url(kako_url)

      case kako_res
      when Net::HTTPSuccess
        thread["result"] = true
        thread["archived"] = true
        body = extract_gz(kako_res.body)
        res_map = parse_dat_body(body, skip_aa, skip_nl)
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

  # http://toro.2ch.net/test/read.cgi/famicom/1361411122/
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

  def parse_subject_body(body)
    # Shift-JIS -> UTF-8
    subject_body = NKF.nkf("-w", body)
    subject_map = []

    subject_body.each_line do |line|
      dat, subject, count = parse_subject_line(line)
      subject_map << {"dat" => dat, "subject" => subject, "count" => count}
    end

    return subject_map
  end

  def parse_dat_body(body, skip_aa, skip_nl)
    # Shift-JIS -> UTF-8
    thread_body = NKF.nkf("-w", body)

    i = 1
    res_map = {}

    thread_body.each_line do |line|
      name, email, date, id, body, refs = parse_res_line(line, skip_aa, skip_nl)

      res_map[i] = {"name" => name, "email" => email, "date" => date, "id" => id,
        "body" => body, "refs" => refs.uniq.sort}

      # if i == 1
      #   thread["title"] = line_arr[4].strip
      # end

      i = i.next
    end

    return res_map
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

  def parse_res_line(line, skip_aa, skip_nl)
    line_arr = line.split("<>")
    name = line_arr[0].gsub(/<\/{0,1}b>/, "")
    email = line_arr[1]
    date_and_id = line_arr[2]
    date = ""
    id = ""

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
    if skip_aa && /　 (?!<br>|$)/i =~ body
      body = "<AA>"
    end

    if skip_nl
      body = body.gsub(/\s*<br>\s*/i, " ")
    else
      body = body.gsub(/\s*<br>\s*/i, "\\\\n")
    end

    body = body
      .gsub("&lt;", "<")
      .gsub("&gt;", ">")
      .gsub("&quot;", "\"")

    refs = []
    body.scan(/(?:>|＞)+(\d{1,4})/).each do |match|
      refs << match[0]
    end

    body = body.gsub(/<a href="(.*?)" target="_blank">(>>\d{1,4})<\/a>/i){$2}
    body = body.gsub(/<a href="(.*?)" target="_blank">/i){$1}

    return name, email, date, id, body, refs
  end
end
