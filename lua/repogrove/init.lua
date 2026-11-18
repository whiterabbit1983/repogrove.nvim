local M = {}
local a, uv = vim.api, vim.uv
local ns = a.nvim_create_namespace('RepoGrove')
local colors = { Repo = '#81d4ac', Ignored = '#8993a4', Staged = '#91cd77', Dirty = '#ffb86c', Dir = '#82b8ff', Hint = '#abb5cd' }
local function highlights()
  for k,v in pairs(colors) do a.nvim_set_hl(0,'RepoGrove'..k,{fg=v,bold=k=='Repo',default=true}) end
end
highlights()
a.nvim_create_autocmd('ColorScheme',{callback=highlights})

-- NUL records preserve spaces, tabs, newlines, and the second path of renames.
local function parse(out)
  local r = { paths={}, staged=0, dirty=0 }
  local skip, oid
  for line in out:gmatch('([^%z]+)%z') do
    local t=line:sub(1,1)
    if skip then skip=false
    elseif t=='#' then
      r.branch=line:match('^# branch%.head (.*)') or r.branch
      local ahead,behind=line:match('^# branch%.ab %+(%d+) %-(%d+)$')
      if ahead then r.sync=' ↑'..ahead..' ↓'..behind end
      if line:match('^# branch%.upstream ') then r.upstream=true end
      oid=line:match('^# branch%.oid (.*)') or oid
    else
      local n=({['1']=8,['2']=9,u=10,['?']=1,['!']=1})[t]
      if n then
        local pos=1
        for _=1,n do pos=line:find(' ',pos,true)+1 end
        local path=line:sub(pos):gsub('/$','')
        local xy=line:sub(3,4)
        local s=(t=='1' or t=='2') and xy:sub(1,1)~='.'
        local d=t=='?' or t=='u' or (t~='!' and xy:sub(2,2)~='.')
        if s then r.staged=r.staged+1 end
        if d then r.dirty=r.dirty+1 end
        r.paths[path]=t=='!' and '!!' or t=='?' and '??' or xy
        skip=t=='2'
      end
    end
  end
  if r.branch=='(detached)' then r.branch='@'..(oid or '?'):sub(1,8) end
  return r
end
function M.open(path)
  local root=uv.fs_realpath(path)
  if not root or uv.fs_stat(root).type~='directory' then return vim.notify('Not a directory: '..path,vim.log.levels.ERROR) end
  local top=vim.system({'git','-C',root,'rev-parse','--show-toplevel'}):wait()
  local outer=top.code==0 and top.stdout:gsub('\n$','') or nil
  vim.cmd('tabnew')
  local b=a.nvim_get_current_buf()
  vim.bo[b].buftype='nofile'; vim.bo[b].bufhidden='wipe'; vim.bo[b].swapfile=false
  vim.bo[b].filetype='repogrove'; vim.wo.wrap=false; vim.wo.number=false; vim.wo.relativenumber=false
  a.nvim_buf_set_name(b,'RepoGrove://'..b..'/'..root)
  local expanded,cache,rows={[root]=true},{},{}
  local render
  local function status(repo)
    if not cache[repo] then
      local entry={}; cache[repo]=entry
      vim.system({'git','--no-optional-locks','-C',repo,'status','--porcelain=v2','--branch','--ahead-behind','-z','--ignored=matching','--untracked-files=all'}, {}, vim.schedule_wrap(function(res)
        if cache[repo]~=entry or not a.nvim_buf_is_valid(b) then return end
        cache[repo]=res.code==0 and parse(res.stdout) or {error=vim.trim(res.stderr)}; render()
      end))
    end
    return cache[repo]
  end
  render=function()
    local lines,hl,nextrows={},{},{}
    local function add(str,group,row)
      lines[#lines+1]=str; nextrows[#lines]=row
      if group then hl[#hl+1]={#lines-1,'RepoGrove'..group} end
    end
    add(' RepoGrove   Enter open   r refresh   g git menu   q close','Hint')
    local function visit(p,name,dir,prefix,edge,childprefix,repo,ignored)
      local isrepo=dir and (p==outer or uv.fs_stat(vim.fs.joinpath(p,'.git'))~=nil)
      if isrepo then repo=p; ignored=false end
      local st=repo and status(repo)
      local key=repo and p:sub(#repo+(repo:sub(-1)=='/' and 1 or 2))
      local mark=st and st.paths and st.paths[key]
      -- When opened below an ignored directory, its record may be an ancestor.
      if st and st.paths and p==root and key then
        local ancestor=key
        while ancestor and ancestor~='' do
          if st.paths[ancestor]=='!!' then ignored=true; break end
          ancestor=ancestor:match('^(.*)/[^/]+$')
        end
      end
      ignored=ignored or mark=='!!'
      local suffix=isrepo and (st.error and '   [git error]' or not st.paths and '   […]' or ('   [%s%s | staged %d | unstaged %d]'):format(vim.fn.strtrans(st.branch or '?'),st.sync or (st.upstream and ' ↑? ↓?' or ''),st.staged,st.dirty)) or (ignored and '   !!' or mark and '   '..mark or '')
      local grp=isrepo and 'Repo' or ignored and 'Ignored' or mark and (mark:sub(2,2)=='.' and 'Staged' or 'Dirty') or dir and 'Dir' or nil
      add(prefix..edge..(dir and (expanded[p] and '▾ ' or '▸ ') or '  ')..vim.fn.strtrans(name)..(dir and '/' or '')..suffix,grp,{p=p,dir=dir,repo=repo})
      if dir and expanded[p] then
        local it,err=uv.fs_scandir(p); local list={}
        if not it then add(childprefix..'  '..tostring(err),'Hint'); return end
        while true do local n,t=uv.fs_scandir_next(it); if not n then break end
          if n~='.git' then list[#list+1]={n,t=='directory'} end
        end
        table.sort(list,function(x,y) if x[2]~=y[2] then return x[2] end return x[1]<y[1] end)
        for i,e in ipairs(list) do local last=i==#list
          visit(vim.fs.joinpath(p,e[1]),e[1],e[2],childprefix,last and '└─ ' or '├─ ',childprefix..(last and '   ' or '│  '),repo,ignored)
        end
      end
    end
    visit(root,vim.fs.basename(root),true,'','','',outer,false)
    vim.bo[b].modifiable=true; a.nvim_buf_set_lines(b,0,-1,false,lines); rows=nextrows
    a.nvim_buf_clear_namespace(b,ns,0,-1)
    for _,h in ipairs(hl) do a.nvim_buf_add_highlight(b,ns,h[2],h[1],0,-1) end
    vim.bo[b].modifiable=false
  end
  local function map(key,fn) vim.keymap.set('n',key,fn,{buffer=b,silent=true}) end
  local function selected() return rows[a.nvim_win_get_cursor(0)[1]] end
  local function refresh() cache={}; render() end
  map('<CR>',function() local n=selected(); if not n then return end
    if n.dir then expanded[n.p]=not expanded[n.p]; render() else vim.cmd('split '..vim.fn.fnameescape(n.p)) end
  end)
  map('r',refresh); map('q',function() a.nvim_buf_delete(b,{force=true}) end)
  map('g',function()
    local n=selected(); if not n then return end
    local dir=n.dir and n.p or vim.fs.dirname(n.p)
    local choices=n.repo and {'shell','status','log','add -p','commit','fetch','pull','push'} or {'shell'}
    vim.ui.select(choices,{prompt='Actions @ '..dir},function(choice)
      if not choice then return end
      local cmd=choice=='shell' and {vim.o.shell} or vim.list_extend({'git'},vim.split(choice,' '))
      vim.cmd('botright new'); vim.bo.bufhidden='wipe'
      vim.fn.termopen(cmd,{cwd=choice=='shell' and dir or n.repo,on_exit=vim.schedule_wrap(function() if a.nvim_buf_is_valid(b) then refresh() end end)})
      vim.cmd('startinsert')
    end)
  end)
  a.nvim_create_autocmd('BufEnter',{buffer=b,callback=refresh}); render(); a.nvim_win_set_cursor(0,{2,0})
end
return M
