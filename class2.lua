-- class.lua, version 2.0b1
-- Made by JackMacWindows
-- Licensed under the MIT license

local binary_metamethods = {__add=true, __sub=true, __mul=true, __div=true, __mod=true, __pow=true, __concat=true, __eq=true, __lt=true, __le=true}

-- Use this to create a property that is set to nil by default.
local NIL = setmetatable({}, {__index = function() end, __newindex = function() end})

-- Stores all of the private (including protected) data about all objects.
-- Weak table to prevent storing objects beyond their lifetimes.
local privateData = setmetatable({}, {__mode = "k"})

-- Stores all of the protected and public members for all classes.
-- This is used when inheriting from classes. Weak table to prevent storing classes beyond their lifetimes.
local classMembers = setmetatable({}, {__mode = "k"})

local function deepcopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[deepcopy(orig_key, copies)] = deepcopy(orig_value, copies)
            end
            setmetatable(copy, deepcopy(getmetatable(orig), copies))
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- Internal function to call a method of an object, setting the self environment variable and other variables
local function call_method(obj, fn, ...)
    -- get new object pointers for private data
    local selfmt = {}
    for k,v in pairs(getmetatable(obj)) do selfmt[k] = v end
    for k,v in pairs(privateData[obj].__meta) do selfmt[k] = v end
    selfmt.__index = function(_, key)
        if privateData[obj].__keys[key] then return privateData[obj][key]
        elseif privateData[obj].__meta.__index then return privateData[obj].__meta.__index(_, key)
        else return obj[key] end
    end
    selfmt.__newindex = function(_, key, value)
        if privateData[obj].__keys[key] then
            if type(privateData[obj][key]) == "function" then error("attempt to change value of member function '" .. key .. "'", 2) end
            privateData[obj][key] = value
        elseif privateData[obj].__meta.__newindex then return privateData[obj].__meta.__newindex(_, key, value)
        else obj[key] = value end
    end
    local self = setmetatable({}, selfmt)
    -- set up environment
    local env
    env = setmetatable({
        self = self,
        super = getmetatable(obj).__super -- super OBJECT, not class
    }, {
        __index = function(_, key)
            if privateData[obj].__keys[key] then return privateData[obj][key]
            elseif getmetatable(obj).__class.hasMember(key) then return obj[key]
            elseif key == "super" then
                -- super doesn't exist, probably constructing the object
                -- return a special function for construction of super
                local s
                s = setmetatable({}, {
                    __index = function(_, idx)
                        s()
                        return env.super[idx]
                    end,
                    __newindex = function(_, idx, val)
                        s()
                        env.super[idx] = val
                    end,
                    __call = function(_, ...)
                        local objmt = getmetatable(obj)
                        local super = objmt.__superclass(...)
                        local supermt = getmetatable(super)
                        local __index, __newindex = supermt.__index, supermt.__newindex
                        supermt.__index = function(_, idx)
                            if privateData[obj].__keys[idx] == 0 then return privateData[obj][idx]
                            elseif objmt.__class.hasMember(idx) then return obj[idx]
                            else return __index(_, idx) end
                        end
                        supermt.__newindex = function(_, idx, val)
                            if privateData[obj].__keys[idx] == 0 then
                                if type(privateData[obj][idx]) == "function" then error("attempt to change value of member function '" .. tostring(idx) .. "'", 2) end
                                privateData[obj][idx] = val
                            elseif getmetatable(obj).__class.hasMember(idx) then
                                if type(obj[idx]) == "function" then error("attempt to change value of member function '" .. tostring(idx) .. "'", 2) end
                                obj[idx] = val
                            else return __newindex(_, idx, val) end
                        end
                        objmt.__super = super
                        env.super = super
                        return super
                    end
                })
                return s
            else return _ENV[key] end
        end,
        __newindex = function(e, key, value)
            if privateData[obj].__keys[key] then
                if type(privateData[obj][key]) == "function" then error("attempt to change value of member function '" .. tostring(key) .. "'", 2) end
                privateData[obj][key] = value
            elseif getmetatable(obj).__class.hasMember(key) then
                if type(obj[key]) == "function" then error("attempt to change value of member function '" .. tostring(key) .. "'", 2) end
                obj[key] = value
            else rawset(e, key, value) end
        end
    })
    setfenv(fn, env)
    -- convert any object pointers for this class to pointers with private data
    -- wish I didn't have to go and wreck the argument list, but oh well
    local args = table.pack(...)
    for i = 1, args.n do
        if type(args[i]) == "table" then
            local mt = getmetatable(args[i])
            local objmt = getmetatable(obj)
            if mt and mt.__class == objmt.__class and mt.__type == objmt.__type and privateData[args[i]] ~= nil then
                local o = args[i]
                args[i] = setmetatable({}, setmetatable({
                    __index = function(_, key)
                        if privateData[o].__keys[key] then return privateData[o][key]
                        else return o[key] end
                    end,
                    __newindex = function(_, key, value)
                        if privateData[o].__keys[key] then
                            if type(privateData[o][key]) == "function" then error("attempt to change value of member function '" .. tostring(key) .. "'", 2) end
                            privateData[o][key] = value
                        else o[key] = value end
                    end
                }, {__index = mt}))
            end
        end
    end
    -- run the function in a coroutine so if it yields we can reset the environment
    local coro = coroutine.create(fn)
    local arg = table.pack(coroutine.resume(coro, table.unpack(args, 1, args.n)))
    while coroutine.status(coro) == "suspended" do
        setfenv(fn, env)
        arg = table.pack(coroutine.resume(coro, coroutine.yield(table.unpack(arg, 1, arg.n))))
    end
    if arg[1] then return table.unpack(arg, 2, arg.n)
    else error(arg[2], 3) end
end

-- Creates a new class.
local function create_class(bodyPublic, name, inheritance, body)
    local class_mt = {}
    local class_obj = setmetatable({}, class_mt)
    local private = {properties = {}, methods = {}, dynamic = {}, meta = {}}
    local protected = {properties = {}, methods = {}, dynamic = {}, meta = {}}
    local public = {properties = {}, methods = {}, dynamic = {}, meta = {}}
    local static = {properties = {}, methods = {}, dynamic = {}, meta = {}}
    local constructor

    -- sort the members of the class into buckets by access specifier and type

    for kk,vv in pairs{private = private, protected = protected, public = public, static = static} do
        if type(body[kk]) == "table" then
            for k,v in pairs(body[kk]) do if k ~= "dynamic" and k ~= "meta" then
                if type(v) == "function" then vv.methods[k] = v
                else vv.properties[k] = v end
            end end
            if type(body[kk].dynamic) == "table" then
                for k,v in pairs(body[kk].dynamic) do
                    if type(v) == "function" then vv.dynamic[k] = {get = v}
                    elseif type(v) ~= "table" then error("invalid syntax in class definition: expected table or function for value of dynamic property '" .. k .. "', but got " .. type(v), 2)
                    elseif v.get == nil then error("invalid syntax in class definition: missing getter for dynamic property '" .. k .. "'", 2)
                    else vv.dynamic[k] = v end
                end
            end
            if type(body[kk].meta) == "table" then
                for k,v in pairs(body[kk].meta) do
                    if type(v) ~= "function" then error("invalid syntax in class definition: expected function for value of metamethod '" .. k .. "', but got " .. type(v), 2)
                    else vv.meta[k] = v end
                end
            end
        end
    end

    for k,v in pairs(body) do
        if k ~= "private" and k ~= "public" and k ~= "protected" and k ~= "dynamic" and k ~= "meta" and k ~= "new" then
            if bodyPublic then
                if type(v) == "function" then public.methods[k] = v
                else public.properties[k] = v end
            else
                if type(v) == "function" then private.methods[k] = v
                else private.properties[k] = v end
            end
        end
    end
    if type(body.dynamic) == "table" then
        for k,v in pairs(body.dynamic) do
            if type(v) == "function" then (bodyPublic and public or private).dynamic[k] = {get = v}
            elseif type(v) ~= "table" then error("invalid syntax in class definition: expected table or function for value of dynamic property '" .. k .. "', but got " .. type(v), 2)
            elseif v.get == nil then error("invalid syntax in class definition: missing getter for dynamic property '" .. k .. "'", 2)
            else (bodyPublic and public or private).dynamic[k] = v end
        end
    end
    if type(body.meta) == "table" then
        for k,v in pairs(body.meta) do
            if type(v) ~= "function" then error("invalid syntax in class definition: expected function for value of metamethod '" .. k .. "', but got " .. type(v), 2)
            else (bodyPublic and public or private).meta[k] = v end
        end
    end
    if type(body.new) == "function" then constructor = body.new
    elseif body.new ~= nil then error("invalid syntax in class definition: expected function for value of constructor, but got " .. type(body.new), 2) end

    -- set members for inheritance and check protocol conformance

    if inheritance then
        if inheritance.inherits then
            if type(classMembers[inheritance.inherits]) ~= "table" then error("runtime error while initializing object of class '" .. name .. "': could not locate inheritance information for superclass", 2) end
            for j,u in pairs(classMembers[inheritance.inherits].public) do for k,v in pairs(u) do if public[j][k] == nil then public[j][k] = v end end end
            for j,u in pairs(classMembers[inheritance.inherits].protected) do for k,v in pairs(u) do if protected[j][k] == nil then protected[j][k] = v end end end
        end
        if inheritance.implements or inheritance.conforms then
            local function checkConformance(protocol)
                for k,v in pairs(protocol.members) do
                    if v == "function" and public.methods[k] == nil then error("class '" .. name .. "' does not conform to protocol '" .. getmetatable(protocol).__name .. "' (missing method '" .. tostring(k) .. "')", 2)
                    elseif v == "var" and public.properties[k] == nil and public.dynamic[k] == nil then error("class '" .. name .. "' does not conform to protocol '" .. getmetatable(protocol).__name .. "' (missing property '" .. tostring(k) .. "')", 2)
                    elseif v == "function_optional" and public.methods[k] == nil then public.methods[k] = function() end -- if the method is optional and no implementation is available, create a dummy function
                    elseif type(v) == "function" and public.methods[k] == nil then public.methods[k] = v end -- if the value is a function (optional function) and no implementation is available, use the function as the default implementation
                end
                for _,v in ipairs(getmetatable(protocol).__implements) do if v ~= protocol then checkConformance(v) end end
            end
            for _,v in ipairs(inheritance.implements or inheritance.conforms) do checkConformance(v) end
        end
    end

    classMembers[class_obj] = {protected = protected, public = public, constructor = constructor}

    -- add class metamethods

    if static.meta.__call ~= nil then error("invalid syntax in class definition: illegal static metamethod '__call'", 2) end
    for k,v in pairs(static.meta) do class_mt[k] = v end

    function class_mt.__index(self, idx)
        if idx == "self" then return class_obj
        elseif idx == "hasMember" then
            return function(name)
                return public.properties[name] ~= nil or public.methods[name] ~= nil or public.dynamic[name] ~= nil
            end
        elseif static.properties[idx] ~= nil then
            if static.properties[idx] == NIL then return nil
            else return static.properties[idx] end
        elseif static.methods[idx] ~= nil then
            return function(...)
                local args = table.pack(...)
                for i = 1, args.n do
                    if type(args[i]) == "table" then
                        local mt = getmetatable(args[i])
                        if mt and mt.__class == class_obj and mt.__type == name and privateData[args[i]] ~= nil then
                            local o = args[i]
                            args[i] = setmetatable({}, setmetatable({
                                __index = function(_, key)
                                    if privateData[o].__keys[key] then return privateData[o][key]
                                    else return o[key] end
                                end,
                                __newindex = function(_, key, value)
                                    if privateData[o].__keys[key] then
                                        if type(privateData[o][key]) == "function" then error("attempt to change value of member function '" .. tostring(key) .. "'", 2) end
                                        privateData[o][key] = value
                                    else o[key] = value end
                                end
                            }, {__index = mt}))
                        end
                    end
                end
                return static.methods[idx](table.unpack(args, 1, args.n))
            end
        elseif static.dynamic[idx] ~= nil then
            return static.dynamic[idx].get()
        elseif public.methods[idx] ~= nil then
            return function(obj, ...)
                return call_method(obj, public.methods[idx], ...)
            end
        elseif static.meta.__index ~= nil then
            return static.meta.__index(self, idx)
        else return nil end
    end

    function class_mt.__newindex(self, idx, value)
        if static.properties[idx] ~= nil then
            if value == nil then static.properties[idx] = NIL
            else static.properties[idx] = value end
        elseif static.dynamic[idx] ~= nil then
            if static.dynamic[idx].set ~= nil then error("attempt to set value of get-only static property '" .. tostring(idx) .. "'", 2)
            else static.dynamic[idx].set(value) end
        elseif static.meta.__newindex ~= nil then
            return static.meta.__newindex(self, idx, value)
        else error("attempt to set value of invalid static property '" .. tostring(idx) .. '"', 2) end
    end

    function class_mt.__call(_, ...)
        local object_mt = {}
        local object = setmetatable({}, object_mt)
        local shadowData = {}
        local priv
        priv = setmetatable({__keys = {}, __meta = {}}, {
            __index = function(_, idx)
                if protected.methods[idx] ~= nil then
                    return function(...)
                        return call_method(object, protected.methods[idx], ...)
                    end
                elseif private.methods[idx] ~= nil then
                    return function(...)
                        return call_method(object, private.methods[idx], ...)
                    end
                elseif protected.dynamic[idx] ~= nil then
                    return call_method(object, protected.dynamic[idx].get)
                elseif private.dynamic[idx] ~= nil then
                    return call_method(object, private.dynamic[idx].get)
                else return nil end
            end,
            __newindex = function(_, idx, val)
                if protected.dynamic[idx] ~= nil and protected.dynamic[idx].set ~= nil then
                    return call_method(object, protected.dynamic[idx].set, val)
                elseif private.dynamic[idx] ~= nil and protected.dynamic[idx].set ~= nil then
                    return call_method(object, private.dynamic[idx].set, val)
                else rawset(priv, idx, val) end
            end
        })
        privateData[object] = priv

        -- initialize members with default values

        for k,v in pairs(public.properties) do if v ~= NIL then
            local ok, val = pcall(deepcopy, v)
            if ok then object_mt.shadowData[k] = val else shadowData[k] = v end
        end end
        for k,v in pairs(protected.properties) do
            priv.__keys[k] = 0
            if v ~= NIL then
                local ok, val = pcall(deepcopy, v)
                if ok then priv[k] = val else priv[k] = v end
            end
        end
        for k,v in pairs(private.properties) do
            priv.__keys[k] = 1
            if v ~= NIL then
                local ok, val = pcall(deepcopy, v)
                if ok then priv[k] = val else priv[k] = v end
            end
        end
        for k in pairs(protected.methods) do priv.__keys[k] = 0 end
        for k in pairs(private.methods) do priv.__keys[k] = 1 end
        for k in pairs(protected.dynamic) do priv.__keys[k] = 0 end
        for k in pairs(private.dynamic) do priv.__keys[k] = 1 end

        -- set up metatable

        for k,v in pairs(public.meta) do
            if binary_metamethods[k] then
                object_mt[k] = function(...) return call_method(object, v, ...) end
            else
                object_mt[k] = function(_, ...) return call_method(object, v, ...) end
            end
        end
        for k,v in pairs(protected.meta) do
            if binary_metamethods[k] then
                priv.__meta[k] = function(...) return call_method(object, v, ...) end
            else
                priv.__meta[k] = function(_, ...) return call_method(object, v, ...) end
            end
        end
        for k,v in pairs(private.meta) do
            if binary_metamethods[k] then
                priv.__meta[k] = function(...) return call_method(object, v, ...) end
            else
                priv.__meta[k] = function(_, ...) return call_method(object, v, ...) end
            end
        end

        function object_mt.__index(_, idx)
            if public.properties[idx] ~= nil then
                return shadowData[idx]
            elseif public.methods[idx] ~= nil then
                return function(...)
                    return call_method(object, public.methods[idx], ...)
                end
            elseif public.dynamic[idx] ~= nil then
                return call_method(object, public.dynamic[idx].get)
            elseif public.meta.__index ~= nil then
                return call_method(object, public.meta.__index, idx)
            else error("attempt to access invalid member '" .. tostring(idx) .. "'", 2) end
        end

        function object_mt.__newindex(_, idx, value)
            if public.properties[idx] ~= nil then
                shadowData[idx] = value
            elseif public.dynamic[idx] ~= nil then
                if public.dynamic[idx].set == nil then error("attempt to set value of get-only property '" .. tostring(idx) .. "'", 2) end
                return call_method(object, public.dynamic[idx].set, value)
            elseif public.meta.__newindex ~= nil then
                return call_method(object, public.meta.__newindex, idx, value)
            else error("attempt to write to invalid member '" .. tostring(idx) .. "'", 2) end
        end

        object_mt.__class = class_obj
        object_mt.__type = name
        object_mt.__tostring = object_mt.__tostring or function() return "[object " .. name .. "]" end
        object_mt.__superclass = inheritance and inheritance.inherits
        object_mt.__implements = inheritance and (inheritance.implements or inheritance.conforms) or {}

        -- call constructor if present

        if constructor then call_method(object, constructor, ...) end

        -- construct superobject if inherited + not constructed in constructor

        if inheritance and inheritance.inherits and object_mt.__super == nil then
            local super = inheritance.inherits(...)
            local supermt = getmetatable(super)
            local __index, __newindex = supermt.__index, supermt.__newindex
            supermt.__index = function(_, idx)
                if priv.__keys[idx] == 0 then return priv[idx]
                elseif class_obj.hasMember(idx) then return object[idx]
                else return __index(_, idx) end
            end
            supermt.__newindex = function(_, idx, val)
                if priv.__keys[idx] == 0 then
                    if type(priv[idx]) == "function" then error("attempt to change value of member function '" .. tostring(idx) .. "'", 2) end
                    priv[idx] = val
                elseif class_obj.hasMember(idx) then
                    if type(object[idx]) == "function" then error("attempt to change value of member function '" .. tostring(idx) .. "'", 2) end
                    object[idx] = val
                else return __newindex(_, idx, val) end
            end
            object_mt.__super = super
        end

        return object
    end

    class_mt.__name = name
    class_mt.__type = "class"
    class_mt.__class = class_mt
    class_mt.__tostring = function() return "[class " .. name .. "]" end
    class_mt.__superclass = inheritance and inheritance.inherits
    class_mt.__implements = inheritance and (inheritance.implements or inheritance.conforms) or {}

    return class_obj
end

-- Protocols are pretty simple - they just store the list of stuff required + some metadata.
-- Most of the logic is actually in class creation!
local function create_protocol(name, inheritance, body)
    local protocol_mt = {}
    local protocol_obj = setmetatable({members = body}, protocol_mt)

    function protocol_obj.hasMember(name)
        if protocol_mt.members[keys] ~= nil then return true end
        for _,v in ipairs(protocol_mt.__implements) do
            if v.hasMember(name) then return true end
        end
        return false
    end

    protocol_mt.__name = name
    protocol_mt.__type = "protocol"
    protocol_mt.__tostring = function() return "[protocol " .. name .. "]" end
    protocol_mt.__implements = inheritance and (inheritance.implements or inheritance.conforms) or {}
    table.insert(protocol_mt.__implements, 1, protocol_obj)

    return protocol_obj
end

local function class(name)
    return function(t)
        if t.extends or t.implements then
            return function(b)
                return create_class(false, name, t, b)
            end
        else
            return create_class(false, name, nil, t)
        end
    end
end

local function struct(name)
    return function(t)
        if t.extends or t.implements then
            return function(b)
                return create_class(true, name, t, b)
            end
        else
            return create_class(true, name, nil, t)
        end
    end
end

local function protocol(name)
    return function(t)
        if t.implements then
            return function(b)
                return create_protocol(name, t, b)
            end
        else
            return create_protocol(name, nil, t)
        end
    end
end

local function recursive_protocol_check(list, protocol, a)
    for _,v in ipairs(list) do if v ~= a then
        if protocol == v or recursive_protocol_check(getmetatable(v).__implements, protocol, v) then return true end
    end end
    return false
end

local function instanceof(object, class)
    if type(object) ~= "table" then return false end
    if type(class) ~= "table" or getmetatable(class) == nil or getmetatable(class).__type == nil then error("bad argument #2 (expected class or protocol, got " .. type(class) .. ")", 2) end
    local mt = getmetatable(object)
    if mt == nil or mt.__class == nil then return false end
    if getmetatable(class).__type == "class" then
        if mt.__class == class then return true end
        local s = mt.__superclass
        while s ~= nil do
            if s == class then return true end
            s = getmetatable(s).__superclass
        end
    elseif getmetatable(class).__type == "protocol" then
        return recursive_protocol_check(mt.__implements, class)
    else error("bad argument #2 (expected class or protocol, got " .. getmetatable(class).__type .. ")", 2) end
end

local function typeof(object)
    if type(object) ~= "table" or getmetatable(object) == nil or getmetatable(object).__type == nil then return nil
    else return getmetatable(object).__type end
end

return {
    class = class,
    struct = struct,
    protocol = setmetatable({
        var = "var",
        func = "function",
        optfunc = "function_optional"
    }, {__call = function(_, ...) return protocol(...) end}),
    interface = protocol,
    instanceof = instanceof,
    typeof = typeof,
    NIL = NIL
}