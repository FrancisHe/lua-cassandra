use Test::Nginx::Socket::Lua;
use t::Utils;

repeat_each(2);

plan tests => repeat_each() * blocks() * 3 + 2;

run_tests();

__DATA__

=== TEST 1: shm cluster info disapeared
--- http_config eval
"$t::Utils::HttpConfig"
--- config
    location /t {
      content_by_lua_block {
        local cassandra = require "cassandra"
        local cache = require "cassandra.cache"
        local shm = "cassandra"
        local session, err = cassandra.new {
            shm = shm,
            contact_points = {"127.0.0.1"}
        }
        if not session then
            ngx.say(ngx.ERR, err)
            ngx.exit(500)
        end

        local dict = ngx.shared[shm]
        local hosts, err = cache.get_hosts(shm)
        if err then
            ngx.log(ngx.ERR, err)
            ngx.exit(500)
        elseif hosts == nil or #hosts < 1 then
            ngx.log(ngx.ERR, "no hosts set in shm")
            ngx.exit(500)
        end

        -- erase hosts from the cache
        dict:delete "hosts"

        local hosts, err = cache.get_hosts(shm)
        if err then
            ngx.log(ngx.ERR, err)
            ngx.exit(500)
        elseif hosts ~= nil then
            ngx.log(ngx.ERR, "hosts set in shm after delete")
            ngx.exit(500)
        end

        -- attempt to create session
        local session, err = cassandra.new {
            shm = shm,
            contact_points = {"127.0.0.1"}
        }
        if err then
            ngx.log(ngx.ERR, err)
            ngx.exit(500)
        end

        -- attempt query
        local rows, err = session:execute "SELECT * FROM system.local"
        if err then
            ngx.log(ngx.ERR, err)
            ngx.exit(500)
        end

        ngx.say(#rows)
        ngx.say(rows[1].key)
      }
    }
--- request
GET /t
--- response_body
1
local
--- no_error_log
[error]
--- error_log eval
qr/\[debug\].*?cluster infos retrieved in shm cassandra/



=== TEST 2: session:execute() invalid query
--- http_config eval
"$t::Utils::HttpConfig"
--- config
    location /t {
        content_by_lua_block {
            local cassandra = require "cassandra"
            local session, err = cassandra.new {
                shm = "cassandra",
                contact_points = {"127.0.0.1"}
            }
            if not session then
                ngx.say(ngx.ERR, err)
                ngx.exit(500)
            end

            local rows, err = session:execute "CAN I HAZ CQL"
            if err then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- no_error_log

--- error_log eval
qr/\[error\].*?\[Syntax error\] line 1:0 no viable alternative at input 'CAN'/