-- This file contains the built-in components. Each componment is a function
-- that takes the following arguments:
--      config: A table containing the configuration provided by the user
--              when declaring this component in their renderer config.
--      node:   A NuiNode object for the currently focused node.
--      state:  The current state of the source providing the items.
--
-- The function should return either a table, or a list of tables, each of which
-- contains the following keys:
--    text:      The text to display for this item.
--    highlight: The highlight group to apply to this text.

local highlights = require("neo-tree.ui.highlights")
local common = require("neo-tree.sources.common.components")

local M = {}

---@return neotree.Render.Node
M.name = function(config, node, state)
	local highlight = config.highlight or highlights.FILE_NAME
	local text = node.name

	if node.type == "directory" then
		highlight = highlights.DIRECTORY_NAME
		if config.trailing_slash and text ~= "/" then
			text = text .. "/"
		end
	end

	if node:get_depth() == 1 and node.type ~= "message" then
		highlight = highlights.ROOT_NAME
		if state.current_position == "current" and state.sort and state.sort.label == "Name" then
			local icon = state.sort.direction == 1 and "▲" or "▼"
			text = text .. "  " .. icon
		end
	else
		local filtered_by = common.filtered_by(config, node, state)
		highlight = filtered_by.highlight or highlight
		if config.use_git_status_colors then
			local git_status = state.components.git_status({}, node, state)
			if git_status and git_status.highlight then
				highlight = git_status.highlight
			end
		end
	end

	if node.type == "file" then
		text = state.extra.name_formatter(state.zk.notes_cache, node)
	end

	local hl_opened = config.highlight_opened_files
	if hl_opened then
		local opened_buffers = state.opened_buffers or {}
		if
			(hl_opened == "all" and opened_buffers[node.path])
			or (opened_buffers[node.path] and opened_buffers[node.path].loaded)
		then
			highlight = highlights.FILE_NAME_OPENED
		end
	end

	if type(config.right_padding) == "number" then
		if config.right_padding > 0 then
			text = text .. string.rep(" ", config.right_padding)
		end
	else
		text = text
	end

	return {
		text = text,
		highlight = highlight,
	}
end

-- TODO: Add current_filter() from filesystem source

return vim.tbl_deep_extend("force", common, M)
