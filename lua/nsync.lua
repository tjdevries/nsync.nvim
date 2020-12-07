
local a = vim.api
_G.a = vim.api
local function try_require(name)
  local status, mod = pcall(require, name)
  if status then return mod end
end
local luadev = try_require'luadev'

local nsync = _G._nsync or {}
_G._nsync = nsync

nsync.ns = a.nvim_create_namespace'nsync'

function nsync.start(bufnr)
  if bufnr == nil or bufnr == 0 then
    bufnr = a.nvim_get_current_buf()
  end
  nsync.bufnr = bufnr
  nsync.sched = false
  nsync.reset()
  a.nvim_buf_attach(bufnr, false, {on_bytes=function(...)
    nsync.on_bytes(...)
  end})
end

function nsync.reset()
  local text = a.nvim_buf_get_lines(nsync.bufnr, 0, -1, true)
  local bytes = table.concat(text, '\n') .. '\n'
  nsync.shadow = bytes
  nsync.dirty = false
  a.nvim_buf_clear_namespace(nsync.bufnr, nsync.ns, 0, -1)
end

function nsync.on_bytes(_, buf, tick, start_row, start_col, start_byte, old_row, old_col, old_byte, new_row, new_col, new_byte)
  local before = string.sub(nsync.shadow, 1, start_byte)
  -- assume no text will contain 0xff bytes (invalid UTF-8)
  -- so we can use it as marker for unknown bytes
  local unknown = string.rep('\255', new_byte)
  local after = string.sub(nsync.shadow, start_byte + old_byte + 1)
  nsync.shadow = before .. unknown .. after
  if not nsync.sched then
    vim.schedule(nsync.show)
    nsync.sched = true
  end

  if luadev then
    vim.schedule(function()
      luadev.print(vim.inspect{start_row, start_col, start_byte, old_row, old_col, old_byte, new_row, new_col, new_byte})
    end)
  end
end

function nsync.sync()
  local text = a.nvim_buf_get_lines(nsync.bufnr, 0, -1, true)
  local bytes = table.concat(text, '\n') .. '\n'
  for i = 1, string.len(nsync.shadow) do
    local shadowbyte = string.sub(nsync.shadow, i, i)
    if shadowbyte ~= '\255' then
      if string.sub(bytes, i, i) ~= shadowbyte then
        error(i)
      end
    end
  end
end

function nsync.show()
  nsync.sched = false
  a.nvim_buf_clear_namespace(nsync.bufnr, nsync.ns, 0, -1)
  local text = a.nvim_buf_get_lines(nsync.bufnr, 0, -1, true)
  local bytes = table.concat(text, '\n') .. '\n'
  local line, lastpos = 0, 0
  for i = 1, string.len(nsync.shadow) do
    local textbyte = string.sub(bytes, i, i)
    if textbyte == '\n' then
      line = line + 1
      lastpos = i
    end
    local shadowbyte = string.sub(nsync.shadow, i, i)
    pcall(function()
      if shadowbyte ~= '\255' then
        if textbyte ~= shadowbyte then
            a.nvim_buf_set_virtual_text(nsync.bufnr, nsync.ns, line, {{"ERR", "ErrorMsg"}}, {})
            a.nvim_buf_add_highlight(nsync.bufnr, nsync.ns, "ErrorMsg", line, i-lastpos-1, i-lastpos)
        end
      else
        if i - lastpos == 0 then
          a.nvim_buf_set_virtual_text(nsync.bufnr, nsync.ns, line-1, {{" ", "RedrawDebugComposed"}}, {})
        else
          a.nvim_buf_add_highlight(nsync.bufnr, nsync.ns, "StatusLine", line, i-lastpos-1, i-lastpos)
        end
      end
    end)
  end
end

nsync.reset()

return nsync
