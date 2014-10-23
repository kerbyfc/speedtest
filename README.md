speedtest
=========

Coffee class to test connection speed for one or few hosts

### example usage
```coffee
# put files https://github.com/kerbyfc/speedtest/tree/master/srv/public/speedtest/files
# to target server and make them asseccable by path /speedtest/files
test = new Speedtest('http://googgle.com');

handlers = 
  'start': ->
  'dimension:start': ->
  'metering:start': ->
  'metering:finish': ->
  'abort': ->
  'error': ->
  'finish': ->
  'dimension:finish': ->

for event, handler of handlers
  test.on event, handler

test.start();
```
