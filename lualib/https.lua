local httpsc = require "httpsc"
local internal = require "http.internal"
local sockethelper = require "http.sockethelper"

local M = {}

function M.request( method, host, url, recvheader, header, content)
	local fd = httpsc.connect(host, 443)

	while true do
		local ok = httpsc.check_connect(fd)
		if ok then break end
		httpsc.usleep(10000)
	end

	local read = function()
		return httpsc.recv(fd) or ""
	end

	local write = function(msg)
    print(msg)
    httpsc.send(fd, msg)
	end

	local header_content = ""
	if header then
		if not header.host then
			header.host = host
		end
		for k,v in pairs(header) do
			header_content = string.format("%s%s:%s\r\n", header_content, k, v)
		end
	else
		header_content = string.format("host:%s\r\n",host)
	end

  print(url)
  print(header_content)
  print(content)

	if content then
		local data = string.format("%s %s HTTP/1.1\r\n%scontent-length:%d\r\n\r\n%s", method, url, header_content, #content, content)
		write(data)
	else
		local request_header = string.format("%s %s HTTP/1.1\r\n%scontent-length:0\r\n\r\n", method, url, header_content)
		write(request_header)
	end

	httpsc.usleep(1000000)
	local tmpline = {}
	local body = internal.recvheader(read, tmpline, "")
	if not body then
		error(sockethelper.socket_error)
	end

	local statusline = tmpline[1]
	local code, info = statusline:match "HTTP/[%d%.]+%s+([%d]+)%s+(.*)$"
	code = assert(tonumber(code))

	local header = internal.parseheader(tmpline,2,recvheader or {})
	if not header then
		error("Invalid HTTP response header")
	end

	local length = header["content-length"]
	if length then
		length = tonumber(length)
	end

	local mode = header["transfer-encoding"]
	if mode then
		if mode ~= "identity" and mode ~= "chunked" then
			error ("Unsupport transfer-encoding")
		end
	end

	if mode == "chunked" then
		body, header = internal.recvchunkedbody(read, nil, header, body)
		if not body then
			error("Invalid response body")
		end
	else
		print(length)
		if length then
			if #body >= length then
				body = body:sub(1,length)
			else
				while true do
					local padding = read(length - #body)
					if #padding>0 then
						body = body .. padding
						if #body>= length then
							body = body:sub(1,length)
							break
						end
					else
						httpsc.usleep(1000)
					end
				end
			end
		else
			body = nil
		end
	end

    if fd then
		httpsc.close(fd)
	end

	return code, body
end

return M
