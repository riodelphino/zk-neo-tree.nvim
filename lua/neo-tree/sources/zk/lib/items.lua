local vim = vim
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

---Get zk items and show neo-tree
---@param state table neotree.State
---@param callback function?
function M.scan(state, callback)
	log.trace("scan: " .. state.path)
	state.git_ignored = state.git_ignored or {}

	local opts =
		vim.tbl_extend("error", { select = { "absPath", "title" } }, state.zk.query.query or {})

	require("zk.api").list(state.path, opts, function(err, notes)
		if err then
			log.error("Error querying notes " .. vim.inspect(err))
			return
		end

		state.zk.notes_cache = index_by_path(notes)

		local context = file_items.create_context(state)

		local root = file_items.create_item(context, state.path, "directory")
		root.id = state.path
		root.name = vim.fn.fnamemodify(state.path, ":~")
		root.search_pattern = state.search_pattern
		context.folders[root.path] = root

		-- Create items from zk notes
		for _, note in pairs(notes) do
			local success, item = pcall(file_items.create_item, context, note.absPath, "file")
			if not success then
				log.error("Error creating item for " .. note.absPath .. ": " .. item)
			end
		end

		-- Set expanded nodes
		state.default_expanded_nodes = {}
		for id, opened in ipairs(state.explicitly_opened_nodes or {}) do
			if opened then
				table.insert(state.default_expanded_nodes, id)
			end
		end

		-- Sort
		local function sorter_wrapper(a, b)
			return state.extra.sorter(state.zk.notes_cache, a, b) -- Wrap sorter to access notes_cache
		end
		-- state.sort_function_override = state.zk.sorter
		file_items.deep_sort(root.children, sorter_wrapper)

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
---@param path string?
function M.get_zk(state, path, callback)
	-- `state` keeps zk user/default config merged in its root.
	log.trace("get_zk: ", path)

	if state.loading then
		return
	end
	state.loading = true

	if not state.zk then
		state.path = resolve_notebook_path(path)
		state.zk = {
			query = default_query,
		}
	end

	M.scan(state, callback)
end

return M
