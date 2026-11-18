if vim.g.loaded_repogrove then return end
vim.g.loaded_repogrove = true
vim.api.nvim_create_user_command('RepoGrove', function(o)
  require('repogrove').open(o.fargs[1] or vim.fn.getcwd())
end, { nargs = '?', complete = 'dir', desc = 'Browse a forest of Git repositories' })
