local C = require("curses")
local re = require('re')
local unpack = table.unpack or _G.unpack
local line_matcher = re.compile('lines<-{| line ("\n" line)* |} line<-{[^\n]*}')
local ldb
local AUTO = { }
local PARENT = { }
local launched = false
local _error = error
local _assert = assert
local callstack_range
callstack_range = function()
  local min, max = 0, -1
  for i = 1, 999 do
    local info = debug.getinfo(i, 'f')
    if not info then
      min = i - 1
      break
    end
    if info.func == ldb.run_debugger then
      min = i + 2
      break
    end
  end
  for i = min, 999 do
    local info = debug.getinfo(i, 'f')
    if not info or info.func == ldb.guard then
      max = i - 3
      break
    end
  end
  return min, max
end
local wrap_text
wrap_text = function(text, width)
  local lines = { }
  local _list_0 = line_matcher:match(text)
  for _index_0 = 1, #_list_0 do
    local line = _list_0[_index_0]
    while #line > width do
      table.insert(lines, line:sub(1, width))
      line = line:sub(width + 1, -1)
      if #line == 0 then
        line = nil
      end
    end
    if line then
      table.insert(lines, line)
    end
  end
  return lines
end
local Color
do
  local color_index = 0
  local existing = { }
  local make_color
  make_color = function(fg, bg)
    if fg == nil then
      fg = -1
    end
    if bg == nil then
      bg = -1
    end
    local key = tostring(fg) .. "," .. tostring(bg)
    if not (existing[key]) then
      color_index = color_index + 1
      C.init_pair(color_index, fg, bg)
      existing[key] = C.color_pair(color_index)
    end
    return existing[key]
  end
  local color_lang = re.compile([[        x <- {|
            {:attrs: {| {attr} (" " {attr})* |} :}
            / (
                ({:bg: "on " {color} :} / ({:fg: color :} (" on " {:bg: color :})?))
                {:attrs: {| (" " {attr})* |} :})
        |}
        attr <- "blink" / "bold" / "dim" / "invis" / "normal" / "protect" / "reverse" / "standout" / "underline" / "altcharset"
        color <- "black" / "blue" / "cyan" / "green" / "magenta" / "red" / "white" / "yellow" / "default"
    ]])
  C.COLOR_DEFAULT = -1
  Color = function(s)
    if s == nil then
      s = "default"
    end
    local t = _assert(color_lang:match(s), "Invalid color: " .. tostring(s))
    if t.fg then
      t.fg = C["COLOR_" .. t.fg:upper()]
    end
    if t.bg then
      t.bg = C["COLOR_" .. t.bg:upper()]
    end
    local c = make_color(t.fg, t.bg)
    local _list_0 = t.attrs
    for _index_0 = 1, #_list_0 do
      local a = _list_0[_index_0]
      c = c | C["A_" .. a:upper()]
    end
    return c
  end
end
local Pad
do
  local _class_0
  local _base_0 = {
    configure_size = function(self, height, width)
      self.height, self.width = height, width
      self._height = math.max(#self.columns[1], 1)
      if self.height == AUTO then
        self.height = self._height + 2
      end
      self._width = #self.columns - 1
      for i, col in ipairs(self.columns) do
        local col_width = 0
        for _index_0 = 1, #col do
          local chunk = col[_index_0]
          col_width = math.max(col_width, #chunk)
        end
        self._width = self._width + col_width
      end
      self._width = math.max(self._width, 6)
      if self.width == AUTO then
        self.width = self._width + 2
      end
    end,
    setup_chstr = function(self, i)
      local chstr = _assert(self.chstrs[i], "Failed to find chstrs[" .. tostring(i) .. "]")
      local x = 0
      for c = 1, #self.columns do
        local attr = self.colors[c](self, i)
        local chunk = self.columns[c][i]
        chstr:set_str(x, chunk, attr)
        x = x + #chunk
        if #chunk < self.column_widths[c] then
          chstr:set_str(x, " ", attr, self.column_widths[c] - #chunk)
          x = x + (self.column_widths[c] - #chunk)
        end
        if c < #self.columns then
          chstr:set_ch(x, C.ACS_VLINE, Color("black bold"))
          x = x + 1
        end
      end
      self._pad:mvaddchstr(i - 1, 0, chstr)
      self.dirty = true
    end,
    set_active = function(self, active)
      if active == self.active then
        return 
      end
      self.active = active
      self._frame:attrset(active and self.active_frame or self.inactive_frame)
      self.dirty = true
    end,
    select = function(self, i)
      if #self.columns[1] == 0 then
        i = nil
      end
      if i == self.selected then
        return self.selected
      end
      local old_y, old_x = self.scroll_y, self.scroll_x
      if i ~= nil then
        i = math.max(1, math.min(#self.columns[1], i))
      end
      local old_selected
      old_selected, self.selected = self.selected, i
      if old_selected then
        self:setup_chstr(old_selected)
      end
      if self.selected then
        self:setup_chstr(self.selected)
        local scrolloff = 3
        if self.selected > self.scroll_y + (self.height - 2) - scrolloff then
          self.scroll_y = self.selected - (self.height - 2) + scrolloff
        elseif self.selected < self.scroll_y + scrolloff then
          self.scroll_y = self.selected - scrolloff
        end
        self.scroll_y = math.max(1, math.min(self._height, self.scroll_y))
      end
      if self.scroll_y == old_y then
        local w = math.min(self.width - 2, self._width)
        if old_selected and self.scroll_y <= old_selected and old_selected <= self.scroll_y + self.height - 2 then
          self._pad:pnoutrefresh(old_selected - 1, self.scroll_x - 1, self.y + 1 + (old_selected - self.scroll_y), self.x + 1, self.y + 1 + (old_selected - self.scroll_y) + 1, self.x + w)
        end
        if self.selected and self.scroll_y <= self.selected and self.selected <= self.scroll_y + self.height - 2 then
          self._pad:pnoutrefresh(self.selected - 1, self.scroll_x - 1, self.y + 1 + (self.selected - self.scroll_y), self.x + 1, self.y + 1 + (self.selected - self.scroll_y) + 1, self.x + w)
        end
      else
        self.dirty = true
      end
      if self.on_select then
        self:on_select(self.selected)
      end
      return self.selected
    end,
    scroll = function(self, dy, dx)
      local old_y, old_x = self.scroll_y, self.scroll_x
      if self.selected ~= nil then
        self:select(self.selected + (dy or 0))
      else
        self.scroll_y = math.max(1, math.min(self._height - (self.height - 2 - 1), self.scroll_y + (dy or 0)))
      end
      self.scroll_x = math.max(1, math.min(self._width - (self.width - 2 - 1), self.scroll_x + (dx or 0)))
      if self.scroll_y ~= old_y or self.scroll_x ~= old_x then
        self.dirty = true
      end
    end,
    refresh = function(self, force)
      if force == nil then
        force = false
      end
      if not force and not self.dirty then
        return 
      end
      self._frame:border(C.ACS_VLINE, C.ACS_VLINE, C.ACS_HLINE, C.ACS_HLINE, C.ACS_ULCORNER, C.ACS_URCORNER, C.ACS_LLCORNER, C.ACS_LRCORNER)
      if self.label then
        self._frame:mvaddstr(0, math.floor((self.width - #self.label - 2) / 2), " " .. tostring(self.label) .. " ")
      end
      self._frame:refresh()
      local h, w = math.min(self.height - 2, self._height), math.min(self.width - 2, self._width)
      self._pad:pnoutrefresh(self.scroll_y - 1, self.scroll_x - 1, self.y + 1, self.x + 1, self.y + h, self.x + w)
      self.dirty = false
    end,
    keypress = function(self, c)
      local _exp_0 = c
      if C.KEY_DOWN == _exp_0 or C.KEY_SR == _exp_0 or ("j"):byte() == _exp_0 then
        return self:scroll(1, 0)
      elseif ('J'):byte() == _exp_0 then
        return self:scroll(10, 0)
      elseif C.KEY_UP == _exp_0 or C.KEY_SF == _exp_0 or ("k"):byte() == _exp_0 then
        return self:scroll(-1, 0)
      elseif ('K'):byte() == _exp_0 then
        return self:scroll(-10, 0)
      elseif C.KEY_RIGHT == _exp_0 or ("l"):byte() == _exp_0 then
        return self:scroll(0, 1)
      elseif ("L"):byte() == _exp_0 then
        return self:scroll(0, 10)
      elseif C.KEY_LEFT == _exp_0 or ("h"):byte() == _exp_0 then
        return self:scroll(0, -1)
      elseif ("H"):byte() == _exp_0 then
        return self:scroll(0, -10)
      end
    end,
    erase = function(self)
      self.dirty = true
      self._frame:erase()
      return self._frame:refresh()
    end,
    __gc = function(self)
      self._frame:close()
      return self._pad:close()
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, label, y, x, height, width, ...)
      self.label, self.y, self.x = label, y, x
      self.scroll_y, self.scroll_x = 1, 1
      self.selected = nil
      self.columns = { }
      self.column_widths = { }
      self.active_frame = Color("yellow bold")
      self.inactive_frame = Color("blue dim")
      self.colors = { }
      for i = 1, select('#', ...) - 1, 2 do
        local col = select(i, ...)
        table.insert(self.columns, col)
        local w = 0
        for _index_0 = 1, #col do
          local chunk = col[_index_0]
          w = math.max(w, #chunk)
        end
        table.insert(self.column_widths, w)
        local color_fn = select(i + 1, ...) or (function(self, i)
          return Color()
        end)
        _assert(type(color_fn) == 'function', "Invalid color function type: " .. tostring(type(color_fn)))
        table.insert(self.colors, color_fn)
      end
      self:configure_size(height, width)
      self._frame = C.newwin(self.height, self.width, self.y, self.x)
      self._frame:immedok(true)
      self._pad = C.newpad(self._height, self._width)
      self._pad:scrollok(true)
      self:set_active(false)
      self.chstrs = { }
      for i = 1, #self.columns[1] do
        self.chstrs[i] = C.new_chstr(self._width)
        self:setup_chstr(i)
      end
      self.dirty = true
    end,
    __base = _base_0,
    __name = "Pad"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Pad = _class_0
end
local NumberedPad
do
  local _class_0
  local _parent_0 = Pad
  local _base_0 = { }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, label, y, x, height, width, ...)
      self.label, self.y, self.x = label, y, x
      local col1 = select(1, ...)
      local fmt = "%" .. tostring(#tostring(#col1)) .. "d"
      local line_nums
      do
        local _accum_0 = { }
        local _len_0 = 1
        for i = 1, #col1 do
          _accum_0[_len_0] = fmt:format(i)
          _len_0 = _len_0 + 1
        end
        line_nums = _accum_0
      end
      local cols = {
        line_nums,
        (function(self, i)
          return i == self.selected and Color() or Color("yellow")
        end),
        ...
      }
      return _class_0.__parent.__init(self, self.label, self.y, self.x, height, width, unpack(cols))
    end,
    __base = _base_0,
    __name = "NumberedPad",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  NumberedPad = _class_0
end
local expansions = { }
local TOP_LOCATION, KEY, VALUE = { }, { }, { }
local locations = { }
local Location
Location = function(old_loc, kind, key)
  if old_loc == nil then
    return TOP_LOCATION
  end
  if not (locations[old_loc]) then
    locations[old_loc] = { }
  end
  if not (locations[old_loc][kind]) then
    locations[old_loc][kind] = { }
  end
  if not (locations[old_loc][kind][key]) then
    locations[old_loc][kind][key] = {
      old_loc = old_loc,
      kind = kind,
      key = key
    }
  end
  return locations[old_loc][kind][key]
end
local expand
expand = function(kind, key, location)
  expansions[Location(location, kind, key)] = true
end
local collapse
collapse = function(kind, key, location)
  expansions[Location(location, kind, key)] = nil
end
local is_key_expanded
is_key_expanded = function(location, key)
  return expansions[Location(location, KEY, key)]
end
local is_value_expanded
is_value_expanded = function(location, key)
  return expansions[Location(location, VALUE, key)]
end
local TYPE_COLORS = setmetatable({ }, {
  __index = 0
})
local colored_repr
colored_repr = function(x, width, depth)
  if depth == nil then
    depth = 2
  end
  depth = depth - 1
  local x_type = type(x)
  if x_type == 'table' then
    if next(x) == nil then
      return {
        "{}",
        TYPE_COLORS.table
      }
    end
    if depth == 0 then
      return {
        "{",
        TYPE_COLORS.table,
        "...",
        Color('white'),
        "}",
        TYPE_COLORS.table
      }
    end
    local ret = {
      "{",
      TYPE_COLORS.table
    }
    local i = 1
    for k, v in pairs(x) do
      if k == i then
        local _list_0 = colored_repr(x[i], width, depth)
        for _index_0 = 1, #_list_0 do
          local s = _list_0[_index_0]
          ret[#ret + 1] = s
        end
        i = i + 1
      else
        local _list_0 = colored_repr(k, width, depth)
        for _index_0 = 1, #_list_0 do
          local s = _list_0[_index_0]
          ret[#ret + 1] = s
        end
        ret[#ret + 1] = ' = '
        ret[#ret + 1] = Color('white')
        local _list_1 = colored_repr(v, width, depth)
        for _index_0 = 1, #_list_1 do
          local s = _list_1[_index_0]
          ret[#ret + 1] = s
        end
      end
      ret[#ret + 1] = ', '
      ret[#ret + 1] = Color('white')
    end
    if #ret > 2 then
      ret[#ret] = nil
      ret[#ret] = nil
    end
    local len = 0
    for i = 1, #ret - 1, 2 do
      len = len + #ret[i]
    end
    for i = #ret - 1, 3, -2 do
      if len <= width - 1 then
        break
      end
      if ret[i + 2] then
        ret[i + 2], ret[i + 3] = nil, nil
      end
      ret[i] = '...'
      ret[i + 1] = Color('white')
    end
    ret[#ret + 1] = '}'
    ret[#ret + 1] = TYPE_COLORS.table
    return ret
  elseif x_type == 'string' then
    local ret = {
      (x:match('^[^\t\r\v\b\a\n]*')),
      TYPE_COLORS.string
    }
    for escape, line in x:gmatch('([\t\r\v\b\a\n])([^\t\r\v\b\a\n]*)') do
      ret[#ret + 1] = '\\' .. ({
        ['\t'] = 't',
        ['\r'] = 'r',
        ['\v'] = 'v',
        ['\b'] = 'b',
        ['\a'] = 'a',
        ['\n'] = 'n'
      })[escape]
      ret[#ret + 1] = Color('white on black')
      ret[#ret + 1] = line
      ret[#ret + 1] = TYPE_COLORS.string
    end
    local len = 0
    for i = 1, #ret - 1, 2 do
      len = len + #ret[i]
    end
    for i = #ret - 1, 1, -2 do
      if len <= width then
        break
      end
      if ret[i + 2] then
        ret[i + 2], ret[i + 3] = nil, nil
      end
      len = len - #ret[i]
      if len <= width then
        ret[i] = ret[i]:sub(1, width - len - 3)
        ret[i + 2] = '...'
        ret[i + 3] = Color('blue')
        break
      end
    end
    return ret
  else
    local ok, s = pcall(tostring, x)
    if not ok then
      return {
        "tostring error: " .. s,
        Color("red")
      }
    end
    if #s > width then
      return {
        s:sub(1, width - 3),
        TYPE_COLORS[type(x)],
        '...',
        Color('blue')
      }
    else
      return {
        s,
        TYPE_COLORS[type(x)]
      }
    end
  end
end
local make_lines
make_lines = function(location, x, width)
  local _exp_0 = type(x)
  if 'string' == _exp_0 then
    local lines = { }
    local _list_0 = line_matcher:match(x)
    for _index_0 = 1, #_list_0 do
      local line = _list_0[_index_0]
      local wrapped = wrap_text(line, width - 1)
      for i, subline in ipairs(wrapped) do
        local _line = {
          location = location
        }
        if i > 1 then
          table.insert(_line, C.ACS_BULLET)
          table.insert(_line, Color('black bold altcharset'))
        end
        table.insert(_line, subline)
        table.insert(_line, Color('blue on black'))
        table.insert(lines, _line)
      end
    end
    if #lines == 0 then
      table.insert(lines, {
        location = location,
        "''",
        Color('blue')
      })
    end
    return lines
  elseif 'table' == _exp_0 then
    local prepend
    prepend = function(line, ...)
      for i = 1, select('#', ...) do
        table.insert(line, i, (select(i, ...)))
      end
    end
    local lines = { }
    for k, v in pairs(x) do
      if is_key_expanded(location, k) and is_value_expanded(location, k) then
        table.insert(lines, {
          location = Location(location, KEY, k),
          'key',
          Color('green bold'),
          '/',
          Color(),
          'value',
          Color('blue bold'),
          ':',
          Color('white')
        })
        local key_lines = make_lines(Location(location, KEY, k), k, width - 1)
        for i, key_line in ipairs(key_lines) do
          if i == 1 then
            prepend(key_line, ' ', Color(), C.ACS_DIAMOND, Color('green bold'), ' ', Color())
          else
            prepend(key_line, '   ', Color())
          end
          table.insert(lines, key_line)
        end
        local value_lines = make_lines(Location(location, VALUE, k), v, width - 2)
        for i, value_line in ipairs(value_lines) do
          if i == 1 then
            prepend(value_line, ' ', Color(), C.ACS_DIAMOND, Color('blue bold'), ' ', Color())
          else
            prepend(value_line, '   ', Color())
          end
          table.insert(lines, value_line)
        end
      elseif is_value_expanded(location, k) then
        local k_str = colored_repr(k, width - 1)
        table.insert(lines, {
          location = Location(location, KEY, k),
          '-',
          Color('red'),
          unpack(k_str)
        })
        local v_lines = make_lines(Location(location, VALUE, k), v, width - 1)
        prepend(v_lines[1], '  ', Color())
        for i = 2, #v_lines do
          prepend(v_lines[i], '  ', Color())
        end
        for _index_0 = 1, #v_lines do
          local v_line = v_lines[_index_0]
          table.insert(lines, v_line)
        end
      elseif is_key_expanded(location, k) then
        local k_lines = make_lines(Location(location, KEY, k), k, width - 4)
        for i = 1, #k_lines do
          prepend(k_lines[i], '    ', Color())
        end
        for _index_0 = 1, #k_lines do
          local k_line = k_lines[_index_0]
          table.insert(lines, k_line)
        end
        local v_str = colored_repr(v, width - 2)
        table.insert(lines, {
          location = Location(location, VALUE, k),
          '  ',
          Color(),
          unpack(v_str)
        })
      else
        local k_space = math.floor((width - 4) / 3)
        local k_str = colored_repr(k, k_space)
        local v_space = (width - 4) - #k_str
        local v_str = colored_repr(v, v_space)
        local line = {
          location = Location(location, VALUE, k),
          '+',
          Color('green'),
          unpack(k_str)
        }
        table.insert(line, ' = ')
        table.insert(line, Color('white'))
        for _index_0 = 1, #v_str do
          local s = v_str[_index_0]
          table.insert(line, s)
        end
        table.insert(lines, line)
      end
    end
    if #lines == 0 then
      table.insert(lines, {
        location = location,
        '{}',
        TYPE_COLORS.table
      })
    end
    return lines
  else
    if getmetatable(x) and getmetatable(x).__pairs then
      local lines = make_lines(location, (function()
        local _tbl_0 = { }
        for k, v in pairs(x) do
          _tbl_0[k] = v
        end
        return _tbl_0
      end)(), width)
      if getmetatable(x).__tostring then
        local s_lines = { }
        local ok, s = pcall(tostring, x)
        if not ok then
          s = "tostring error: " .. s
        end
        local _list_0 = line_matcher:match(s)
        for _index_0 = 1, #_list_0 do
          local line = _list_0[_index_0]
          local wrapped = wrap_text(line, width)
          for i, subline in ipairs(wrapped) do
            table.insert(s_lines, {
              location = location,
              subline,
              ok and Color('yellow') or Color('red')
            })
          end
        end
        for i = 1, #s_lines do
          table.insert(lines, i, s_lines[i])
        end
      end
      return lines
    end
    local str = tostring(x)
    if #str > width then
      str = str:sub(1, width - 3) .. '...'
    end
    return {
      {
        location = location,
        str,
        TYPE_COLORS[type(x)]
      }
    }
  end
end
local DataViewer
do
  local _class_0
  local _parent_0 = Pad
  local _base_0 = {
    setup_chstr = function(self, i) end,
    configure_size = function(self, height, width)
      self.height, self.width = height, width
      self._height, self._width = #self.chstrs, self.width - 2
    end,
    select = function(self, i)
      if #self.chstrs == 0 then
        i = nil
      end
      if i == self.selected then
        return self.selected
      end
      local old_y, old_x = self.scroll_y, self.scroll_x
      if i ~= nil then
        i = math.max(1, math.min(#self.chstrs, i))
      end
      local old_selected
      old_selected, self.selected = self.selected, i
      if old_selected and self.chstrs[old_selected] then
        self.chstrs[old_selected]:set_str(0, ' ', Color('yellow bold'))
        self._pad:mvaddchstr(old_selected - 1, 0, self.chstrs[old_selected])
      end
      if self.selected then
        self.chstrs[self.selected]:set_ch(0, C.ACS_RARROW, Color('yellow bold'))
        self._pad:mvaddchstr(self.selected - 1, 0, self.chstrs[self.selected])
        local scrolloff = 3
        if self.selected > self.scroll_y + (self.height - 2) - scrolloff then
          self.scroll_y = self.selected - (self.height - 2) + scrolloff
        elseif self.selected < self.scroll_y + scrolloff then
          self.scroll_y = self.selected - scrolloff
        end
        self.scroll_y = math.max(1, math.min(self._height, self.scroll_y))
      end
      if self.scroll_y == old_y then
        local w = math.min(self.width - 2, self._width)
        if old_selected and self.scroll_y <= old_selected and old_selected <= self.scroll_y + self.height - 2 then
          self._pad:pnoutrefresh(old_selected - 1, self.scroll_x - 1, self.y + 1 + (old_selected - self.scroll_y), self.x + 1, self.y + 1 + (old_selected - self.scroll_y) + 1, self.x + w)
        end
        if self.selected and self.scroll_y <= self.selected and self.selected <= self.scroll_y + self.height - 2 then
          self._pad:pnoutrefresh(self.selected - 1, self.scroll_x - 1, self.y + 1 + (self.selected - self.scroll_y), self.x + 1, self.y + 1 + (self.selected - self.scroll_y) + 1, self.x + w)
        end
      else
        self.dirty = true
      end
      if self.on_select then
        self:on_select(self.selected)
      end
      return self.selected
    end,
    keypress = function(self, c)
      local _exp_0 = c
      if C.KEY_DOWN == _exp_0 or C.KEY_SR == _exp_0 or ("j"):byte() == _exp_0 then
        return self:scroll(1, 0)
      elseif ('J'):byte() == _exp_0 then
        return self:scroll(10, 0)
      elseif C.KEY_UP == _exp_0 or C.KEY_SF == _exp_0 or ("k"):byte() == _exp_0 then
        return self:scroll(-1, 0)
      elseif ('K'):byte() == _exp_0 then
        return self:scroll(-10, 0)
      elseif C.KEY_RIGHT == _exp_0 or ("l"):byte() == _exp_0 then
        expansions[self.chstr_locations[self.selected]] = true
        return self:full_refresh()
      elseif ("L"):byte() == _exp_0 then
        expansions[self.chstr_locations[self.selected]] = true
        return self:full_refresh()
      elseif C.KEY_LEFT == _exp_0 or ("h"):byte() == _exp_0 then
        local loc = self.chstr_locations[self.selected]
        if expansions[loc] == nil then
          loc = Location(loc.old_loc, (loc.kind == KEY and VALUE or KEY), loc.key)
        end
        while loc and expansions[loc] == nil do
          loc = loc.old_loc
        end
        if loc then
          expansions[loc] = nil
        end
        self:full_refresh()
        if loc and self.chstr_locations[self.selected] ~= loc then
          for i, chstr_loc in ipairs(self.chstr_locations) do
            if chstr_loc == loc then
              self:select(i)
              break
            end
          end
        elseif not loc then
          return self:select(1)
        end
      elseif ("H"):byte() == _exp_0 then
        local loc = self.chstr_locations[self.selected]
        if expansions[loc] == nil then
          loc = Location(loc.old_loc, (loc.kind == KEY and VALUE or KEY), loc.key)
        end
        while loc and expansions[loc] == nil do
          loc = loc.old_loc
        end
        if loc then
          expansions[loc] = nil
        end
        self:full_refresh()
        if loc and self.chstr_locations[self.selected] ~= loc then
          for i, chstr_loc in ipairs(self.chstr_locations) do
            if chstr_loc == loc then
              self:select(i)
              break
            end
          end
        elseif not loc then
          return self:select(1)
        end
      end
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, data, label, y, x, height, width)
      self.data, self.label, self.y, self.x = data, label, y, x
      self.scroll_y, self.scroll_x = 1, 1
      self.selected = nil
      self.active_frame = Color("yellow bold")
      self.inactive_frame = Color("blue dim")
      self.full_refresh = function()
        local old_location = self.selected and self.chstr_locations and self.chstr_locations[self.selected]
        self.chstrs, self.chstr_locations = { }, { }
        local W = width - 3
        local lines = make_lines(TOP_LOCATION, self.data, W)
        for i, line in ipairs(lines) do
          local chstr = C.new_chstr(W)
          if i == self.selected then
            chstr:set_ch(0, C.ACS_RARROW, Color('yellow bold'))
          else
            chstr:set_str(0, ' ', Color('yellow bold'))
          end
          local offset = 1
          for j = 1, #line - 1, 2 do
            local chunk, attrs = line[j], line[j + 1]
            if type(chunk) == 'number' then
              chstr:set_ch(offset, chunk, attrs)
              offset = offset + 1
            else
              chstr:set_str(offset, chunk, attrs)
              offset = offset + #chunk
            end
          end
          if offset < W then
            chstr:set_str(offset, ' ', attrs, W - offset)
          end
          table.insert(self.chstrs, chstr)
          table.insert(self.chstr_locations, line.location)
        end
        self._height, self._width = #self.chstrs, self.width - 2
        self._pad:resize(self._height, self._width)
        for i, chstr in ipairs(self.chstrs) do
          self._pad:mvaddchstr(i - 1, 0, chstr)
        end
        self.dirty = true
        if old_location then
          for i, loc in ipairs(self.chstr_locations) do
            if loc == old_location then
              self:select(i)
              break
            end
          end
        end
      end
      self.height, self.width = height, width
      self._frame = C.newwin(self.height, self.width, self.y, self.x)
      self._frame:immedok(true)
      self._pad = C.newpad(self.height - 2, self.width - 2)
      self._pad:scrollok(true)
      self:set_active(false)
      self:full_refresh()
      return self:select(1)
    end,
    __base = _base_0,
    __name = "DataViewer",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  DataViewer = _class_0
end
local ok, to_lua = pcall(function()
  return require('moonscript.base').to_lua
end)
if not ok then
  to_lua = function()
    return nil
  end
end
local file_cache = setmetatable({ }, {
  __index = function(self, filename)
    local file = io.open(filename)
    if not file then
      return nil
    end
    local contents = file:read("a"):sub(1, -2)
    self[filename] = contents
    return contents
  end
})
local line_tables = setmetatable({ }, {
  __index = function(self, filename)
    local file = file_cache[filename]
    if not file then
      return nil
    end
    local line_table
    ok, line_table = to_lua(file)
    if ok then
      self[filename] = line_table
      return line_table
    end
  end
})
local err_hand
err_hand = function(err)
  C.endwin()
  print("Error in debugger.")
  print(debug.traceback(err, 2))
  return os.exit(2)
end
local show_launch_screen
show_launch_screen = function(stdscr, width, height, launch_msg)
  do
    stdscr:wbkgd(Color("yellow on red bold"))
    stdscr:clear()
    stdscr:refresh()
    local lines = wrap_text("LUA DEBUGGER:\n \n " .. launch_msg .. "\n \npress any key...", math.floor(width - 2))
    local max_line = 0
    for _index_0 = 1, #lines do
      local line = lines[_index_0]
      max_line = math.max(max_line, #line)
    end
    for i, line in ipairs(lines) do
      if i == 1 or i == #lines then
        stdscr:mvaddstr(math.floor(height / 2 - #lines / 2) + i, math.floor((width - #line) / 2), line)
      else
        stdscr:mvaddstr(math.floor(height / 2 - #lines / 2) + i, math.floor((width - max_line) / 2), line)
      end
    end
    stdscr:refresh()
    C.doupdate()
    stdscr:getch()
    launched = true
  end
end
ldb = {
  run_debugger = function(err_msg)
    local select_pad
    err_msg = err_msg or ''
    if type(err_msg) ~= 'string' then
      err_msg = tostring(err_msg)
    end
    local stdscr = C.initscr()
    local SCREEN_H, SCREEN_W = stdscr:getmaxyx()
    C.cbreak()
    C.echo(false)
    C.nl(false)
    C.curs_set(0)
    C.start_color()
    C.use_default_colors()
    do
      TYPE_COLORS.string = Color('blue on black')
      TYPE_COLORS.number = Color('magenta')
      TYPE_COLORS.boolean = Color('cyan')
      TYPE_COLORS["nil"] = Color('cyan')
      TYPE_COLORS.table = Color('yellow')
      TYPE_COLORS["function"] = Color('green')
      TYPE_COLORS.userdata = Color('cyan bold')
      TYPE_COLORS.thread = Color('blue')
    end
    if launched == false then
      show_launch_screen(stdscr, SCREEN_W, SCREEN_H, err_msg)
    end
    stdscr:keypad()
    stdscr:wbkgd(Color())
    stdscr:clear()
    stdscr:refresh()
    local pads = { }
    do
      local err_msg_lines = wrap_text(err_msg, SCREEN_W - 4)
      for i, line in ipairs(err_msg_lines) do
        err_msg_lines[i] = (" "):rep(2) .. line
      end
      local height = math.min(#err_msg_lines + 2, 7)
      pads.err = Pad("(E)rror Message", 0, 0, height, SCREEN_W, err_msg_lines, function(self, i)
        return Color("red bold")
      end)
    end
    local err_lines = { }
    local stack_sources = { }
    local stack_locations = { }
    local watch_exprs = setmetatable({ }, {
      __index = function(self, k)
        local t = { }
        self[k] = t
        return t
      end
    })
    do
      local stack_names = { }
      local max_filename, max_fn_name = 0, 0
      local stack_min, stack_max = callstack_range()
      for i = stack_min, stack_max do
        local info = debug.getinfo(i)
        if not info then
          break
        end
        local fn_name = info.name
        if not (fn_name) then
          if info.istailcall then
            fn_name = "<tail call>"
          else
            fn_name = "<anonymous>"
          end
        end
        table.insert(stack_names, fn_name)
        local line
        if info.short_src then
          local line_table = line_tables[info.short_src]
          if line_table then
            local char = line_table[info.currentline]
            local line_num = 1
            local file = file_cache[info.short_src] or info.source
            for _ in file:sub(1, char):gmatch("\n") do
              line_num = line_num + 1
            end
            line = tostring(info.short_src) .. ":" .. tostring(line_num)
          else
            line = info.short_src .. ":" .. info.currentline
          end
        else
          line = "???"
        end
        err_lines[line] = true
        table.insert(stack_locations, line)
        table.insert(stack_sources, info.source)
        max_filename = math.max(max_filename, #line)
        max_fn_name = math.max(max_fn_name, #fn_name)
      end
      max_fn_name, max_filename = 0, 0
      for i = 1, #stack_names do
        max_fn_name = math.max(max_fn_name, #stack_names[i])
        max_filename = math.max(max_filename, #stack_locations[i])
      end
      local stack_h = math.floor(SCREEN_H * .6)
      local stack_w = math.min(max_fn_name + 3 + max_filename, math.floor(1 / 3 * SCREEN_W))
      pads.stack = Pad("(C)allstack", pads.err.height, SCREEN_W - stack_w, stack_h, stack_w, stack_names, (function(self, i)
        return (i == self.selected) and Color("black on green") or Color("green bold")
      end), stack_locations, (function(self, i)
        return (i == self.selected) and Color("black on cyan") or Color("cyan bold")
      end))
    end
    local show_src
    show_src = function(filename, line_no, file_contents)
      if file_contents == nil then
        file_contents = nil
      end
      if pads.src then
        if pads.src.filename == filename then
          pads.src:select(line_no)
          pads.src.colors[2] = function(self, i)
            if i == line_no and i == self.selected then
              return Color("yellow on red bold")
            elseif i == line_no then
              return Color("yellow on red")
            elseif err_lines[tostring(filename) .. ":" .. tostring(i)] == true then
              return Color("red on black bold")
            elseif i == self.selected then
              return Color("reverse")
            else
              return Color()
            end
          end
          for line, _ in pairs(err_lines) do
            local _filename, i = line:match("([^:]*):(%d*).*")
            if _filename == filename and tonumber(i) then
              pads.src:setup_chstr(tonumber(i))
            end
          end
          pads.src:select(line_no)
          return 
        else
          pads.src:erase()
        end
      end
      file_contents = file_contents or file_cache[filename]
      if file_contents then
        local src_lines = line_matcher:match(file_contents)
        pads.src = NumberedPad("(S)ource Code", pads.err.height, 0, pads.stack.height, pads.stack.x, src_lines, function(self, i)
          if i == line_no and i == self.selected then
            return Color("yellow on red bold")
          elseif i == line_no then
            return Color("yellow on red")
          elseif err_lines[tostring(filename) .. ":" .. tostring(i)] == true then
            return Color("red on black bold")
          elseif i == self.selected then
            return Color("reverse")
          else
            return Color()
          end
        end)
        pads.src:select(line_no)
      else
        local lines = { }
        for i = 1, math.floor(pads.stack.height / 2) - 1 do
          table.insert(lines, "")
        end
        local s = "<no source code found>"
        s = (" "):rep(math.floor((pads.stack.x - 2 - #s) / 2)) .. s
        table.insert(lines, s)
        pads.src = Pad("(S)ource Code", pads.err.height, 0, pads.stack.height, pads.stack.x, lines, function()
          return Color("red")
        end)
      end
      pads.src.filename = filename
    end
    local stack_env
    local show_vars
    show_vars = function(stack_index)
      if pads.vars then
        pads.vars:erase()
      end
      if pads.data then
        pads.data:erase()
      end
      local callstack_min, _ = callstack_range()
      local var_names, values = { }, { }
      stack_env = setmetatable({ }, {
        __index = _G
      })
      for loc = 1, 999 do
        local name, value = debug.getlocal(callstack_min + stack_index - 1, loc)
        if name == nil then
          break
        end
        table.insert(var_names, tostring(name))
        table.insert(values, value)
        stack_env[name] = value
      end
      local num_locals = #var_names
      local info = debug.getinfo(callstack_min + stack_index - 1, "uf")
      for upval = 1, info.nups do
        local _continue_0 = false
        repeat
          local name, value = debug.getupvalue(info.func, upval)
          if name == "_ENV" then
            _continue_0 = true
            break
          end
          table.insert(var_names, tostring(name))
          table.insert(values, value)
          stack_env[name] = value
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      local _list_0 = watch_exprs[stack_index]
      for _index_0 = 1, #_list_0 do
        local _continue_0 = false
        repeat
          local watch = _list_0[_index_0]
          if stack_env[watch.expr] ~= nil then
            _continue_0 = true
            break
          end
          table.insert(var_names, watch.expr)
          table.insert(values, watch.value)
          stack_env[watch.expr] = watch.value
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      local var_y = pads.stack.y + pads.stack.height
      local var_x = 0
      local height = SCREEN_H - (pads.err.height + pads.stack.height)
      pads.vars = Pad("(V)ars", var_y, var_x, height, AUTO, var_names, function(self, i)
        local color
        if i <= num_locals then
          color = Color()
        elseif i <= num_locals + info.nups - 1 then
          color = Color("blue")
        else
          color = Color("green")
        end
        if i == self.selected then
          color = color + C.A_REVERSE
        end
        return color
      end)
      pads.vars.keypress = function(self, key)
        if key == ('l'):byte() or key == C.KEY_RIGHT then
          return select_pad(pads.data)
        else
          return Pad.keypress(self, key)
        end
      end
      pads.vars.on_select = function(self, var_index)
        if var_index == nil then
          return 
        end
        local value_x = pads.vars.x + pads.vars.width
        local value_w = SCREEN_W - (value_x)
        local value = stack_env[var_names[var_index]]
        local type_str = tostring(type(value))
        pads.data = DataViewer(value, "(D)ata [" .. tostring(type_str) .. "]", var_y, value_x, pads.vars.height, value_w)
        pads.data.keypress = function(self, key)
          if (key == ('h'):byte() or key == C.KEY_LEFT) and self.selected == 1 then
            return select_pad(pads.vars)
          else
            return DataViewer.keypress(self, key)
          end
        end
        collectgarbage()
        return collectgarbage()
      end
      return pads.vars:select(1)
    end
    pads.stack.on_select = function(self, stack_index)
      local filename, line_no = pads.stack.columns[2][stack_index]:match("^(.*):(%d*)$")
      line_no = tonumber(line_no)
      show_src(filename, line_no, filename and file_cache[filename] or stack_sources[stack_index])
      return show_vars(stack_index)
    end
    pads.stack:select(1)
    local selected_pad = nil
    select_pad = function(pad)
      if selected_pad ~= pad then
        if selected_pad then
          selected_pad:set_active(false)
          selected_pad:refresh()
        end
        selected_pad = pad
        if selected_pad then
          selected_pad:set_active(true)
          return selected_pad:refresh()
        end
      end
    end
    select_pad(pads.stack)
    while true do
      for _, p in pairs(pads) do
        p:refresh()
      end
      local s = " press 'q' to quit "
      stdscr:mvaddstr(math.floor(SCREEN_H - 1), math.floor((SCREEN_W - #s)), s)
      local c = stdscr:getch()
      local _exp_0 = c
      if (':'):byte() == _exp_0 or ('>'):byte() == _exp_0 or ('?'):byte() == _exp_0 then
        C.echo(true)
        local print_nil = false
        local user_input
        local code = ''
        if c == ('?'):byte() then
          stdscr:mvaddstr(SCREEN_H - 1, 0, "? " .. (' '):rep(SCREEN_W - 1))
          stdscr:move(SCREEN_H - 1, 2)
          user_input = stdscr:getstr()
          code = 'return ' .. user_input
          print_nil = true
        elseif c == (':'):byte() or c == ('>'):byte() then
          local numlines = 1
          stdscr:mvaddstr(SCREEN_H - 1, 0, "> " .. (' '):rep(SCREEN_W - 1))
          stdscr:move(SCREEN_H - 1, 2)
          while true do
            local line = stdscr:getstr()
            if line == '' then
              break
            end
            code = code .. (line .. '\n')
            numlines = numlines + 1
            stdscr:mvaddstr(SCREEN_H - numlines, 0, "> " .. ((' '):rep(SCREEN_W) .. '\n'):rep(numlines))
            stdscr:mvaddstr(SCREEN_H - numlines, 2, code)
            stdscr:mvaddstr(SCREEN_H - 1, 0, (' '):rep(SCREEN_W))
            stdscr:move(SCREEN_H - 1, 0)
          end
        end
        C.echo(false)
        local output = ""
        if not stack_env then
          stack_env = setmetatable({ }, {
            __index = _G
          })
        end
        stack_env.print = function(...)
          for i = 1, select('#', ...) do
            if i > 1 then
              output = output .. '\t'
            end
            output = output .. tostring(select(i, ...))
          end
          output = output .. "\n"
        end
        for _, p in pairs(pads) do
          p:refresh(true)
        end
        local run_fn
        run_fn, err_msg = load(code, 'user input', 't', stack_env)
        if not run_fn then
          stdscr:attrset(Color('red bold'))
          stdscr:addstr(err_msg)
          stdscr:attrset(Color())
        else
          local ret
          ok, ret = pcall(run_fn)
          if not ok then
            stdscr:attrset(Color('red bold'))
            stdscr:addstr(ret)
            stdscr:attrset(Color())
          elseif ret ~= nil or print_nil then
            local value_bits = {
              '= ',
              Color('yellow'),
              unpack(colored_repr(ret, SCREEN_W - 2, 4))
            }
            local numlines = 1
            for i = 1, #value_bits - 1, 2 do
              for nl in value_bits[i]:gmatch('\n') do
                numlines = numlines + 1
              end
            end
            for nl in output:gmatch('\n') do
              numlines = numlines + 1
            end
            local y, x = SCREEN_H - numlines, 0
            if output ~= "" then
              stdscr:mvaddstr(SCREEN_H - numlines, 0, output)
              for nl in output:gmatch('\n') do
                y = y + 1
              end
            end
            for i = 1, #value_bits - 1, 2 do
              stdscr:attrset(value_bits[i + 1])
              local first_line = value_bits[i]:match('^[^\n]*')
              stdscr:mvaddstr(y, x, first_line)
              x = x + #first_line
              for line in value_bits[i]:gmatch('\n([^\n]*)') do
                stdscr:mvaddstr(y, x, (' '):rep(SCREEN_W - x))
                y = y + 1
                x = 0
                stdscr:mvaddstr(y, x, line)
              end
            end
            stdscr:attrset(Color())
            stdscr:mvaddstr(y, x, (' '):rep(SCREEN_W - x))
            if c == ("?"):byte() and ret ~= nil then
              local replacing = false
              local watch_index = nil
              local watches = watch_exprs[pads.stack.selected]
              for i, w in ipairs(watches) do
                if w.expr == user_input then
                  w.value = ret
                  watch_index = i
                  break
                end
              end
              if not (watch_index) then
                table.insert(watches, {
                  expr = user_input,
                  value = ret
                })
                watch_index = #watches
              end
              show_vars(pads.stack.selected)
              for i, s in ipairs(pads.vars.columns[1]) do
                if s == user_input then
                  pads.vars:select(i)
                  break
                end
              end
              select_pad(pads.data)
            end
          else
            local numlines = 0
            for nl in output:gmatch('\n') do
              numlines = numlines + 1
            end
            stdscr:mvaddstr(SCREEN_H - numlines, 0, output)
          end
        end
      elseif ('o'):byte() == _exp_0 then
        local file = stack_locations[pads.stack.selected]
        local filename, line_no = file:match("([^:]*):(.*)")
        line_no = tostring(pads.src.selected)
        C.endwin()
        os.execute((os.getenv("EDITOR") or "nano") .. " +" .. line_no .. " " .. filename)
        stdscr = C.initscr()
        C.cbreak()
        C.echo(false)
        C.nl(false)
        C.curs_set(0)
        C.start_color()
        C.use_default_colors()
        stdscr:clear()
        stdscr:refresh()
        for _, pad in pairs(pads) do
          pad:refresh(true)
        end
      elseif C.KEY_RESIZE == _exp_0 then
        SCREEN_H, SCREEN_W = stdscr:getmaxyx()
        stdscr:clear()
        stdscr:refresh()
        for _, pad in pairs(pads) do
          pad:refresh(true)
        end
        C.doupdate()
      elseif ('q'):byte() == _exp_0 or ("Q"):byte() == _exp_0 then
        pads = { }
        C.endwin()
        return 
      elseif ('c'):byte() == _exp_0 then
        select_pad(pads.stack)
      elseif ('s'):byte() == _exp_0 then
        select_pad(pads.src)
      elseif ('v'):byte() == _exp_0 then
        select_pad(pads.vars)
      elseif ('d'):byte() == _exp_0 then
        select_pad(pads.data)
      elseif ('e'):byte() == _exp_0 then
        select_pad(pads.err)
      elseif C.KEY_DC == _exp_0 or C.KEY_DL == _exp_0 or C.KEY_BACKSPACE == _exp_0 then
        if selected_pad == pads.vars then
          local watches = watch_exprs[pads.stack.selected]
          local expr = pads.vars.columns[1][pads.vars.selected]
          for i, w in ipairs(watches) do
            if w.expr == expr then
              table.remove(watches, i)
              show_vars(pads.stack.selected)
              select_pad(pads.vars)
              break
            end
          end
        end
      else
        if selected_pad then
          selected_pad:keypress(c)
        end
      end
    end
    return C.endwin()
  end,
  guard = function(fn, ...)
    local handler
    handler = function(err_msg)
      print(debug.traceback(err_msg, 2))
      return xpcall(ldb.run_debugger, err_hand, err_msg)
    end
    return xpcall(fn, handler, ...)
  end,
  breakpoint = function()
    return xpcall(ldb.run_debugger, err_hand, "Breakpoint triggered!")
  end,
  hijack = function()
    error = function(err_msg)
      print(debug.traceback(err_msg, 2))
      xpcall(ldb.run_debugger, err_hand, err_msg)
      return os.exit(2)
    end
    assert = function(condition, err_msg)
      if not condition then
        err_msg = err_msg or 'Assertion failed!'
        print(debug.traceback(err_msg, 2))
        xpcall(ldb.run_debugger, err_hand, err_msg)
        os.exit(2)
      end
      return condition
    end
  end
}
return ldb
