# frozen_string_literal: true

require 'socket'

EOL_TYPE = ARGV[0] == '1'

EOL = EOL_TYPE ? "\n" : "\r\n"

class MemcachedServer
  STORE_FAIL = "NOT STORED#{EOL}"
  ERROR = "ERROR#{EOL}"
  STORED = "STORED#{EOL}"
  BAD_LINE = "CLIENT_ERROR bad command line format#{EOL}"
  BAD_DATA = "CLIENT_ERROR bad data chunk#{EOL}"
  NOT_FOUND = "NOT FOUND#{EOL}"
  EXISTS = "EXISTS#{EOL}"
  PORT = 8080

  def initialize
    @cas_unique_global = 1
    @memcached = {}
    @socket = TCPServer.new('0.0.0.0', PORT)
  end

  attr_reader :memcached

  def close
    @socket.close
  end

  def start
    until @socket.closed?
      client = @socket.accept
      Thread.new { handle_connection(client) }
    end
  rescue IOError
  end

  private

  def handle_connection(client)
    @client = client
    until @client.closed?
      @data = @client.gets&.split(' ')
      storage_commands = %w[set add replace append prepend cas]
      retrieval_commands = %w[get gets]
      @command = @data.first
      case @command
      when *storage_commands
        manage_storage_commnds
      when *retrieval_commands
        handle_get
      when 'quit'
        @client.close
      else
        @client.write(ERROR)
      end
    end
  rescue IOError
  end

  def manage_storage_commnds
    params
    if valid_commands?
      client_get_data
    elsif no_reply?
      @client.write(ERROR)
    else
      @client.write(BAD_LINE)
    end
  end

  def client_get_data
    @value = @client.gets
    @value = @value.gsub("\r", '').gsub("\n", '')
    @exist_key = @memcached.key?(@key)
    if @command == 'cas'
      handle_cas
    else
      handle_storage
    end
  end

  def params
    if @command == 'cas'
      @command, @key, @flags, @exptime, @bytes, @cas_unique, @no_reply = @data
    else
      @command, @key, @flags, @exptime, @bytes, @no_reply = @data
    end
  end

  def no_reply?
    @no_reply == 'noreply'
  end

  def store_data(data, flags, exp_time, length, cas_unique = nil)
    if data.bytesize == length.to_i
      @memcached[@key] = { value: data, flags: flags, max_time: exp_time,
                           length: length, cas_unique: cas_unique }
      send_msg(STORED) unless no_reply?
    else
      send_msg(BAD_DATA) unless no_reply?
      send_msg(ERROR)
    end
  end

  def send_msg(msg)
    @client.write(msg)
  end

  def handle_storage
    if @command == 'set' || (@exist_key && @command == 'replace') || (!@exist_key && @command == 'add')
      store_data(@value, @flags, @exptime.to_i.zero? ? 0 : Time.now + @exptime.to_i, @bytes)
    elsif @exist_key && %w[prepend append].include?(@command)
      handle_pends
    else
      send_msg(STORE_FAIL) unless no_reply?
    end
  end

  def handle_pends
    length = @bytes.to_i + @memcached[@key][:length].to_i
    if @command == 'append'
      store_data(@memcached[@key][:value] + @value, @memcached[@key][:flags],
                 @memcached[@key][:max_time], length)
    elsif @command == 'prepend'
      store_data(@value + @memcached[@key][:value], @memcached[@key][:flags],
                 @memcached[@key][:max_time], length)
    end
  end

  def handle_cas
    if !@exist_key
      send_msg(NOT_FOUND)
    elsif @memcached[@key][:cas_unique] != @cas_unique.to_i
      send_msg(EXISTS)
    else
      store_data(@value, @flags.to_i, @exptime.to_i.zero? ? 0 : Time.now + @exptime.to_i, @bytes.to_i)
    end
  end

  def handle_get
    @data.drop(1).each do |key|
      if @memcached.key?(key)
        if @memcached[key][:max_time] == 0 || @memcached[key][:max_time] > Time.now
          return_data(key)
        else
          @memcached.delete(key)
        end
      end
    end
    send_msg("END#{EOL}")
  end

  def return_data(key)
    gets = @command == 'gets'
    update_cas_unique(key) if gets && @memcached[key][:cas_unique].nil?
    msg = "VALUE #{key} #{@memcached[key][:flags]} #{@memcached[key][:length]}" +
          (gets ? " #{@memcached[key][:cas_unique]}#{EOL}" : EOL.to_s)
    send_msg(msg)
    send_msg("#{@memcached[key][:value]}#{EOL}")
  end

  def update_cas_unique(key)
    @memcached[key][:cas_unique] = @cas_unique_global
    @cas_unique_global += 1
  end

  def valid_commands?
    if @command == 'cas'
      integer_params? && [6, 7].include?(@data.count) && @cas_unique&.match(/^(\d)+$/)
    else
      integer_params? && [5, 6].include?(@data.count)
    end
  end

  def integer_params?
    @flags&.match(/^(\d)+$/) && @exptime&.match(/^(\d)+$/) && @bytes&.match(/^(\d)+$/)
  end
end
