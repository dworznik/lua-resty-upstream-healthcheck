local _M = {}


local function kvconcat(t, sep1, sep2)
    local ret = {}
    local lastv
    for k, v in pairs(t) do
        ret[#ret+1] = k .. sep1
        ret[#ret+1] = v .. sep2
        lastv = v
    end
    ret[#ret] = lastv -- remove the last sep
    return table.concat(ret)
end

function _M.send_get(c, path, headers)
  -- local log = ngx.log
  -- local ERR = ngx.ERR
  -- log(ERR, '>>>headers', headers)
  -- log(ERR, headers)
  local bytes, err = c:send('GET ' .. path .. ' HTTP/1.0\r\n'.. kvconcat(headers, ': ', '\r\n') .. '\r\n\r\n')
  return bytes, err
end

function _M.send_post(c, path, headers, body)
  headers['content-length'] = string.len(body)
  local _, err = c:send('POST ' .. path .. ' HTTP/1.0\r\n' .. kvconcat(headers, ': ', '\r\n') .. '\r\n' .. body)
  return err
end

function _M.receive_status(c)
  local line, err = c:receive()
  if err then return nil, err end
  local _, __, status = string.find(line, '^HTTP.* (%d+)')
  return tonumber(status)
end


function _M.receive_headers(c)
  local line, err = c:receive()
  if err then return nil, err end

  local headers = {}
  while line ~= '' do
    local _, __, name, value = tring.find(line, '^(.-):%s*(.*)')
    if not (name and value) then return nil, 'invalid http headers' end

    name = string.lower(name)
    headers[name] = value

    line, err  = c:receive()
    if err then return nil, err end
  end
  return headers, nil
end

function _M.receive_body(c)
  local buf, err, partial
  local data = {}
  while true do
    buf, err, partial = c:receive(1024)
    if buf then
      data[#data+1] = buf
    elseif partial then
      data[#data+1] = partial
    end
    if err then break end
  end
  if err ~= 'closed' then return nil, err end
  return table.concat(data)
end

return _M
