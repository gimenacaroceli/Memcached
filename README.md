
# Memcached

Memcached server implentation, in which TCP/IP clients can connect whit it in order to save key/value pairs.


Storage commands:
- set
- add
- replace
- append
- prepend
- cas

Retrieval commands:
- get
- gets



## Pre-requisites
Have Ruby installed

Have [Apache Jmeter](https://jmeter.apache.org/download_jmeter.cgi) installed
## Installation

to run tests: [RSpec](https://github.com/rspec/rspec/)
```bash
gem install rspec
```

## Usage

Run Memcached server

```bash
ruby main.rb
```
then you can connect to the server running 

```bash
telnet localhost 8080
```

As an example:

```bash
>> telnet localhost 8080
   Trying 127.0.0.1...
   Connected to localhost.
   Escape character is '^]'.
>> set key 0 0 5
>> value
   STORED
>> get key
   VALUE key 0 5
   value
   END
```

## RSpec tests

```bash
rspec memcached_spec.rb
```

## Considerations

The memcached protocol indicates the end of a line with "\r\n".

JMeter tests uses "\n" as the end of line. In order to pass JMeter test a flag was implemented to accept both end of lines.

To switch to "\n" end of line in the memcached server is required to add an extra parameter to the command that runs the script.

```bash
ruby main.rb 1
```

## JMeter

Open Jmeter GUI, import the test file and run it.

```bash
Memcached Sampler.jmx
```
