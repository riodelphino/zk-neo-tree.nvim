
local defaults = {
	follow_current_file = {
		enabled = true,
	},
	-- before_render = false, -- function(state) end,
	enable_git_status = true,
	bind_to_cwd = true,
	use_libuv_file_watcher = true,
	-- filtered_items = {
	-- 	visible = false, -- when true, they will just be displayed differently than normal items
	-- 	hide_dotfiles = true,
	-- 	hide_gitignored = true,
	-- 	hide_hidden = true, -- only works on Windows for hidden files/directories
	-- 	hide_by_name = {
	-- 		--"node_modules"
	-- 	},
	-- 	hide_by_pattern = { -- uses glob style patterns
	-- 		--"*.meta",
	-- 		--"*/src/*/tsconfig.json",
	-- 	},
	-- 	always_show = { -- remains visible even if other settings would normally hide it
	-- 		--".gitignored",
	-- 	},
	-- 	always_show_by_pattern = { -- uses glob style patterns
	-- 		--".env*",
	-- 	},
	-- 	never_show = { -- remains hidden even if visible is toggled to true, this overrides always_show
	-- 		--".DS_Store",
	-- 		--"thumbs.db"
	-- 	},
	-- 	never_show_by_pattern = { -- uses glob style patterns
	-- 		--".null-ls_*",
	-- 	},
	-- },
	filtered_items = {
		always_show = {},
		always_show_by_pattern = {},
		hide_by_name = {},
		hide_by_pattern = {},
		hide_dotfiles = true,
		hide_gitignored = true,
		hide_hidden = true,
		never_show = {},
		never_show_by_pattern = {},
		visible = false,
	},
	window = {
		mappings = {
			["n"] = "change_query",
			-- Additional keys from filesystem source
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
