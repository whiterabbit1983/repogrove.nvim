local M = {}
local api = vim.api

function M.open(repo)
  local function git(args, done)
    local cmd = vim.list_extend({'git', '--no-pager', '--literal-pathspecs', '-C', repo}, args)
    vim.system(cmd, {}, vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        vim.notify('RepoGrove: '..vim.trim(res.stderr), vim.log.levels.WARN)
        return
      end
      done(res.stdout)
    end))
  end

  local function files(commit)
    -- Compare against the first parent, or the empty tree for an initial commit.
    local function compare(options, path, done)
      local args = {'diff-tree', '--no-commit-id', '-r', '--no-renames', '--no-ext-diff', '--no-textconv', '--no-color'}
      vim.list_extend(args, options)
      if commit.parent then table.insert(args, commit.parent) else table.insert(args, '--root') end
      table.insert(args, commit.id)
      table.insert(args, '--')
      if path then table.insert(args, path) end
      git(args, done)
    end
    compare({'--name-status', '-z'}, nil, function(out)
      local items = {}
      for status, path in out:gmatch('([^%z]+)%z([^%z]+)%z') do
        items[#items+1] = {status=status, path=path}
      end
      if #items == 0 then return vim.notify('RepoGrove: no file changes in this commit') end
      vim.ui.select(items, {
        prompt='Files @ '..commit.id:sub(1, 10),
        format_item=function(item) return item.status..'  '..vim.fn.strtrans(item.path) end,
      }, function(item)
        if not item then return end
        compare({'-p'}, item.path, function(patch)
          vim.cmd('botright new')
          local b = api.nvim_get_current_buf()
          vim.bo[b].buftype='nofile'; vim.bo[b].bufhidden='wipe'; vim.bo[b].swapfile=false
          api.nvim_buf_set_lines(b, 0, -1, false, vim.split(patch:gsub('\n$', ''), '\n', {plain=true}))
          vim.bo[b].filetype='diff'; vim.bo[b].modifiable=false
          vim.keymap.set('n', 'q', function() vim.cmd('close') end, {buffer=b, silent=true})
        end)
      end)
    end)
  end

  local function page(skip, tip)
    git({'log', '-z', '--no-color', '--no-show-signature', '--format=%H%x00%P%x00%s', '--max-count=51', '--skip='..skip, tip or 'HEAD', '--'}, function(out)
      local items = {}
      for id, parents, subject in out:gmatch('(%x+)%z([^%z]*)%z([^%z]*)%z') do
        items[#items+1] = {id=id, parent=parents:match('^%x+'), label=id:sub(1,10)..'  '..vim.fn.strtrans(subject)}
      end
      if #items==0 then return vim.notify('RepoGrove: no commits') end
      tip = tip or items[1].id
      if #items==51 then items[51]={label='Older commits…'} end
      vim.ui.select(items, {prompt='Select commit', format_item=function(item) return item.label end}, function(item)
        if not item then return end
        if item.id then files(item) else page(skip+50, tip) end
      end)
    end)
  end
  page(0)
end
return M
