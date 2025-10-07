local config = {
	follow_current_file = {
		enabled = true,
	},
	before_render = false,
	bind_to_cwd = true,
	enable_git_status = true,
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
			["n"] = "change_query",
		},
	},
	extra = {
		scan_none_zk_items = true,

		-- The fields fetched by `zk.api.list`
		select = { "absPath", "title"},

		---Default name formatter
		---@param note table? single cached note by zk.api.list
		---@param node NuiTree.Node
		name_formatter = function(note, node)
			return note and note.title or node.name or nil
		end,

		---Additional customizer for text and highlight table
		---@param rendere_nodes neotree.Render.Node[]
		---@param note table? single cached note by zk.api.list
		---@param node neotree.collections.ListNode
		name_extra_renderer = function(rendere_nodes, note, node)
			return rendere_nodes
		end,

		---Default sort function
		---@param notes table cached notes by zk.api.list
		---@param a table
		---@param b table
		sorter = function(notes, a, b)
			-- 1. Sort by directories -> files
			if a.type ~= b.type then
				return a.type == "directory"
			end

			-- 2. Sort by none-hidden -> hidden
			local a_hidden = string.sub(a.name, 1, 1) == "."
			local b_hidden = string.sub(b.name, 1, 1) == "."
			if a_hidden ~= b_hidden then
				return not a_hidden
			end

			-- 3. Sort by titled files -> untitled files
			local a_title = notes[a.path] and notes[a.path].title
			local b_title = notes[b.path] and notes[b.path].title
			local a_has_title = a_title and a_title ~= ""
			local b_has_title = b_title and b_title ~= ""
			if a_has_title ~= b_has_title then
				return a_has_title
			end

			-- Sort by title
			if a_has_title and b_has_title then
				return a_title:lower() < b_title:lower()
			end

			-- Sort by name
			return a.name:lower() < b.name:lower()
		end,
	},
}

return config
