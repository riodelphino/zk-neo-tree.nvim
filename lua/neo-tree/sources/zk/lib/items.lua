local vim = vim
local renderer = require("neo-tree.ui.renderer")
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

---Sort by Directory > Title > No Title
local function zk_sort_function(state, a, b)
	-- Directories first
	if a.type == "directory" and b.type ~= "directory" then
		return true
	elseif a.type ~= "directory" and b.type == "directory" then
		return false
	elseif a.type == "directory" and b.type == "directory" then
		return a.name:lower() < b.name:lower()
	end

	-- Both are files
	local a_cache = state.notes_cache[a.path]
	local b_cache = state.notes_cache[b.path]
	local a_title = a_cache and a_cache.title
	local b_title = b_cache and b_cache.title

	-- Title group priority
	if a_title and not b_title then
		return true
	elseif not a_title and b_title then
		return false
	end

	-- Both have title → sort by title
	if a_title and b_title then
		if a_title:lower() == b_title:lower() then
			return a.name:lower() < b.name:lower()
		end
		return a_title:lower() < b_title:lower()
	end

	-- Both no title → sort by filename
	return a.name:lower() < b.name:lower()
end

function M.scan(state, callback)
	require("zk.api").list(
		state.path,
		vim.tbl_extend("error", { select = { "absPath", "title" } }, state.zk.query.query),
		function(err, notes)
			if err then
				log.error("Error querying notes " .. vim.inspect(err))
				return
			end

			-- cache
			state.notes_cache = index_by_path(notes)

			local context = file_items.create_context(state)

			local root = file_items.create_item(context, state.path, "directory")

			root.id = state.path
			root.name = vim.fn.fnamemodify(state.path, ":~")
			root.path = state.path -- FIX: Necessarly?
			root.type = "directory"
			root.children = {}
			root.loaded = true
			root.search_pattern = state.search_pattern
			context.folders[root.path] = root

			-- zk
			for _, note in pairs(notes) do
				local success, item = pcall(file_items.create_item, context, note.absPath, "file")
				if success then
					item.title = note.title -- FIX: Delete if use state.notes_cache in sort
				else
					log.error("Error creating item for " .. note.absPath .. ": " .. item)
				end
			end

			-- Expand default settings
			state.default_expanded_nodes = {}
			for id_, _ in pairs(context.folders) do
				table.insert(state.default_expanded_nodes, id_)
			end

			local function sort_by_yaml_title(a, b)
				if a.type == "directory" and b.type ~= "directory" then
					return true
				elseif a.type ~= "directory" and b.type == "directory" then
					return false
				end

				-- print("a.path: " .. a.path)
				print(vim.inspect(a))
				-- print(state.notes_cache[a.path] and state.notes_cache[a.path].title or "nashi")
				local a_title = state.notes_cache[a.path] and state.notes_cache[a.path].title or a.name
				local b_title = state.notes_cache[b.path] and state.notes_cache[b.path].title or b.name
				local a_compare = vim.fs.joinpath(a.parent_path, a_title)
				local b_compare = vim.fs.joinpath(b.parent_path, b_title)

				-- if a_title == b_title then
				-- 	return a.name < b.name
				-- end
				-- return a_title < b_title
				return a_compare < b_compare
			end
			-- TODO: なんでここ？これいる？
			-- file_items.deep_sort(root.children)

			-- TODO: state.sort_function_override にセットすると、フィルタクリア時にクリアされちゃうよね？
			-- state.sort_function_override = function(a, b)
			-- 	-- YAML title → filename の順
			-- 	-- print("sort_function_override is called")
			-- 	if a.type == "directory" and b.type ~= "directory" then
			-- 		return true
			-- 	elseif a.type ~= "directory" and b.type == "directory" then
			-- 		return false
			-- 	end
			-- 	local a_title = a.title or a.name
			-- 	local b_title = b.title or b.name
			-- 	if a_title == b_title then
			-- 		return a.name < b.name
			-- 	end
			-- 	return a_title < b_title
			-- end

			-- file_items.deep_sort(root.children, M.sort_by_yaml_title(state))
			-- file_items.deep_sort(root.children, sort_by_yaml_title)
			-- file_items.deep_sort(root.children)
			-- context.deep_sort(root.children)
			-- print("after deep_sort " .. vim.inspect(root.children))
			-- file_items.advanced_sort(root.children, state) -- TODO: 最後まで使ってた

			-- table.sort(root.children, function(a, b)
			-- 	return M.sort_by_yaml_title(state, a, b)
			-- end)

			state.zk_sort_function = function(a, b) -- FIX: Using closure (Can use sort_fielder?)
				return zk_sort_function(state, a, b)
			end

			state.sort_function_override = state.zk_sort_function -- これでどうだ？
			-- file_items.deep_sort(root.children, function(a, b)
			-- 	zk_sort_function(state, a, b)
			-- end)
			file_items.deep_sort(root.children, state.zk_sort_function) -- FIX: DOES IT WORK?
			-- file_items.advanced_sort(root.children, state) -- TODO: やっぱ override を設定した場合に備えて、要るんじゃね？

			-- file_items.advanced_sort(root.children, state) -- TODO: やっぱ override を設定した場合に備えて、要るんじゃね？
			-- table.sort(root.children, state.zk_sort_function)

			renderer.show_nodes({ root }, state)
			-- renderer.redraw(state) -- 関係なし

			print("after renderer.show_nodes: root.children: " .. vim.inspect(root.children)) -- TODO: debug code
			-- print("state.sort_field_provider: " .. vim.inspect(state.sort_field_provider))
			-- print("state.tree: " .. vim.inspect(state.tree))

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
