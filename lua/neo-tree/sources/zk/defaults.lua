
local defaults = {
	follow_current_file = {
		enabled = true,
	},
	before_render = false,
	enable_git_status = true,
	bind_to_cwd = true,
	use_libuv_file_watcher = true,
	filtered_items = {
		always_show = {},
		always_show_by_pattern = {},
		hide_dotfiles = true,
		hide_gitignored = true,
		hide_hidden = true,
		hide_by_name = {},
		hide_by_pattern = {},
		never_show = {},
		never_show_by_pattern = {},
		visible = false,
	},
	window = {
		mappings = {
         -- zk source
			["n"] = "change_query",
			-- filesystem source
			["H"] = "toggle_hidden",
			["<bs>"] = "navigate_up",
			["."] = "set_root",
			["f"] = "filter_on_submit",
			["<c-x>"] = "clear_filter",
			["[g"] = "prev_git_modified",
			["]g"] = "next_git_modified",
		},
	},
}

return defaults
