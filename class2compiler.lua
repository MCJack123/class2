-- THIS IS BROKEN FOR NOW, DO NOT USE.
-- Will actually finish at some point in the future.

local parseClassDefinition, parseLuaBlock

local undefined = {}

-- takes block of code (should be class ... end)
-- returns modified code block, position of first non-block character, line of first non-block character
function parseClassDefinition(code, name, line)
    local state = nil
    local pos = 1
    local class = {
        name = nil,
        extends = nil,
        implements = nil,
        private = {
            properties = {},
            methods = {},
            metamethods = {},
            dynamic = {}
        },
        protected = {
            properties = {},
            methods = {},
            metamethods = {},
            dynamic = {}
        },
        public = {
            properties = {},
            methods = {},
            metamethods = {},
            dynamic = {}
        },
        static = {
            properties = {},
            methods = {},
            metamethods = {},
            dynamic = {}
        }
    }
    local nextparams = {}
    -- Parse
    -- TODO: handle comments
    while true do
        if state == nil then
            assert(code:match("^class%s", pos), name .. ":" .. line .. ": 'class' expected at beginning of class block")
            state, nextparams = "name", {function(name) class.name = name end, "start"}
            local e = select(2, code:find("^class%s+%S", pos))
            assert(e, name .. ":" .. line .. ": <name> expected near <eof>")
            code:sub(pos, e):gsub("\n", function() line = line + 1 end)
            pos = e
        elseif state == "name" then
            local m, e = code:match("^([%w_]+)" .. (nextparams[3] or "%s+") .. "()", pos)
            assert(m, name .. ":" .. line .. ": <name> expected near '" .. (code:match("^%S+", pos) or "<eof>") .. "'")
            state, nextparams = nextparams[2], {nextparams[1](m)}
            assert(e, name .. ":" .. line .. ": 'end' expected near <eof>")
            code:sub(pos, e):gsub("\n", function() line = line + 1 end)
            pos = e
        elseif state == "start" or state == "block" then
            local e
            if state == "start" and code:match("^extends%s", pos) then
                assert(class.extends == nil, name .. ":" .. line .. ": duplicate field 'extends'")
                state, nextparams = "name", {function(name) class.extends = name end, class.implements and "block" or "start"}
                e = select(2, code:find("^extends%s+%S", pos))
            elseif state == "start" and code:match("^implements%s", pos) then
                assert(class.implements == nil, name .. ":" .. line .. ": duplicate field 'implements'")
                class.implements = {}
                state, nextparams = "namelist", {function(name) class.implements[#class.implements+1] = name end, class.extends and "block" or "start"}
                e = select(2, code:find("^implements%s+%S", pos))
            elseif code:match("^end[%s(]", pos) or code:match("^end$", pos) then
                assert(#nextparams == 0, name .. ":" .. line .. ": 'var' or 'function' expected near 'end'")
                pos = pos + 3
                break
            elseif code:match("^private%s", pos) or code:match("^protected%s", pos) or code:match("^public%s", pos) or code:match("^static%s", pos) then
                assert(nextparams[1] == nil, name .. ":" .. line .. ": duplicate visibility modifier near '" .. (code:match("^%S+", pos) or "<eof>") .. "'")
                state = "block"
                nextparams[1] = code:match("^%S+", pos)
                e = select(2, code:find("^%S+%s+%S", pos))
            elseif code:match("^meta%s", pos) then
                assert(nextparams[2] == nil, name .. ":" .. line .. ": duplicate modifier 'meta'")
                state = "block"
                nextparams[2] = true
                e = select(2, code:find("^meta%s+%S", pos))
            elseif code:match("^var%s", pos) then
                assert(nextparams[2] == nil, name .. ":" .. line .. ": 'function' expected near 'var'")
                state, nextparams = "name", {function(name) return name, nextparams[4] end, "var", "%s*()[{=;epsmvf]", nextparams[1]}
                e = select(2, code:find("^var%s+%S", pos))
            elseif code:match("^function%s", pos) then
                state, nextparams = "name", {function(name) return name, nextparams[4], nextparams[5] end, "function", "%s*%(", nextparams[1], nextparams[2]}
                e = select(2, code:find("^function%s+%S", pos))
            elseif code:match("^;") then
                e = pos + 1
            else
                error(name .. ":" .. line .. ": 'end' expected near '" .. (code:match("^%S+", pos) or "<eof>") .. "'", -1)
            end
            assert(e, name .. ":" .. line .. ": 'end' expected near <eof>")
            code:sub(pos, e):gsub("\n", function() line = line + 1 end)
            pos = e
        elseif state == "namelist" then
            local m, e, c
            while true do
                m, e, c = code:match("^([%w_]+)%s*()(%S)", pos)
                assert(m, name .. ":" .. line .. ": <name> expected near '" .. (code:match("^%S+", pos) or "<eof>") .. "'")
                nextparams[1](m)
                assert(e, name .. ":" .. line .. ": 'end' expected near <eof>")
                code:sub(pos, e):gsub("\n", function() line = line + 1 end)
                pos = e
                if c == ',' then
                    e = assert(select(2, code:find(",%s*%S", pos)), name .. ":" .. line .. ": <name> expected near <eof>")
                    code:sub(pos, e):gsub("\n", function() line = line + 1 end)
                    pos = e
                else break end
            end
            state, nextparams = nextparams[2], {}
        elseif state == "var" then
            if code:sub(pos, pos) == '=' then
                local _name, visibility = table.unpack(nextparams)
                state, nextparams = "exp", {function(exp) class[visibility or "private"].properties[_name] = exp end, "block"}
                local e = select(2, code:find("^=%s*%S", pos))
                assert(e, name .. ":" .. line .. ": expression expected near <eof>")
                code:sub(pos, e):gsub("\n", function() line = line + 1 end)
                pos = e
            elseif code:sub(pos, pos) == '{' then
                state = "dynvar"
                class[nextparams[2] or "private"].dynamic[nextparams[1]] = {}
                local e = select(2, code:find("^{%s*%S", pos))
                assert(e, name .. ":" .. line .. ": expression expected near <eof>")
                code:sub(pos, e):gsub("\n", function() line = line + 1 end)
                pos = e
            else
                class[nextparams[2] or "private"].properties[nextparams[1]] = undefined
                state, nextparams = "block", {}
            end
        elseif state == "dynvar" then
            local a
            if code:match("^get%s", pos) then
                assert(class[nextparams[2] or "private"].dynamic[nextparams[1]].get == nil, name .. ":" .. line .. ": 'set' or '}' expected near 'get'")
                class[nextparams[2]].dynamic[nextparams[1]].get, a, line = parseLuaBlock(code:sub(pos), name, line, true)
                pos = pos + a
            elseif code:match("^set%s", pos) then
                assert(class[nextparams[2] or "private"].dynamic[nextparams[1]].set == nil, name .. ":" .. line .. ": 'get' or '}' expected near 'set'")
                class[nextparams[2]].dynamic[nextparams[1]].set, a, line = parseLuaBlock(code:sub(pos), name, line, true)
                pos = pos + a
            elseif code:match("^}", pos) then
                assert(class[nextparams[2] or "private"].dynamic[nextparams[1]].get ~= nil, name .. ":" .. line .. ": 'get' expected near '}'")
                state, nextparams = "block", {}
                local e = select(2, code:find("^}%s*%S", pos))
                assert(e, name .. ":" .. line .. ": 'end' expected near <eof>")
                code:sub(pos, e):gsub("\n", function() line = line + 1 end)
                pos = e
            else
                error(name .. ":" .. line .. ": '}' expected near '" .. (code:match("^%S+", pos) or "<eof>") .. "'", -1)
            end
        elseif state == "function" then
            local t = nextparams[3] and "metamethods" or "methods"
            local args, e = code:match("^(%b())%s*()%S", pos)
            assert(args, name .. ":" .. line .. ": '(' expected near '" .. (code:match("^%S+") or "<eof>") .. "'")
            class[nextparams[2] or "private"][t][nextparams[1]] = {args = args}
            local a
            class[nextparams[2] or "private"][t][nextparams[1]].block, a, line = parseLuaBlock(code:sub(pos), name, line, true)
            pos = pos + a
            state, nextparams = "block", {}
        elseif state == "exp" then
            --[[local start = pos
            local continue = true
            local last = nil
            while continue do
                continue = false
                if code:match("^not[%s\"({]", pos) or code:match("^[#-][%w%s(_]+", pos) then
                    last = 1
                    continue = true
                    pos = pos + (code:match("^not%s*()", pos) or code:match("^[#-]%s*()"))
                elseif last == 0 and (code:match("^[+-*/%^][%w%s(_]", pos) or code:match("^[<=>~]=[%w%s(_]", pos) or code:match("^[<>][%w%s(_]", pos)) then
                    last = 1
                    continue = true
                    pos = pos + code:match("^[+-*/%^<=>~]+%s*()", pos)
                elseif last == 0 and (code:match("^or[%s\"({]", pos) or code:match("^and[%s\"({]", pos)) then
                    last = 1
                    continue = true
                    pos = pos + code:match("^%w+%s*()", pos)
                elseif last == 1 and (code:match("^true%s", pos) or code:match("^false%s", pos) or code:match("^nil%s", pos)) then
                    last = 0
                    continue = true

                end
            end]]
            -- cheese it
            local e = code:match("%s()private%s", pos) or code:match("%s()protected%s", pos) or code:match("%s()public%s", pos) or code:match("%s()static%s", pos) or code:match("%s()meta%s", pos) or code:match("%s()var%s", pos) or code:match("%s()end%s", pos)
            local f = code:match("%s()function%s+[%w_]", pos)
            if e == nil and f ~= nil then e = f end
            if f ~= nil and e < f then
                -- figure this out
            end
            assert(e, name .. ":" .. line .. ": 'end' expected near <eof>")
            nextparams[1](code:sub(pos, e-1):gsub("%s+$", ""))
            code:sub(pos, e):gsub("\n", function() line = line + 1 end)
            pos = e
            state, nextparams = nextparams[2], {}
        else
            error("Internal error: unimplemented state " .. state)
        end
    end
    -- Convert to Lua code
    local res = ("local %s = class.class '%s' "):format(class.name, class.name)
    if class.extends or class.implements then
        res = res .. "{"
        if class.extends then res = res .. "extends = " .. class.extends .. ", " end
        if class.implements then
            res = res .. "implements = {"
            for _,v in ipairs(class.implements) do res = res .. v .. ", " end
            res = res .. "}"
        end
        res = res .. "} "
    end
    res = res .. "{\n"
    for _,t in ipairs{"private", "protected", "public", "static"} do
        if next(class[t].properties) or next(class[t].dynamic) or next(class[t].methods) or next(class[t].metamethods) then
            res = res .. "    " .. t .. " = {\n"
            for k,v in pairs(class[t].properties) do
                if v == undefined or v == "nil" then res = res .. "        " .. k .. " = class.undefined,\n"
                else res = res .. "        " .. k .. " = " .. v .. ",\n" end
            end
            for k,v in pairs(class[t].methods) do
                res = res .. "        " .. k .. " = function" .. v.args .. "\n" .. v.block .. ",\n"
            end
            for k,v in pairs(class[t].dynamic) do
                if v.get then res = res .. "        __" .. k .. "_get = function()\n" .. v.get .. ",\n" end
                if v.set then res = res .. "        __" .. k .. "_set = function(value)\n" .. v.set .. ",\n" end
            end
            if #class[t].metamethods > 0 then
                res = res .. "        __metamethods = {\n"
                for k,v in pairs(class[t].metamethods) do
                    res = res .. "            " .. k .. " = function" .. v.args .. "\n" .. v.block .. ",\n"
                end
                res = res .. "        },\n"
            end
            res = res .. "    },\n"
        end
    end
    res = res .. "}\n"
    return res, pos, line
end

local blocks = {["then"] = "end", ["do"] = "end", ["repeat"] = "until", ["{"] = "}", ["["] = "]", ["("] = ")"}

function parseLuaBlock(code, name, line, requireEnd)
    -- +1: then, do, repeat, function
    -- -1: end, until
    local pos = 1
    local stack = {n = 0}
    local current = ""
    local quoted = false
    while pos < #code do
        current = current .. code:sub(pos, pos)
        if current == "end"
        local found = false
        for k,v in pairs(blocks) do
            if k:find("^" .. current) then
                found = true
                if k == current then

                end
                break
            elseif v:find("^" .. current) then
                found = true
                if v == current and stack[stack.n] == k then

                end
                break
            end
        end
        if not found then current = "" end
        pos = pos + 1
    end
end

local function parse(code, name)
    return parseLuaBlock(code, name, 1, false), nil
end

local function loadstring(code, name)
    return _G.loadstring(parseLuaBlock(code, name, 1), name)
end

local file = fs.open(..., "r")
local str = file.readAll()
file.close()
print(parseClassDefinition(str, "file", 1))
