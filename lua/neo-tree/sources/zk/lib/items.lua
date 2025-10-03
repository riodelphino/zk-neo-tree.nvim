local vim = vim
local file_items = require("neo-tree.sources.common.file-items")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local log = require("neo-tree.log")

local M = {}

local default_query = {
	desc = "All",
	query = {},
}

---@param bufnr number?
---@return string? path inside a notebook
local function resolve_notebook_path_from_dir(path, cwd)
	-- if the buffer has no name (i.e. it is empty), set the current working directory as it's path
	if not path or path == "" then
		path = cwd
	end
	if not require("zk.util").notebook_root(path) then
		if not require("zk.util").notebook_root(cwd) then
			-- if neither the buffer nor the cwd belong to a notebook, use $ZK_NOTEBOOK_DIR as fallback if available
			if vim.env.ZK_NOTEBOOK_DIR then
				path = vim.env.ZK_NOTEBOOK_DIR
			end
		else
			-- the buffer doesn't belong to a notebook, but the cwd does!
			path = cwd
		end
	end
	-- at this point, the buffer either belongs to a notebook, or everything else failed
	return path
end

local function index_by_path(notes)
	local tbl = {}
	for _, note in ipairs(notes) do
		tbl[note.absPath] = note
	end
	return tbl
end

---Sort by 1.Directory > 2.Title > 3.filename
local function sorter(state, a, b)
	-- 1. Directories come first
	if a.type == "directory" and b.type ~= "directory" then
		return true
	elseif a.type ~= "directory" and b.type == "directory" then
		return false
	elseif a.type == "directory" and b.type == "directory" then
		return a.name:lower() < b.name:lower() -- Sort by directory name
	end

	-- Both are files
	local a_cache = state.zk.notes_cache[a.path]
	local b_cache = state.zk.notes_cache[b.path]
	local a_title = a_cache and a_cache.title
	local b_title = b_cache and b_cache.title

	-- 2. Titles come second
	if a_title and not b_title then
		return true
	elseif not a_title and b_title then
		return false
	elseif a_title and b_title then -- Sort by Title
		if a_title:lower() == b_title:lower() then
			return a.name:lower() < b.name:lower()
		end
		return a_title:lower() < b_title:lower()
	end

	-- 3. Both no title
	return a.name:lower() < b.name:lower() -- Sort by filename
end

function M.scan(state, callback)
	state.git_ignored = state.git_ignored or {}

	-- Get zk items
	require("zk.api").list(
		state.path,
		vim.tbl_extend("error", { select = { "absPath", "title" } }, state.zk.query or {}),
		function(err, notes)
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

			state.default_expanded_nodes = {}
			for id, opened in ipairs(state.explicitly_opened_nodes or {}) do
				if opened then
					table.insert(state.default_expanded_nodes, id)
				end
			end

			-- Sort
			state.zk.sorter = function(a, b)
				return sorter(state, a, b)
			end
			state.sort_function_override = state.zk.sorter
			file_items.deep_sort(root.children, state.zk.sorter)

			state.loading = false
			if type(callback) == "function" then
				callback()
			end
		end
	)
end

---Get a table of all open buffers, along with all parent paths of those buffers.
---The paths are the keys of the table, and all the values are 'true'.
function M.get_zk(state, path)
	if state.loading then
		return
	end
	state.loading = true
	if not state.zk then
		state.path = resolve_notebook_path_from_dir(path, vim.fn.getcwd())
		state.zk = {
			query = default_query,
		}
	end

	M.scan(state)
end

return M
