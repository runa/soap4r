require 'soap/rpc/driver'

# SOAP client with BasicAuth requires http-access2.
# http://raa.ruby-lang.org/project/http-access2/
drv = SOAP::RPC::Driver.new('http://localhost:7000/', 'urn:test')
drv.wiredump_dev = STDERR if $DEBUG
drv.options["protocol.http.basic_auth"] <<
  ['http://localhost:7000/', "username", "passwd"]

p drv.add_method('echo', 'msg').call('hello')
