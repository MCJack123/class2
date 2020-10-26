local class = require "class2"

local IContainer = class.interface "IContainer" {
	push = "function",
	pop = "function",
	count = "var"
}

local Array
Array = class.class "Array" {implements = {IContainer}} {
    private = {
        tab = {},
        size = 0
    },
    new = function(a, b)
		if class.instanceof(a, Array) and b == nil then
			for i,v in ipairs(a.tab) do tab[i] = v end
			size = #tab
		elseif type(a) == "table" and b == nil then
			for i,v in ipairs(a) do tab[i] = v end
			size = #tab
		elseif type(a) == "number" and (b == nil or type(b) == "number") then
			for i = 1, a do tab[i] = b or 0 end
			size = a
		elseif a ~= nil or b ~= nil then
			error("invalid constructor with types (" .. type(a) .. ", " .. type(b) .. ")", 2)
		end
    end,
    public = {
        meta = {
            __index = function(idx)
                if type(idx) ~= "number" then error("bad argument #1 (expected number, got " .. type(idx) .. ")", 2) end
                if idx < 1 or idx > #tab then error("bad argument #1 (index out of range)", 2) end
                return tab[idx]
            end,
            __newindex = function(idx, val)
                if type(idx) ~= "number" then error("bad argument #1 (expected number, got " .. type(idx) .. ")", 2) end
                if idx < 1 or idx > #tab then error("bad argument #1 (index out of range)", 2) end
                tab[idx] = val
            end,
            __ipairs = function()
                return ipairs(tab)
            end,
            __pairs = function()
                return ipairs(tab)
            end
        },

        push_back = function(val)
            tab[size + 1] = val
            size = size + 1
        end,
        pop_back = function()
            if size < 1 then error("attempted to pop empty array", 2) end
            local val = tab[size]
            tab[size] = nil
            size = size - 1
            return val
        end,
        push_front = function(val)
            table.insert(tab, 1, val)
            size = size + 1
        end,
        pop_front = function()
            if size < 1 then error("attempted to pop empty array", 2) end
            size = size + 1
            return table.remove(tab, 1)
        end,
        insert = function(pos, val)
            if pos < 1 or pos > size + 1 then error("bad argument #1 (index out of range)", 2) end
            table.insert(tab, pos, val)
            size = size + 1
        end,
        erase = function(pos)
            if pos < 1 or pos > size then error("bad argument #1 (index out of range)", 2) end
            local val = table.remove(tab, pos)
            size = size - 1
            return val
        end,
        clear = function()
            self.tab = {}
            self.size = 0
        end,

        -- MARK: IContainer
        dynamic = {
            count = {
                get = function()
                    return size
                end
            }
        },
        push = function(val)
            return push_back(val)
        end,
        pop = function()
            return pop_back(val)
        end,
    },
    static = {
        combine = function(a, b)
            if not class.instanceof(a, Array) then error("bad argument #1 (expected Array, got " .. (class.typeof(a) or type(a)) .. ")", 2) end
            if not class.instanceof(b, Array) then error("bad argument #2 (expected Array, got " .. (class.typeof(b) or type(b)) .. ")", 2) end
            local c = Array(a)
            for i = 1, b.count do c.push_back(b[i]) end
            return c
        end
    }
}

local a = Array {7, 1, 4, 9}
print("A:", a)
for i, v in pairs(a) do print(i .. " => " .. v) end
local b = Array.combine(a, Array(3, 12))
print("B:", b)
for i = 1, b.count do write(b[i] .. (i == b.count and "" or ", ")) end
print()
assert(class.instanceof(a, IContainer))
assert(class.instanceof(b, IContainer))
assert(class.instanceof(Array, IContainer))