require 'socket'

class Client
  attr_reader :socket

  def initialize
    hostname = 'localhost'
    port = 8080
    @socket = TCPSocket.open(hostname, port)
  end

  def send_data(data)
    @socket.puts data
  end

  def recv_data
    @socket.gets
    
  end

  def close
    @socket.close
  end
end