local vim = vim
local uv = vim.uv or vim.loop
local renderer = require("neo-tree.ui.renderer")
local file_items = require("neo-tree.sources.common.file-items")
local log = require("neo-tree.log")

local M = {}

local default_query = {
	desc = "All",
	query = {},
}

---Get notebook root directory from a path
---@param path string?
---@return string? path inside a notebook
local function resolve_notebook_path(path)
	local zk_util = require("zk.util")
	local cwd = vim.fn.getcwd()

	-- if the buffer has no name (i.e. it is empty), set the current working directory as it's path
	if not path or path == "" then
		path = cwd
	end
	if not zk_util.notebook_root(path) then
		if not zk_util.notebook_root(cwd) then
			-- if neither the buffer nor the cwd belong to a notebook, use $ZK_NOTEBOOK_DIR as fallback if available
			if vim.env.ZK_NOTEBOOK_DIR then
				path = vim.env.ZK_NOTEBOOK_DIR
			end
		else
			-- the buffer doesn't belong to a notebook, but the cwd does!
			path = cwd
		end
	end
	log.trace("resolve_notebook_path: ", path)
	-- at this point, the buffer either belongs to a notebook, or everything else failed
	return path
end

---Index state.zk.notes_cache by path
---@param notes table?
---@return table tbl indexed by path
local function index_by_path(notes)
	local tbl = {}
	for _, note in ipairs(notes or {}) do
		tbl[note.absPath] = note
	end
	return tbl
end

---Recursively list all files and directories in the path (including hidden and non-Zk items)
---@param context neotree.FileItemContext
---@param parent_id string
---@param notes_cache table
---@param folders_cache table
function M.scan_none_zk_items(context, parent_id, notes_cache, folders_cache, root)
	local handle = uv.fs_scandir(parent_id)
	if not handle then
		return
	end

	while true do
		local name, type = uv.fs_scandir_next(handle)
		if not name then
			break
		end
		local fullpath = parent_id .. "/" .. name
		if not notes_cache[fullpath] then
			local success, item = pcall(file_items.create_item, context, fullpath, type)
			if not success then
				log.error("Error creating item for " .. fullpath .. ": " .. item)
			end
			-- Hide the folders unlisted by zk.api.list
			if not folders_cache[fullpath] then
				if not item.filtered_by then -- To avoid overwriting filtered_by
					item.filtered_by = { name = true } -- TODO: Using `hide_by_name` to hide unlisted folders is correct?
				end
			end
		end
		if type == "directory" then
			M.scan_none_zk_items(context, fullpath, notes_cache, folders_cache, root)
		end
	end
end

---Get zk items and show neo-tree
---@param state table neotree.State
---@param path_to_reveal string?
---@param parent_id string?
---@param callback function?
function M.scan(state, parent_id, path_to_reveal, callback)
	log.trace("scan: " .. tostring(parent_id))
	state.git_ignored = state.git_ignored or {}
	state.zk.notes_cache = {}
	state.zk.folders_cache = {}
	renderer.acquire_window(state)

	local opts =
		vim.tbl_extend("error", { select = { "absPath", "title" } }, state.zk.query.query or {})

	require("zk.api").list(state.path, opts, function(err, notes)
		if err then
			log.error("Error querying notes " .. vim.inspect(err))
			return
		end

		state.zk.notes_cache = index_by_path(notes)

		-- Create context
		---@type neotree.sources.filesystem.Context
		local context = file_items.create_context(state) --[[@as neotree.sources.filesystem.Context]]
		context.state = state
		context.parent_id = parent_id
		context.path_to_reveal = path_to_reveal
		context.recursive = true
		context.callback = callback

		-- Create root folder
		---@type neotree.FileItem.Directory
		local root = file_items.create_item(context, state.path, "directory") --[[@as neotree.FileItem.Directory]]
		root.name = vim.fn.fnamemodify(state.path, ":~")
		root.loaded = true
		root.search_pattern = state.search_pattern
		context.root = root
		context.folders[root.path] = root

		-- Set expanded nodes
		state.default_expanded_nodes = state.force_open_folders or { state.path }

		-- Create items for zk notes
		for _, note in pairs(notes) do
			local stat = uv.fs_stat(note.absPath)
			if stat then
				local success, item = pcall(file_items.create_item, context, note.absPath, "file")
				if not success then
					log.error("Error creating item for " .. note.absPath .. ": " .. item)
				end
				state.zk.folders_cache[item.parent_path] = true
			end
		end

		-- Create items for none-zk files and directories
		if state.extra.scan_none_zk_items then
			M.scan_none_zk_items(context, state.path, state.zk.notes_cache, state.zk.folders_cache, root)
		end

		-- Register a sorter function
		local function sorter_wrapper(a, b)
			return state.extra.sorter(state.zk.notes_cache, a, b) -- Wrap sorter to access notes_cache
		end
		file_items.deep_sort(root.children, sorter_wrapper)
		-- *** Another way to register a sorter function? ***
		-- state.sort_function_override = state.zk.sorter
		-- file_items.deep_sort(root.children, nil)

		renderer.show_nodes({ root }, state, nil, function()
			state.loading = false
			if type(callback) == "function" then
				callback()
			end
		end)
	end)
end

---An entry point to get zk items
---@param state table neotree.State
---@param parent_id string?
---@param path_to_reveal string?
---@param callback function?
function M.get_zk(state, parent_id, path_to_reveal, callback)
	-- `state` keeps zk user/default config merged in its root.
	log.trace("get_zk: ", parent_id)

	if state.loading then
		return
	end
	state.loading = true

	if not state.zk then
		state.path = resolve_notebook_path(parent_id)
		state.zk = {
			query = default_query,
		}
	end

	M.scan(state, state.path, path_to_reveal, callback)
end

return M
