local parseClassDefinition, parseInterfaceDefinition, parseLuaBlock

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
        constructor = nil,
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
                state, nextparams = "name", {function(name) return name, nextparams[4], nextparams[5] end, "function", "%s*()%(", nextparams[1], nextparams[2]}
                e = select(2, code:find("^function%s+%S", pos))
            elseif code:match("^new%s*%(", pos) then
                state, nextparams = "ctor", {}
                e = select(2, code:find("^new%s*%(", pos))
            elseif code:match("^%-%-%[=*%[", pos) then
                e = select(2, code:find(code:match("^%-%-(%[=*%[)", pos):gsub("%[", "%%]") .. "%s*%S", pos))
            elseif code:match("^%-%-", pos) then
                e = select(2, code:find("\n%s*%S", pos))
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
                class[nextparams[2]].dynamic[nextparams[1]].get, a, line = parseLuaBlock(code:sub(select(2, code:find("^get%s+%S", pos))), name, line, true)
                pos = select(2, code:find("^get%s+%S", pos)) + a
            elseif code:match("^set%s", pos) then
                assert(class[nextparams[2] or "private"].dynamic[nextparams[1]].set == nil, name .. ":" .. line .. ": 'get' or '}' expected near 'set'")
                class[nextparams[2]].dynamic[nextparams[1]].set, a, line = parseLuaBlock(code:sub(select(2, code:find("^set%s+%S", pos))), name, line, true)
                pos = select(2, code:find("^set%s+%S", pos)) + a
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
            assert(args, name .. ":" .. line .. ": '(' expected near '" .. (code:match("^%S+", pos) or "<eof>") .. "'")
            class[nextparams[2] or "private"][t][nextparams[1]] = {args = args}
            local a
            print("entering function " .. nextparams[1])
            class[nextparams[2] or "private"][t][nextparams[1]].block, a, line = parseLuaBlock(code:sub(e), name, line, true)
            print("exiting function " .. nextparams[1])
            e = e + a
            state, nextparams = "block", {}
            code:sub(pos, e):gsub("\n", function() line = line + 1 end)
            pos = e
        elseif state == "ctor" then
            local args, e = code:match("^(%b())%s*()%S", pos)
            assert(args, name .. ":" .. line .. ": '(' expected near '" .. (code:match("^%S+") or "<eof>") .. "'")
            class.constructor = {args = args}
            local a
            print("entering ctor")
            class.constructor.block, a, line = parseLuaBlock(code:sub(e), name, line, true)
            print("exiting ctor")
            e = e + a
            state, nextparams = "block", {}
            code:sub(pos, e):gsub("\n", function() line = line + 1 end)
            pos = e
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
            local e = math.min(code:match("%s()private%s", pos) or #code, code:match("%s()protected%s", pos) or #code, code:match("%s()public%s", pos) or #code, code:match("%s()static%s", pos) or #code, code:match("%s()meta%s", pos) or #code, code:match("%s()var%s", pos) or #code, code:match("%s()end%s", pos) or #code, code:match("%s()new%s*%(", pos) or #code)
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
    local res = ("local %s\n%s = class.class '%s' "):format(class.name, class.name, class.name)
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
    if class.constructor then
        res = res .. "    new = function" .. class.constructor.args .. "\n" .. class.constructor.block .. ","
    end
    for _,t in ipairs{"private", "protected", "public", "static"} do
        if next(class[t].properties) or next(class[t].dynamic) or next(class[t].methods) or next(class[t].metamethods) then
            res = res .. "    " .. t .. " = {\n"
            for k,v in pairs(class[t].properties) do
                if v == undefined or v == "nil" then res = res .. "        " .. k .. " = class.NIL,\n"
                else res = res .. "        " .. k .. " = " .. v .. ",\n" end
            end
            for k,v in pairs(class[t].methods) do
                res = res .. "        " .. k .. " = function" .. v.args .. "\n" .. v.block .. ",\n"
            end
            if next(class[t].dynamic) then
                res = res .. "        dynamic = {\n"
                for k,v in pairs(class[t].dynamic) do
                    res = res .. "            " .. k .. " = {\n"
                    if v.get then res = res .. "                get = function()\n" .. v.get .. ",\n" end
                    if v.set then res = res .. "                set = function(value)\n" .. v.set .. ",\n" end
                    res = res .. "            },\n"
                end
                res = res .. "        },\n"
            end
            if next(class[t].metamethods) then
                res = res .. "        meta = {\n"
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

function parseInterfaceDefinition(code, name, line)
    local state = nil
    local pos = 1
    local interface = {
        name = nil,
        implements = nil,
        properties = {},
        methods = {},
        optional_methods = {},
        default_methods = {}
    }
    local nextparams = {}
    while true do
        if state == nil then
            assert(code:match("^interface%s", pos) or code:match("^protocol%s", pos), name .. ":" .. line .. ": 'interface' or 'protocol' expected at beginning of interface block")
            state, nextparams = "name", {function(name) interface.name = name end, "start"}
            local e = select(2, code:find("^interface%s+%S", pos)) or select(2, code:find("^protocol%s+%S", pos))
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
            if state == "start" and code:match("^implements%s", pos) then
                assert(interface.implements == nil, name .. ":" .. line .. ": duplicate field 'implements'")
                interface.implements = {}
                state, nextparams = "namelist", {function(name) interface.implements[#interface.implements+1] = name end, "start"}
                e = select(2, code:find("^implements%s+%S", pos))
            elseif code:match("^end[%s(]", pos) or code:match("^end$", pos) then
                assert(#nextparams == 0, name .. ":" .. line .. ": 'var' or 'function' expected near 'end'")
                pos = pos + 3
                break
            elseif code:match("^var%s", pos) then
                assert(nextparams[2] == nil, name .. ":" .. line .. ": 'function' expected near 'var'")
                state, nextparams = "name", {function(name) table.insert(interface.properties, name) end, "block"}
                e = select(2, code:find("^var%s+%S", pos))
            elseif code:match("^function%s", pos) then
                state, nextparams = "name", {function(name) return name end, "function", "%s*"}
                e = select(2, code:find("^function%s+%S", pos))
            elseif code:match("^%-%-%[=*%[", pos) then
                e = select(2, code:find(code:match("^%-%-(%[=*%[)", pos):gsub("%[", "%%]") .. "%s*%S", pos))
            elseif code:match("^%-%-", pos) then
                e = select(2, code:find("\n%s*%S", pos))
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
        elseif state == "function" then
            print(nextparams[1])
            if code:match("^%(", pos) then
                local args, e = code:match("^(%b())%s*()%S", pos)
                assert(args, name .. ":" .. line .. ": '(' expected near '" .. (code:match("^%S+", pos) or "<eof>") .. "'")
                interface.default_methods[nextparams[1]] = {args = args}
                local a
                print("entering function " .. nextparams[1])
                interface.default_methods[nextparams[1]].block, a, line = parseLuaBlock(code:sub(e), name, line, true)
                print("exiting function " .. nextparams[1])
                e = e + a
                state, nextparams = "block", {}
                code:sub(pos, e):gsub("\n", function() line = line + 1 end)
                pos = e
            elseif code:match("^optional%s", pos) then
                table.insert(interface.optional_methods, nextparams[1])
                state, nextparams = "block", {}
                local e = select(2, code:find("^optional%s+%S", pos))
                assert(e, name .. ":" .. line .. ": 'end' expected near <eof>")
                code:sub(pos, e):gsub("\n", function() line = line + 1 end)
                pos = e
            else
                table.insert(interface.methods, nextparams[1])
                state, nextparams = "block", {}
            end
        else
            error("Internal error: unimplemented state " .. state)
        end
    end
    -- Convert to Lua code
    local res = ("local %s\n%s = class.interface '%s' "):format(interface.name, interface.name, interface.name)
    if interface.implements then
        res = res .. "{implements = {"
        for _,v in ipairs(interface.implements) do res = res .. v .. ", " end
        res = res .. "}} "
    end
    res = res .. "{\n"
    for _,v in ipairs(interface.properties) do res = res .. "    " .. v .. " = 'var',\n" end
    for _,v in ipairs(interface.methods) do res = res .. "    " .. v .. " = 'function',\n" end
    for _,v in ipairs(interface.optional_methods) do res = res .. "    " .. v .. " = 'function_optional',\n" end
    for k,v in pairs(interface.default_methods) do res = res .. "    " .. k .. " = function" .. v.args .. "\n" .. v.block .. ",\n" end 
    res = res .. "}\n"
    return res, pos, line
end

local blocks = {["then"] = "end", ["do"] = "end", ["function"] = "end", ["repeat"] = "until", ["{"] = "}", ["["] = "]", ["("] = ")", ["class"] = "", ["elseif"] = "elseif", ["interface"] = "", ["protocol"] = ""}

function parseLuaBlock(code, name, line, requireEnd)
    -- +1: then, do, repeat, function, (, [, {
    -- -1: end, until, elseif, ), ], }
    local pos = 1
    local stack = {n = 0}
    local current = ""
    local quoted = false
    local escaped = false
    local output = ""
    local chunk_start = 1
    while pos <= #code do
        local c = code:sub(pos, pos)
        if c == '\n' then line = line + 1 end
        if c == '"' and not escaped then if quoted == 0 then quoted = false elseif not quoted then quoted = 0 end
        elseif c == "'" and not escaped then if quoted == 1 then quoted = false elseif not quoted then quoted = 1 end
        elseif c == '\\' and quoted then escaped = 1
        elseif code:sub(pos, pos+1) == "--" then
            if code:match("^%[=*%[", pos+2) then
                local e = select(2, code:find(code:match("^%[=*%[", pos+2):gsub("%[", "%%]"), pos))
                code:sub(pos, e):gsub("\n", function() line = line + 1 end)
                pos = e
            else pos = code:find("\n", pos) line = line + 1 end
        elseif not quoted then
            current = current .. c
            --write(current .. " ")
            if (code:sub(pos-#current, pos-#current) .. current):match("^[^%w_]end[^%w_]$") and stack.n == 0 then
                -- reached end of enclosing block if it exists
                code:sub(pos, code:find("%S", pos), nil):gsub("\n", function() line = line + 1 end)
                output = output .. code:sub(chunk_start, pos)
                if requireEnd then return output, code:find("%S", pos) - 1, line
                else error(name .. ":" .. line .. ": '<eof>' expected near 'end'", 2) end
            elseif (pos == 6 and current:match("^class[^%w_%.]$")) or (code:sub(pos-#current, pos-#current) .. current):match("^[^%w_]class[^%w_%.]$") then
                output = output .. code:sub(chunk_start, pos - 6)
                print("entering class block")
                local r, p, l = parseClassDefinition(code:sub(pos - 5), name, line)
                print("exiting class block")
                output = output .. r
                pos = pos + p - 5
                chunk_start = pos
                line = l
                current = ""
            elseif (pos == 10 and current:match("^interface[^%w_%.]$")) or (code:sub(pos-#current, pos-#current) .. current):match("^[^%w_]interface[^%w_%.]$") then
                output = output .. code:sub(chunk_start, pos - 10)
                print("entering interface block")
                local r, p, l = parseInterfaceDefinition(code:sub(pos - 9), name, line)
                print("exiting interface block")
                output = output .. r
                pos = pos + p - 9
                chunk_start = pos
                line = l
                current = ""
            elseif (pos == 9 and current:match("^protocol[^%w_%.]$")) or (code:sub(pos-#current, pos-#current) .. current):match("^[^%w_]protocol[^%w_%.]$") then
                output = output .. code:sub(chunk_start, pos - 9)
                print("entering protocol block")
                local r, p, l = parseInterfaceDefinition(code:sub(pos - 8), name, line)
                print("exiting protocol block")
                output = output .. r
                pos = pos + p - 8
                chunk_start = pos
                line = l
                current = ""
            else
                local found, endfound = false, false
                for k,v in pairs(blocks) do
                    local km, vm = true, true
                    for i = 1, #current do
                        if #k > 1 then
                            if i == #k+1 and not current:sub(i, i):match("^[^%w_]$") then km = false
                            elseif i <= #k and current:sub(i, i) ~= k:sub(i, i) then km = false end
                        else km = c == k end
                        if #v > 1 then
                            if i == #v+1 and not current:sub(i, i):match("^[^%w_]$") then vm = false
                            elseif i <= #v and current:sub(i, i) ~= v:sub(i, i) then vm = false end
                        else vm = c == v end
                    end
                    if km and k ~= "elseif" then
                        found = true
                        if (#k == 1 or (code:sub(pos-#current, pos-#current) .. current):match("^[^%w_]" .. k .. "[^%w_]$")) and k ~= "class" and k ~= "interface" and k ~= "protocol" then
                            print("pushed " .. k .. " at " .. pos .. " (" .. line .. ")")
                            stack.n = stack.n + 1
                            stack[stack.n] = k
                            current = ""
                            break
                        end
                    elseif vm then
                        found = true
                        if #v == 1 or (code:sub(pos-#current, pos-#current) .. current):match("^[^%w_]" .. v .. "[^%w_]$") then
                            if stack.n == 0 then error(name .. ":" .. line .. ": '<eof>' expected near '" .. current:sub(1, -2) .. "'", 2)
                            elseif k == stack[stack.n] or (v == "elseif" and stack[stack.n] == "then") then
                                print("popped " .. v .. " at " .. pos .. " (" .. line .. ")")
                                stack[stack.n] = nil
                                stack.n = stack.n - 1
                                current = ""
                                endfound = 1
                                break
                            else endfound = 0 end
                        end
                    end
                end
                if endfound == 0 then error(name .. ":" .. line .. ": '" .. blocks[stack[stack.n]] .. "' expected near '" .. current:sub(1, -2) .. "'", 2) end
                if not found then current = "" end
            end
        end
        pos = pos + 1
        if escaped then
            if escaped == 0 then escaped = false
            else escaped = escaped - 1 end
        end
    end
    if stack.n > 0 then error(name .. ":" .. line .. ": '" .. blocks[stack[stack.n]] .. "' expected near '<eof>'", 2) end
    output = output .. code:sub(chunk_start)
    if not requireEnd then return output, code:find("%S", pos), line
    else error(name .. ":" .. line .. ": 'end' expected near '<eof>'", 2) end
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
if ({...})[2] then
    local ok, contents = pcall(parseLuaBlock, str, "file", 1)
    if not ok then printError(contents) return 1 end
    file = fs.open(({...})[2], "w")
    file.writeLine('local class = require "class2"')
    file.write(contents)
    file.close()
else
    print(parseLuaBlock(str, "file", 1))
end