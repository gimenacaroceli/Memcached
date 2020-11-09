# frozen_string_literal: true

require_relative 'memcached_server' # relative path to server
require_relative 'client'  # relative path to client
require 'rspec'

describe MemcachedServer do
  before(:each) do
    @server = MemcachedServer.new
    Thread.new do
      @server.start
    end

    @client = Client.new
  end

  after(:each) do
    @server.close
  end

  def store(command, key, value, flags, exp_time, length, cas_u = nil)
    @client.send_data "#{command} #{key} #{flags} #{exp_time} #{length} #{cas_u}"
    @client.send_data "#{value}\r\n"
    expect(@client.recv_data).to eql(MemcachedServer::STORED)
  end

  def bad_data_chunk(command, key, value, flags, exp_time, length, cas_u = nil)
    @client.send_data "#{command} #{key} #{flags} #{exp_time} #{length} #{cas_u}"
    @client.send_data "#{value}\r\n"
    expect(@client.recv_data).to eql(MemcachedServer::BAD_DATA)
    expect(@client.recv_data).to eq(MemcachedServer::ERROR)
  end

  def not_store(command, key, value, flags, exp_time, length)
    @client.send_data "#{command} #{key} #{flags} #{exp_time} #{length}"
    @client.send_data "#{value}\r\n"
    expect(@client.recv_data).to eql(MemcachedServer::STORE_FAIL)
  end

  def check_memcached(key, value, flags, length)
    memcached = @server.memcached
    expect(memcached.key?(key)).to eq(true)
    expect(memcached[key][:value]).to eq(value)
    expect(memcached[key][:flags].to_i).to eq(flags)
    expect(memcached[key][:length].to_i).to eq(length)
  end

  def check_not_memcached(key)
    memcached = @server.memcached
    expect(memcached.key?(key)).to eq(false)
    expect(memcached[key]).to eq(nil)
  end

  def quit_client
    @client.send_data "quit\r\n"
  end

  describe 'general fails' do
    it 'send invalid command' do
      @client.send_data 'invalid_command data 0 0 5'
      expect(@client.recv_data).to eql(MemcachedServer::ERROR)
    end

    it 'send invalid flags' do
      @client.send_data 'set data invalid_flags 0 5'
      expect(@client.recv_data).to eql(MemcachedServer::BAD_LINE)
    end

    it 'send invalid expiration time' do
      @client.send_data 'set data 0 invalid 5'
      expect(@client.recv_data).to eql(MemcachedServer::BAD_LINE)
    end

    it 'send invalid length' do
      @client.send_data 'set data 0 0 invalid'
      expect(@client.recv_data).to eql(MemcachedServer::BAD_LINE)
    end

    it 'send invalid line' do
      @client.send_data 'set data 0 0 5 noreply invalid'
      expect(@client.recv_data).to eql(MemcachedServer::ERROR)
    end
  end

  describe 'no reply command' do
    it 'store value with no reply' do
      @client.send_data 'set key 0 0 5 noreply'
      @client.send_data "value\r\n"
      sleep(0.1)
      check_memcached('key', 'value', 0, 5)
      quit_client
    end

    it 'not store value with no reply' do
      @client.send_data 'replace key 0 0 5 noreply'
      @client.send_data "value\r\n"
      check_not_memcached('key')
      quit_client
    end

    it 'not store value cause bad data chunk with no reply' do
      @client.send_data 'set key 0 0 5 noreply'
      @client.send_data "val\r\n"
      expect(@client.recv_data).to eql(MemcachedServer::ERROR)
      check_not_memcached('key')
      quit_client
    end

    it 'not store value cause invalid input with no reply' do
      @client.send_data 'set key invalid 0 5 noreply'
      @client.send_data "value\r\n"
      expect(@client.recv_data).to eql(MemcachedServer::ERROR)
      check_not_memcached('key')
      quit_client
    end
  end

  describe 'set command' do
    context 'success' do
      it 'store the value' do
        store('set', 'key', 'value', 0, 0, 5)
        check_memcached('key', 'value', 0, 5)
        quit_client
      end
    end

    context 'fail' do
      it 'not store value, cause bytes not match' do
        bad_data_chunk('set', 'key', 'value', 0, 0, 8)
        check_not_memcached('key')
        quit_client
      end
    end
  end

  describe 'add command' do
    context 'success' do
      it 'store the value' do
        store('add', 'key', 'value', 0, 0, 5)
        check_memcached('key', 'value', 0, 5)
        quit_client
      end
    end

    context 'fail' do
      it 'not store value, cause key exists' do
        store('set', 'key', 'value', 0, 0, 5)
        not_store('add', 'key', 'new value', 0, 0, 9)
        check_memcached('key', 'value', 0, 5)
        quit_client
      end

      it 'not store value, cause bytes not match' do
        bad_data_chunk('add', 'key', 'value', 0, 0, 15)
        check_not_memcached('key')
        quit_client
      end
    end
  end

  describe 'replace command' do
    context 'success' do
      it 'store the value' do
        store('set', 'key', 'value', 0, 0, 5)
        check_memcached('key', 'value', 0, 5)
        store('replace', 'key', 'new value', 5, 30, 9)
        check_memcached('key', 'new value', 5, 9)
        quit_client
      end
    end

    context 'fail' do
      it 'not store value, cause key not exists' do
        not_store('replace', 'key', 'value', 0, 0, 5)
        check_not_memcached('key')
        quit_client
      end

      it 'not store value, cause bytes not match' do
        store('set', 'key', 'value', 0, 0, 5)
        check_memcached('key', 'value', 0, 5)
        bad_data_chunk('replace', 'key', 'new value', 0, 0, 15)
        check_memcached('key', 'value', 0, 5)
        quit_client
      end
    end
  end

  describe 'append command' do
    context 'success' do
      it 'store the value' do
        store('set', 'key', 'value', 0, 0, 5)
        check_memcached('key', 'value', 0, 5)
        store('append', 'key', ' append', 5, 120, 7)
        check_memcached('key', 'value append', 0, 12)
        quit_client
      end
    end

    context 'fail' do
      it 'not store value, cause key not exists' do
        not_store('append', 'key', 'value', 0, 0, 5)
        check_not_memcached('key')
        quit_client
      end

      it 'not store value, cause bytes not match' do
        store('set', 'key', 'value', 0, 0, 5)
        bad_data_chunk('append', 'key', 'append ', 0, 0, 25)
        check_memcached('key', 'value', 0, 5)
        quit_client
      end
    end
  end

  describe 'prepend command' do
    context 'success' do
      it 'store the value' do
        store('set', 'key', 'value', 0, 0, 5)
        store('prepend', 'key', 'prepend ', 25, 500, 8)
        check_memcached('key', 'prepend value', 0, 13)
        quit_client
      end
    end

    context 'fail' do
      it 'not store value, cause key not exists' do
        not_store('prepend', 'key', 'value', 0, 0, 5)
        check_not_memcached('key')
        quit_client
      end

      it 'not store value, cause bytes not match' do
        store('set', 'key', 'value', 0, 0, 5)
        bad_data_chunk('prepend', 'key', 'prepend ', 0, 0, 585)
        check_memcached('key', 'value', 0, 5)
        quit_client
      end
    end
  end

  describe 'cas and gets command' do
    context 'success' do
      it 'cas the value' do
        store('set', 'key', 'value', 0, 0, 5)
        store('set', 'key_2', 'value', 0, 0, 5)
        @client.send_data 'gets key key_2'
        expect(@client.recv_data).to eql("VALUE key 0 5 1\r\n")
        expect(@client.recv_data).to eql("value\r\n")
        expect(@client.recv_data).to eql("VALUE key_2 0 5 2\r\n")
        expect(@client.recv_data).to eql("value\r\n")
        expect(@client.recv_data).to eq("END\r\n")
        store('cas', 'key', 'new value', 10, 300, 9, 1)
        quit_client
      end
    end

    context 'fail' do
      it 'return exists, cause key exist but cas unique invalid' do
        store('set', 'key', 'value', 0, 0, 5)
        @client.send_data 'cas key 10 300 9 1'
        @client.send_data 'new value'
        expect(@client.recv_data).to eql("EXISTS\r\n")
        quit_client
      end

      it 'return not found, cause key not exists' do
        @client.send_data 'cas key 10 300 9 1'
        @client.send_data 'new value'
        expect(@client.recv_data).to eql("NOT FOUND\r\n")
        quit_client
      end

      it 'not store value, cause bytes not match' do
        store('set', 'key', 'value', 0, 0, 5)
        @client.send_data 'gets key'
        expect(@client.recv_data).to eql("VALUE key 0 5 1\r\n")
        expect(@client.recv_data).to eql("value\r\n")
        expect(@client.recv_data).to eq("END\r\n")
        bad_data_chunk('cas', 'key', 'wrong', '10', '300', '19', '1')
        quit_client
      end
    end
  end

  describe 'get command' do
    context 'success' do
      it 'return the value' do
        store('set', 'key', 'value', 0, 0, 5)
        @client.send_data 'get key'
        expect(@client.recv_data).to eql("VALUE key 0 5\r\n")
        expect(@client.recv_data).to eql("value\r\n")
        expect(@client.recv_data).to eq("END\r\n")
      end

      it 'return the values' do
        store('set', 'key', 'value', 0, 0, 5)
        store('set', 'key2', 'value2', 0, 0, 6)
        @client.send_data 'get key key2'
        expect(@client.recv_data).to eql("VALUE key 0 5\r\n")
        expect(@client.recv_data).to eql("value\r\n")
        expect(@client.recv_data).to eql("VALUE key2 0 6\r\n")
        expect(@client.recv_data).to eql("value2\r\n")
        expect(@client.recv_data).to eq("END\r\n")
      end
    end

    context 'fail' do
      it 'not return value, cause not exist' do
        @client.send_data 'get key'
        expect(@client.recv_data).to eq("END\r\n")
        memcached = @server.memcached
        quit_client
      end

      it 'not reeturn value, cause time expired' do
        store('set', 'key', 'value', 0, 1, 5)
        check_memcached('key', 'value', 0, 5)
        sleep(1)
        @client.send_data 'get key'
        expect(@client.recv_data).to eq("END\r\n")
        memcached = @server.memcached
        expect(memcached.key?('key')).to eq(false)
        expect(memcached['key']).to eq(nil)
      end
    end
  end
end
