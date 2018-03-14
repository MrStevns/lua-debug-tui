local C = require("curses")
local repr = require('repr')
local COLORS = { }
local run_debugger, guard, stdscr
local AUTO = -1
local log = io.open("output.log", "w")
local callstack_range
callstack_range = function()
  local min, max = 0, -1
  for i = 1, 999 do
    local info = debug.getinfo(i, 'f')
    if not info then
      min = i - 1
      break
    end
    if info.func == run_debugger then
      min = i + 1
      break
    end
  end
  for i = min, 999 do
    local info = debug.getinfo(i, 'f')
    if not info or info.func == guard then
      max = i - 3
      break
    end
  end
  return min, max
end
local wrap_text
wrap_text = function(text, width)
  local lines = { }
  for line in text:gmatch("[^\n]*") do
    while #line > width do
      table.insert(lines, line:sub(1, width))
      line = line:sub(width + 1, -1)
    end
    if #line > 0 then
      table.insert(lines, line)
    end
  end
  return lines
end
local default_colors = { }
local Pad
do
  local _class_0
  local _base_0 = {
    set_active = function(self, active)
      if active == self.active then
        return 
      end
      self.active = active
      return self._pad:attrset(active and self.colors.active_frame or self.colors.inactive_frame)
    end,
    select = function(self, i)
      if i == self.selected or #self.lines == 0 then
        return self.selected
      end
      if i ~= nil then
        i = math.max(1, math.min(#self.lines, i))
      end
      if self.selected then
        local j = self.selected
        local attr = (j % 2 == 0) and self.colors.even_row or self.colors.odd_row
        self.chstrs[j]:set_str(0, self.lines[j], attr)
        self.chstrs[j]:set_str(#self.lines[j], ' ', attr, self.chstrs[j]:len() - #self.lines[j])
        self._pad:mvaddchstr(j - 1 + 1, 0 + 1, self.chstrs[j])
      end
      if i then
        local attr = self.active and self.colors.active or self.colors.highlight
        self.chstrs[i]:set_str(0, self.lines[i], attr)
        self.chstrs[i]:set_str(#self.lines[i], ' ', attr, self.chstrs[i]:len() - #self.lines[i])
        self._pad:mvaddchstr(i - 1 + 1, 0 + 1, self.chstrs[i])
      end
      self.selected = i
      if self.selected then
        if self.scroll_y + self.height - 1 < self.selected then
          self.scroll_y = math.min(self.selected - (self.height - 1), #self.lines - self.height)
        elseif self.scroll_y + 1 > self.selected then
          self.scroll_y = self.selected - 1
        end
      end
      self:refresh()
      if self.on_select then
        self:on_select(self.selected)
      end
      return self.selected
    end,
    scroll = function(self, delta)
      if self.selected == nil then
        return self:select(1)
      end
      return self:select(self.selected + delta)
    end,
    refresh = function(self)
      self._pad:border(C.ACS_VLINE, C.ACS_VLINE, C.ACS_HLINE, C.ACS_HLINE, C.ACS_ULCORNER, C.ACS_URCORNER, C.ACS_LLCORNER, C.ACS_LRCORNER)
      if self.label then
        self._pad:mvaddstr(0, math.floor((self.width - #self.label - 2) / 2), " " .. tostring(self.label) .. " ")
      end
      return self._pad:pnoutrefresh(self.scroll_y, self.scroll_x, self.y, self.x, self.y + self.height + 1, self.x + self.width)
    end,
    erase = function(self)
      self._pad:erase()
      return self._pad:pnoutrefresh(self.scroll_y, self.scroll_x, self.y, self.x, self.y + self.height, self.x + self.width)
    end,
    clear = function(self)
      self:erase()
      self.lines = { }
      self.chstrs = { }
      self:set_internal_size(2, 2)
      if self.resize_height then
        self:set_size(self._height, self.width)
      end
      if self.resize_width then
        self:set_size(self.height, self._width)
      end
      self.selected = nil
      self.scroll_y, self.scroll_x = 0, 0
      return self:refresh()
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, y, x, height, width, lines, label, colors)
      if colors == nil then
        colors = default_colors
      end
      self.y, self.x, self.height, self.width, self.lines, self.label, self.colors = y, x, height, width, lines, label, colors
      if self.colors and self.colors ~= default_colors then
        setmetatable(self.colors, {
          __index = default_colors
        })
      end
      self.scroll_y, self.scroll_x = 0, 0
      self.selected = nil
      if self.width == AUTO then
        self.width = 2
        local _list_0 = self.lines
        for _index_0 = 1, #_list_0 do
          local x = _list_0[_index_0]
          self.width = math.max(self.width, #x + 2)
        end
      end
      self._width = self.width
      if self.height == AUTO then
        self.height = #self.lines + 2
      end
      self._height = self.height
      self._pad = C.newpad(self._height, self._width)
      self._pad:scrollok(true)
      self:set_active(false)
      self.chstrs = { }
      for i, line in ipairs(self.lines) do
        local attr = (i % 2 == 0) and self.colors.even_row or self.colors.odd_row
        local chstr = C.new_chstr(self.width - 2)
        self.chstrs[i] = chstr
        if #line >= chstr:len() then
          line = line:sub(1, chstr:len())
        else
          line = line .. (" "):rep(chstr:len() - #line)
        end
        chstr:set_str(0, line, attr)
        self._pad:mvaddchstr(i - 1 + 1, 0 + 1, chstr)
      end
      return self:refresh()
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
    local contents = file:read("*a")
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
run_debugger = function(err_msg)
  stdscr = C.initscr()
  SCREEN_H, SCREEN_W = stdscr:getmaxyx()
  C.cbreak()
  C.echo(false)
  C.nl(false)
  C.curs_set(0)
  C.start_color()
  C.use_default_colors()
  local _
  _, COLORS.REGULAR = C.init_pair(1, C.COLOR_WHITE, -1), C.color_pair(1)
  _, COLORS.INVERTED = C.init_pair(2, C.COLOR_WHITE, C.COLOR_BLACK), C.color_pair(2)
  _, COLORS.YELLOW_BG = C.init_pair(3, C.COLOR_BLACK, C.COLOR_YELLOW), C.color_pair(3)
  _, COLORS.RED = C.init_pair(4, C.COLOR_RED, -1), C.color_pair(4)
  _, COLORS.BLUE = C.init_pair(5, C.COLOR_BLUE, -1), C.color_pair(5) | C.A_BOLD
  _, COLORS.WHITE = C.init_pair(6, C.COLOR_WHITE, -1), C.color_pair(6)
  _, COLORS.WHITE_BG = C.init_pair(7, C.COLOR_BLACK, C.COLOR_WHITE), C.color_pair(7)
  _, COLORS.BROWN = C.init_pair(8, C.COLOR_BLACK, -1), C.color_pair(8) | C.A_BOLD
  _, COLORS.RED_BG = C.init_pair(9, C.COLOR_YELLOW, C.COLOR_RED), C.color_pair(9) | C.A_BOLD | C.A_DIM
  _, COLORS.GREEN = C.init_pair(10, C.COLOR_GREEN, -1), C.color_pair(10)
  default_colors = {
    active_frame = COLORS.BLUE,
    inactive_frame = COLORS.BROWN,
    odd_row = COLORS.REGULAR,
    even_row = COLORS.INVERTED,
    highlight = COLORS.WHITE_BG,
    active = COLORS.YELLOW_BG
  }
  stdscr:clear()
  stdscr:refresh()
  local pads = { }
  do
    local err_msg_lines = wrap_text(err_msg, SCREEN_W - 4)
    for i, line in ipairs(err_msg_lines) do
      err_msg_lines[i] = (" "):rep(math.floor((SCREEN_W - 2 - #line) / 2)) .. line
    end
    pads.err = Pad(0, 0, AUTO, SCREEN_W, err_msg_lines, "Error Message", {
      even_row = COLORS.RED | C.A_BOLD,
      odd_row = COLORS.RED | C.A_BOLD,
      inactive_frame = COLORS.RED | C.A_DIM
    })
  end
  do
    local stack_names = { }
    local stack_locations = { }
    local max_filename = 0
    local stack_min, stack_max = callstack_range()
    for i = stack_min, stack_max do
      local _continue_0 = false
      repeat
        local info = debug.getinfo(i)
        if not info then
          break
        end
        table.insert(stack_names, info.name or "<unnamed function>")
        if not info.short_src then
          _continue_0 = true
          break
        end
        local line_table = line_tables[info.short_src]
        local line
        if line_table then
          local char = line_table[info.currentline]
          local line_num = 1
          local file = file_cache[info.short_src]
          for _ in file:sub(1, char):gmatch("\n") do
            line_num = line_num + 1
          end
          line = tostring(info.short_src) .. ":" .. tostring(line_num)
        else
          line = info.short_src .. ":" .. info.currentline
        end
        table.insert(stack_locations, line)
        max_filename = math.max(max_filename, #line)
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
    local callstack = { }
    for i = 1, #stack_names do
      callstack[i] = stack_locations[i] .. (" "):rep(max_filename - #stack_locations[i]) .. " | " .. stack_names[i] .. " "
    end
    pads.stack = Pad(pads.err.height, 0, math.max(#callstack + 2, 20), AUTO, callstack, "(C)allstack")
    pads.stack:set_active(true)
    pads.stack:refresh()
  end
  local show_src
  show_src = function(filename, line_no)
    local file = file_cache[filename]
    local src_lines = { }
    local selected = nil
    if file then
      local i = 0
      for line in file:gmatch("[^\n]*") do
        local _continue_0 = false
        repeat
          i = i + 1
          if i < line_no - (pads.stack.height - 2) / 2 then
            _continue_0 = true
            break
          end
          table.insert(src_lines, line)
          if i == line_no then
            selected = #src_lines
          end
          if #src_lines >= pads.stack.height - 2 then
            break
          end
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
    else
      table.insert(src_lines, "<no source code found>")
    end
    if pads.src then
      pads.src:erase()
    end
    pads.src = Pad(pads.err.height, pads.stack.x + pads.stack.width, pads.stack.height, SCREEN_W - pads.stack.x - pads.stack.width - 0, src_lines, "(S)ource Code", {
      highlight = COLORS.RED_BG,
      inactive_frame = COLORS.GREEN | C.A_BOLD
    })
    return pads.src:select(selected)
  end
  local show_vars
  show_vars = function(stack_index)
    if pads.vars then
      pads.vars:erase()
    end
    if pads.values then
      pads.values:erase()
    end
    local callstack_min
    callstack_min, _ = callstack_range()
    local var_names, values = { }, { }
    for loc = 1, 999 do
      local name, value = debug.getlocal(callstack_min + stack_index - 1, loc)
      if value == nil then
        break
      end
      table.insert(var_names, tostring(name))
      if type(value) == 'function' then
        local info = debug.getinfo(value, 'nS')
        table.insert(values, repr(info))
      else
        table.insert(values, repr(value))
      end
    end
    local var_y = pads.stack.y + pads.stack.height
    local var_x = 0
    pads.vars = Pad(var_y, var_x, math.min(2 + #var_names, SCREEN_H - pads.err.height - pads.stack.height), AUTO, var_names, "(V)ars")
    pads.vars.on_select = function(self, var_index)
      local value_x = pads.vars.x + pads.vars.width
      local value_w = SCREEN_W - (value_x)
      if var_index then
        pads.values = Pad(var_y, value_x, pads.vars.height, value_w, wrap_text(values[var_index], value_w - 2), "Values")
      else
        pads.values = Pad(var_y, value_x, pads.vars.height, value_w, values, "Values")
      end
    end
    return pads.vars:select(1)
  end
  pads.stack.on_select = function(self, stack_index)
    local filename, line_no = pads.stack.lines[stack_index]:match("([^:]*):(%d*).*")
    line_no = tonumber(line_no)
    show_src(filename, line_no)
    return show_vars(stack_index)
  end
  pads.stack:select(1)
  pads.stack:set_active(true)
  local selected_pad = pads.stack
  local select_pad
  select_pad = function(pad)
    if selected_pad ~= pad then
      selected_pad:set_active(false)
      selected_pad:refresh()
      selected_pad = pad
      selected_pad:set_active(true)
      return selected_pad:refresh()
    end
  end
  while true do
    C.doupdate()
    local c = stdscr:getch()
    local _exp_0 = c
    if C.KEY_DOWN == _exp_0 or C.KEY_SF == _exp_0 or ("j"):byte() == _exp_0 then
      selected_pad:scroll(1)
    elseif C.KEY_UP == _exp_0 or C.KEY_SR == _exp_0 or ("k"):byte() == _exp_0 then
      selected_pad:scroll(-1)
    elseif ('J'):byte() == _exp_0 then
      selected_pad:scroll(10)
    elseif ('K'):byte() == _exp_0 then
      selected_pad:scroll(-10)
    elseif ('c'):byte() == _exp_0 then
      select_pad(pads.stack)
    elseif ('s'):byte() == _exp_0 then
      select_pad(pads.src)
    elseif ('v'):byte() == _exp_0 then
      select_pad(pads.vars)
    elseif ('o'):byte() == _exp_0 then
      local file = stack_locations[pads.stack.selected]
      local filename, line_no = file:match("([^:]*):(.*)")
      os.execute((os.getenv("EDITOR") or "nano") .. " +" .. line_no .. " " .. filename)
    elseif ('q'):byte() == _exp_0 or ("Q"):byte() == _exp_0 then
      break
    end
  end
  return C.endwin()
end
guard = function(fn, ...)
  local err_hand
  err_hand = function(err)
    C.endwin()
    print("Caught an error:")
    print(debug.traceback(err, 2))
    return os.exit(2)
  end
  return xpcall(fn, (function(err_msg)
    return xpcall(run_debugger, err_hand, err_msg)
  end), ...)
end
local breakpoint
breakpoint = function()
  local err_hand
  err_hand = function(err)
    C.endwin()
    print("Caught an error:")
    print(debug.traceback(err, 2))
    return os.exit(2)
  end
  return xpcall(run_debugger, err_hand, "Breakpoint triggered!")
end
return {
  guard = guard,
  breakpoint = breakpoint
}
