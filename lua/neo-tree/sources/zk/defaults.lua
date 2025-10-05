
local defaults = {
	follow_current_file = {
		enabled = true,
	},
	before_render = false,
	bind_to_cwd = true,
	enable_git_status = true,
	enable_diagnostics = true,
	enable_opened_markers = true,
	enable_modified_markers = true,
	git_status_async = true,
	use_libuv_file_watcher = true,
	filtered_items = {
		always_show = {}, -- NOT WORKS
		always_show_by_pattern = {}, -- NOT WORKS
		hide_dotfiles = true, -- NOT WORKS
		hide_gitignored = true, -- NOT WORKS
		hide_hidden = true, -- NOT WORKS
		hide_by_name = {},
		hide_by_pattern = {},
		never_show = {},
		never_show_by_pattern = {},
		visible = false, -- NOT WORKS
	},
	window = {
		mappings = {
			["n"] = "change_query",
		},
	},
   custom = {
    name_formatter = function(note)
    end,
    sorter = function(state, a, b)
    end,
    select = { "absPath", "title"},
   },
}

return defaults
