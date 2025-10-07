local config = {
	follow_current_file = {
		enabled = true,
	},
	before_render = false,
	bind_to_cwd = true,
	enable_git_status = true,
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
	extra = {
		scan_none_zk_items = true,

		-- The fields fetched by `zk.api.list`
		select = { "absPath", "title"},

		---Default name formatter
		---@param note table? single cached note by zk.api.list
		---@param node neotree.collections.ListNode
		name_formatter = function(note, node)
			return note and note.title or node.name or nil
		end,

		---Additional customizer for neotree.Render.Node table
		---@param rendere_nodes neotree.Render.Node[]
		---@param note table? single cached note by zk.api.list
		---@param node neotree.collections.ListNode
		name_extra_renderer = function(rendere_nodes, note, node)
			return rendere_nodes
		end,

		---Default sort function (directory > title > filename)
		---@param notes table cached notes by zk.api.list
		---@param a table
		---@param b table
		sorter = function(notes, a, b)
			local a_hidden = string.sub(a.name, 1, 1) == "."
			local b_hidden = string.sub(b.name, 1, 1) == "."

			-- 1. Directories come first
			if a.type == "directory" and b.type ~= "directory" then
				return true
			elseif a.type ~= "directory" and b.type == "directory" then
				return false
			elseif a.type == "directory" and b.type == "directory" then
				if not a_hidden and b_hidden then -- Sort by none-hidden -> hidden
					return true
				elseif a_hidden and not b_hidden then
					return false
				end
				return a.name:lower() < b.name:lower() -- Sort by directory name
			end

			-- 2. Files with titles come first
			local a_note = notes[a.path]
			local b_note = notes[b.path]
			local a_title = a_note and a_note.title
			local b_title = b_note and b_note.title
			if a_title and not b_title then
				return true
			elseif not a_title and b_title then
				return false
			elseif a_title and b_title then
				return a_title:lower() < b_title:lower() -- Sort by title
			end

			-- 3. Files without titles come last
			if not a_hidden and b_hidden then -- Sort by none-hidden -> hidden
				return true
			elseif a_hidden and not b_hidden then
				return false
			end
			return a.name:lower() < b.name:lower() -- Sort by filename
		end,
	},
}

return config
