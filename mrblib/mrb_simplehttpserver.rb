class TCPServer
  def accept
    BasicSocket.for_fd(self.sysaccept)
  end
end

class SimpleHttpServer
  SEP = "\r\n"
  RECV_BUF = 1024
  HTTP_VERSION = "HTTP/1.0"
  # TODO: Add other HTTP status code and message
  STATUS_CODE_MAP = {

    200 => "OK",
    404 => "Not Found",
    500 => "Internal Server Error",
    503 => "Service Unavailable",

  }

  attr_reader :config
  attr_accessor :response_body, :response_headers

  def self.status_line code=200
    "#{HTTP_VERSION} #{code} #{STATUS_CODE_MAP[code]}"
  end

  def initialize config
    @config = config
    @host = config[:server_ip]
    @port = config[:port]
    @nonblock = config[:nonblock]
    @server = nil
    @httpinit = nil
    @locconf = {}

    # init per request
    @r = nil
    @response_headers = {}
    @response_body = nil
  end

  def debug msg
    p msg if @config[:debug]
  end


  def run
    @server ||= TCPServer.new @host, @port
    while true
      conn = nil
      begin
        conn = @nonblock ? @server.accept_nonblock : @server.accept
      rescue
        return
      end

      # send response to client
      begin
        data = ''
        while true
          buf = conn.recv RECV_BUF
          data << buf
          break if buf.size != RECV_BUF
        end

        # for safari's POST method
        if data[0] == 'P'
          if data.split("\r\n\r\n")[1] == nil
            while true
              buf = conn.recv RECV_BUF
              data << buf
              break if buf.size != RECV_BUF
            end
          end
        end
        
        # init per request
        @r = HTTP::Parser.new.parse_request data
        @response_headers = {}
        @response_body = nil
        # init block called
        unless @httpinit.nil?
          @httpinit.call @r
        end

        # checking location config
        key = check_location(@r.path)

        unless key.nil?
          response = @locconf[key].call @r
          conn.send response, 0
        else
          # default response when can't found location config
          if @r.method == "GET"
            error_404_response conn, @r
          elsif @r.method == "POST"
            error_503_response conn
          else
            error_503_response conn
          end
        end
      ensure
        debug "close: #{@r.inspect}"
        conn.close
      end
    end
  end

  def set_response_headers headers
    @response_headers = @response_headers.merge headers
  end

  def create_response code=200
    set_response_headers "content-length" => @response_body.size
    headers_ary = []
    @response_headers.keys.each do |k|
      unless @response_headers[k].nil?
        headers_ary << ["#{k.upcase.capitalize}: #{@response_headers[k]}"]
      end
    end
    SimpleHttpServer.status_line(code) + SEP + headers_ary.join("\r\n") + SEP * 2 + @response_body
  end

  def error_404_response socket, r
    @response_body = "Not Found on this server: #{r.path}\n"
    socket.send create_response(404), 0
  end

  def error_503_response socket
    @response_body = "Service Unavailable\n"
    socket.send create_response(503), 0
  end

  def http &blk
    @httpinit = blk
  end

  def location url, &blk
    @locconf[url] = blk
  end

  def check_location path
    locations = @locconf.keys.sort{|a, b| b.size <=> a.size}
    locations.each do |key|
      if path.to_s.index(key) == 0
        return key
      end
    end
    nil
  end

  def http_date
    t = Time.new.gmtime.to_s
    tp = t.split " "
    "#{tp[0]}, #{tp[2]} #{tp[1]} #{tp[5]} #{tp[3]} GMT"
  end

  def file_response r, filename
    response = ""
    begin
      fp = File.open filename
      set_response_headers "Content-Type" => "text/html; charset=utf-8"
      # TODO: Add last-modified header, need File.mtime but not implemented
      @response_body = fp.read
      response = create_response
    rescue File::FileError
      set_response_headers "Content-Type" => nil
      @response_body = "Not Found on this server: #{r.path}\n"
      response = create_response 404
    rescue
      set_response_headers "Content-Type" => nil
      @response_body = "Internal Server Error\n"
      response = create_response 500
    ensure
      fp.close if fp
    end
    response
  end

end

class String

  def is_dir?
    self[-1] == '/'
  end

  def is_html?
    self.split(".")[-1] == "html"
  end

end
