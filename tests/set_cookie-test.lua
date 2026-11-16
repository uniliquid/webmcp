-- Tests of rocketcgi.set_cookie and request.set_cookie (pure Lua, no C
-- libraries). Run from the repository root: lua5.1 tests/set_cookie-test.lua
-- < /dev/null (tests/run.sh does this in Docker). Exit status 0: all passed.

package.path = "lib/?.lua;" .. package.path
local rocketcgi = require "rocketcgi"

-- The header lines are captured instead of written to stdout.
local headers
rocketcgi.add_header = function(...)
  headers[#headers+1] = table.concat({...})
end

local failures = 0
local function check(name, condition)
  print((condition and "ok   " or "FAIL ") .. name)
  if not condition then failures = failures + 1 end
end

-- The header line of rocketcgi.set_cookie(args), or nil and the error.
local function header(args, set_cookie)
  headers = {}
  local ok, err = pcall(set_cookie or rocketcgi.set_cookie, args)
  if not ok then return nil, err end
  assert(#headers == 1, "one header line")
  return headers[1]
end

local function check_header(name, args, expected, set_cookie)
  local got, err = header(args, set_cookie)
  check(name, got == expected)
  if got ~= expected then
    print("     expected: " .. tostring(expected))
    print("     got:      " .. tostring(got) .. (err and (" (" .. tostring(err) .. ")") or ""))
  end
end

local function check_error(name, args, message)
  local got, err = header(args)
  check(name, got == nil and string.find(tostring(err), message, 1, true) ~= nil)
end

local base = { name = "liquid_feedback_session", value = "abcDEF0123456789abcDEF0123456789" }
local function with(fields)
  local args = {}
  for k, v in pairs(base) do args[k] = v end
  for k, v in pairs(fields) do args[k] = v end
  return args
end
local prefix = "Set-Cookie: liquid_feedback_session=abcDEF0123456789abcDEF0123456789"

-- Existing callers: the same header as before.
check_header("old call: name and value only", with{}, prefix)
check_header("old call: path and secure", with{ path = "/", secure = true }, prefix .. "; path=/; secure")
check_header("old call: path, not secure", with{ path = "/lf/", secure = false }, prefix .. "; path=/lf/")

-- New attributes.
check_header("max_age", with{ path = "/", max_age = 2592000 }, prefix .. "; path=/; Max-Age=2592000")
check_header("max_age 0", with{ max_age = 0 }, prefix .. "; Max-Age=0")
check_header("max_age as an integral float", with{ max_age = 3600.0 }, prefix .. "; Max-Age=3600")
check_header("max_age large", with{ max_age = 7776000 }, prefix .. "; Max-Age=7776000")
check_header("http_only", with{ http_only = true }, prefix .. "; HttpOnly")
check_header("http_only false", with{ http_only = false }, prefix)
check_header("same_site Lax", with{ same_site = "Lax" }, prefix .. "; SameSite=Lax")
check_header("same_site Strict", with{ same_site = "Strict" }, prefix .. "; SameSite=Strict")
check_header("all attributes in order",
  with{ path = "/", secure = true, max_age = 2592000, http_only = true, same_site = "Lax" },
  prefix .. "; path=/; secure; Max-Age=2592000; HttpOnly; SameSite=Lax")
check_header("session cookie with HttpOnly and SameSite",
  with{ path = "/", secure = true, http_only = true, same_site = "Lax" },
  prefix .. "; path=/; secure; HttpOnly; SameSite=Lax")

-- Refused values.
check_error("max_age negative", with{ max_age = -1 }, "Illegal cookie max_age")
check_error("max_age fractional", with{ max_age = 1.5 }, "Illegal cookie max_age")
check_error("max_age string", with{ max_age = "3600" }, "Illegal cookie max_age")
check_error("max_age infinite", with{ max_age = math.huge }, "Illegal cookie max_age")
check_error("max_age NaN", with{ max_age = 0/0 }, "Illegal cookie max_age")
check_error("same_site None", with{ same_site = "None" }, "Illegal cookie same_site")
check_error("same_site lower case", with{ same_site = "lax" }, "Illegal cookie same_site")
check_error("same_site boolean", with{ same_site = true }, "Illegal cookie same_site")
check_error("value with a semicolon", with{ value = "a;HttpOnly" }, "Illegal cookie value")
check_error("path with a semicolon", with{ path = "/;x" }, "Illegal cookie path")

-- request.set_cookie: defaults from the base URL, new arguments passed on.
local baseurl
request = { get_absolute_baseurl = function() return baseurl end }
cgi = rocketcgi
dofile("env/request/set_cookie.lua")
baseurl = "https://lf.example.org/"
check_header("request: old call, https base -> path / and secure", with{}, prefix .. "; path=/; secure", request.set_cookie)
baseurl = "http://lf.example.org/sub/"
check_header("request: old call, http base -> base path, not secure", with{}, prefix .. "; path=/sub/", request.set_cookie)
baseurl = "https://lf.example.org"
check_header("request: new arguments passed on",
  with{ max_age = 3600, http_only = true, same_site = "Lax" },
  prefix .. "; path=/; secure; Max-Age=3600; HttpOnly; SameSite=Lax", request.set_cookie)
check_header("request: secure = false kept", with{ secure = false, http_only = true }, prefix .. "; path=/; HttpOnly", request.set_cookie)

print(failures == 0 and "all passed" or (failures .. " failed"))
os.exit(failures == 0 and 0 or 1)
