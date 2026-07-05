-- Pure Lua JSON parser (decodes JSON string to Lua table)
-- Based on public implementations, optimized for loading simple static data files

local json = {}

local function next_char(str, pos)
    return str:sub(pos, pos), pos + 1
end

local function skip_whitespace(str, pos)
    while pos <= #str do
        local c = str:sub(pos, pos)
        if c == " " or c == "\t" or c == "\n" or c == "\r" then
            pos = pos + 1
        else
            break
        end
    end
    return pos
end

local parse_value -- forward declaration

local function parse_string(str, pos)
    local start = pos
    local result = {}
    while pos <= #str do
        local c = str:sub(pos, pos)
        if c == '"' then
            return table.concat(result), pos + 1
        elseif c == "\\" then
            pos = pos + 1
            local esc = str:sub(pos, pos)
            if esc == "n" then table.insert(result, "\n")
            elseif esc == "r" then table.insert(result, "\r")
            elseif esc == "t" then table.insert(result, "\t")
            else table.insert(result, esc) end
        else
            table.insert(result, c)
        end
        pos = pos + 1
    end
    error("Unterminated string in JSON at " .. start)
end

local function parse_number(str, pos)
    local start = pos
    while pos <= #str do
        local c = str:sub(pos, pos)
        if c:match("[%d%.%-eE%+]") then
            pos = pos + 1
        else
            break
        end
    end
    local val = tonumber(str:sub(start, pos - 1))
    if not val then error("Invalid number in JSON at " .. start) end
    return val, pos
end

local function parse_object(str, pos)
    local obj = {}
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) == "}" then
        return obj, pos + 1
    end
    while pos <= #str do
        pos = skip_whitespace(str, pos)
        if str:sub(pos, pos) ~= '"' then
            error("Expected string key in object at " .. pos)
        end
        local key
        key, pos = parse_string(str, pos + 1)
        pos = skip_whitespace(str, pos)
        if str:sub(pos, pos) ~= ":" then
            error("Expected ':' after key in object at " .. pos)
        end
        pos = skip_whitespace(str, pos + 1)
        local val
        val, pos = parse_value(str, pos)
        obj[key] = val
        pos = skip_whitespace(str, pos)
        local next_c = str:sub(pos, pos)
        if next_c == "}" then
            return obj, pos + 1
        elseif next_c == "," then
            pos = pos + 1
        else
            error("Expected ',' or '}' in object at " .. pos)
        end
    end
end

local function parse_array(str, pos)
    local arr = {}
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) == "]" then
        return arr, pos + 1
    end
    while pos <= #str do
        pos = skip_whitespace(str, pos)
        local val
        val, pos = parse_value(str, pos)
        table.insert(arr, val)
        pos = skip_whitespace(str, pos)
        local next_c = str:sub(pos, pos)
        if next_c == "]" then
            return arr, pos + 1
        elseif next_c == "," then
            pos = pos + 1
        else
            error("Expected ',' or ']' in array at " .. pos)
        end
    end
end

parse_value = function(str, pos)
    pos = skip_whitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == '"' then
        return parse_string(str, pos + 1)
    elseif c == "{" then
        return parse_object(str, pos + 1)
    elseif c == "[" then
        return parse_array(str, pos + 1)
    elseif c == "t" and str:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif c == "f" and str:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif c == "n" and str:sub(pos, pos + 3) == "null" then
        return nil, pos + 4
    elseif c == "-" or c:match("%d") then
        return parse_number(str, pos)
    else
        error("Unexpected character '" .. c .. "' at " .. pos)
    end
end

function json.decode(str)
    local val, pos = parse_value(str, 1)
    pos = skip_whitespace(str, pos)
    if pos <= #str then
        error("Trailing garbage in JSON at " .. pos)
    end
    return val
end

function json.encode(val)
    local t = type(val)
    if t == "string" then
        return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
    elseif t == "number" then
        return tostring(val)
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "nil" then
        return "null"
    elseif t == "table" then
        -- Check if it is an array
        local is_array = true
        local max_idx = 0
        local count = 0
        for k, _ in pairs(val) do
            count = count + 1
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                is_array = false
                break
            end
            if k > max_idx then max_idx = k end
        end
        if count > 0 and max_idx ~= count then
            is_array = false
        end
        
        if is_array then
            local parts = {}
            for i = 1, max_idx do
                table.insert(parts, json.encode(val[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            local keys = {}
            for k in pairs(val) do
                table.insert(keys, tostring(k))
            end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local v = val[k]
                -- Try index as string or as number if string fails
                if v == nil and tonumber(k) then
                    v = val[tonumber(k)]
                end
                if v ~= nil then
                    table.insert(parts, '"' .. k .. '":' .. json.encode(v))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        error("Unsupported JSON type: " .. t)
    end
end

return json
