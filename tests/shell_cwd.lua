-- Run from the plugin directory: nvim --clean --headless --cmd 'set rtp^=.' -l tests/shell_cwd.lua
local a = vim.api
local root = vim.fn.tempname()
local repo = root .. '/repo'
local sub = repo .. '/sub dir'
local function test()
  vim.fn.mkdir(sub, 'p')
  assert(vim.system({'git','init','-q',repo}):wait().code == 0)
  vim.fn.writefile({}, sub .. '/file')
  vim.o.shell = '/bin/sh'
  require('repogrove').open(root)
  local tree = a.nvim_get_current_win()
  local original = vim.fn.getcwd()
  local function press(row,key)
    a.nvim_win_set_cursor(tree,{row,0})
    vim.fn.maparg(key,'n',false,true).callback()
  end
  press(3,'<CR>'); press(4,'<CR>')
  vim.ui.select = function(items,_,cb) assert(vim.tbl_contains(items,'shell')); cb('shell') end
  for _,row in ipairs({4,5}) do
    press(row,'g')
    assert(vim.fn.getcwd()==sub, 'wrong terminal window :pwd')
    local b = a.nvim_get_current_buf()
    a.nvim_chan_send(vim.b[b].terminal_job_id, "printf '%s\\n' \"$(pwd -P)\" > ../actual-cwd\n")
    assert(vim.wait(3000,function()
      return vim.fn.filereadable(repo..'/actual-cwd')==1 and vim.fn.readfile(repo..'/actual-cwd')[1]==sub
    end), 'wrong shell cwd')
    vim.fn.delete(repo..'/actual-cwd'); vim.cmd('close!')
    assert(a.nvim_get_current_win()==tree and vim.fn.getcwd()==original)
  end
end
local ok, err = xpcall(test,debug.traceback)
vim.fn.delete(root,'rf'); assert(ok,err)
