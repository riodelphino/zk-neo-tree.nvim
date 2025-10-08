--This file should contain all commands meant to be used by mappings.
local vim = vim
local uv = vim.uv or vim.loop
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local manager = require("neo-tree.sources.manager")
local log = require("neo-tree.log")
local fs_actions = require("neo-tree.sources.filesystem.lib.fs_actions")
local fs_commands = require("neo-tree.sources.filesystem.commands")
local scan = require("neo-tree.sources.zk.lib.items").scan

local M = {}

M.name = "zk"

local function format_item(item)
	return item.desc
end

local refresh = utils.wrap(manager.refresh, "zk")

---Change the query dynamically
---@param state neotree.sources.zk.State
M.change_query = function(state)
	local tree = state.tree
	local node = tree:get_node()
	local id = node:get_id()
	local items = {}
	for _, item in pairs(require("neo-tree.sources.zk.lib.queries")) do
		table.insert(items, item)
	end
	vim.ui.select(items, { prompt = "zk query", format_item = format_item }, function(item)
		if not item then
			return
		end
		item.input(state.zk.notebookPath, id, function(res)
			state.zk.query = res
			refresh()
		end)
	end)
end

-- copied from neo-tree/sources/common/commands.lua
---Gets the node parent folder recursively
---@param tree table to look for nodes
---@param node table? to look for folder parent
---@return table table
local function get_folder_node(tree, node)
	if not node then
		node = tree:get_node()
	end
	if node.type == "directory" then
		return node
	end
	return get_folder_node(tree, tree:get_node(node:get_parent_id()))
end

local function show_only_explicitly_opened(state, eod, path_to_reveal)
	local expanded_nodes = renderer.get_expanded_nodes(state.tree)
	local state_changed = false
	for _, id in ipairs(expanded_nodes) do
		local is_explicit = eod[id]
		if not is_explicit then
			local is_in_path = path_to_reveal and path_to_reveal:sub(1, #id) == id
			if is_in_path then
				is_explicit = true
			end
		end
		if not is_explicit then
			local node = state.tree:get_node(id)
			if node then
				node:collapse()
				state_changed = true
			end
		end
	end
	if state_changed then
		renderer.redraw(state)
	end
end

---Create a directory recursively
---@param path string
local function mkdir_p(path)
	function create_all_as_folders(in_path)
		if not uv.fs_stat(in_path) then
			local parent, _ = utils.split_path(in_path)
			if parent then
				create_all_as_folders(parent)
			end
			uv.fs_mkdir(in_path, 493)
		end
	end
	create_all_as_folders(path)
end

---Add new note
---@param state neotree.sources.zk.State
M.add = function(state)
	local tree = state.tree
	local node = get_folder_node(tree)
	local in_directory = node:get_id()
	local dir = in_directory:sub(state.path:len() + 1)
	if dir:len() > 0 then
		dir = dir:sub(2)
	end
	local eod = state.explicitly_opened_nodes or {}
	vim.ui.input({ prompt = "new note title" }, function(input)
		if input then
			local dir_ = vim.fn.fnamemodify(input, ":h")
			if dir_ ~= "." then
				if dir == "" then -- DEBUG: ここら辺なにやってるかわからん
					dir = dir_
				else
					dir = dir .. utils.path_separator .. dir_
				end
			end
			local title = vim.fn.fnamemodify(input, ":t")
			mkdir_p(state.path .. utils.path_separator .. dir) -- DEBUG: うーん、そうじゃない。title に dir は含めないよ。config.toml を参照しようよ〜
			require("zk.api").new(state.path, {
				title = title,
				dir = dir,
			}, function(err, res)
				if err then
					log.error("Error querying notes " .. vim.inspect(err))
					return
				end
				vim.cmd("e " .. res.path)
				scan(state, state.path, res.path, function()
					show_only_explicitly_opened(state, eod, res.path)
					renderer.focus_node(state, res.path, true)
				end)
			end)
		end
	end)
end

---Delete selected item
---@param state neotree.sources.zk.State
M.delete = function(state)
	local tree = state.tree
	local node = tree:get_node()
	local id = node:get_id()
	fs_actions.delete_node(id, function()
		require("zk.api").index(state.path, {}, function(err)
			if err then
				log.error("Error indexing notes " .. vim.inspect(err))
			end
			-- local eod = state.explicitly_opened_nodes or {}
			scan(state, state.path, nil, function()
				-- show_only_explicitly_opened(state, eod) -- FIX: Tree becomes completely empty
			end)
		end)
	end)
end

-- TODO: delete_note_visual

---Toggles whether hidden files are shown or not.
---@param state neotree.sources.zk.State
M.toggle_hidden = function(state)
	state.filtered_items.visible = not state.filtered_items.visible
	log.info("Toggling hidden files: " .. tostring(state.filtered_items.visible))
	refresh()
end

---Toggles whether the tree is filtered by gitignore or not.
---@param state neotree.sources.zk.State
M.toggle_gitignore = function(state)
	log.warn("`toggle_gitignore` has been removed, running toggle_hidden instead.")
	M.toggle_hidden(state)
end

M = vim.tbl_deep_extend("keep", M, fs_commands) -- Also including 'common.commands'

return M
