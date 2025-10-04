local vim = vim
local file_items = require("neo-tree.sources.common.file-items")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
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

---Default sort function (directory > title > filename)
---@param state table neotree.State
---@param a table
---@param b table
local function sorter(state, a, b)
	print("sorter")
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

---Get and set zk items
---@param state table neotree.State
---@param callback function?
function M.scan(state, callback)
	state.git_ignored = state.git_ignored or {}

	-- Get zk items

	-- state.zk.query = {
	-- 	desc = "Tag book",
	-- 	query = {
	-- 		tags = { "book" },
	-- 	},
	-- }

	local opts =
		vim.tbl_extend("error", { select = { "absPath", "title" } }, state.zk.query.query or {})

	require("zk.api").list(state.path, opts, function(err, notes)
		if err then
			log.error("Error querying notes " .. vim.inspect(err))
			return
		end

		state.zk.notes_cache = index_by_path(notes)

		local context = file_items.create_context(state)
		local root
		if vim.tbl_isempty(state.zk.query.query or {}) then
			root = file_items.create_item(context, state.path, "directory") -- Get all files and directories
		else
			root = {}
			root.path = state.path
			root.children = {} -- DEBUG: 初期化方法は？ common かな？
		end

		root.id = state.path
		root.name = vim.fn.fnamemodify(state.path, ":~")
		root.search_pattern = state.search_pattern
		context.folders[root.path] = root
		-- print("root (after context.folders[]): " .. vim.inspect(root)) -- DEBUG: ここでは root しかない

		-- Create items from zk notes
		for _, note in pairs(notes) do
			local success, item = pcall(file_items.create_item, context, note.absPath, "file")
			if not success then
				log.error("Error creating item for " .. note.absPath .. ": " .. item)
			end
		end
		-- print("root (after create_item with notes_cache): " .. vim.inspect(root)) -- DEBUG: ここでは root.children が生成済み(当然)

		state.default_expanded_nodes = {}
		for id, opened in ipairs(state.explicitly_opened_nodes or {}) do
			if opened then
				table.insert(state.default_expanded_nodes, id)
			end
		end

		if not vim.tbl_isempty(state.zk.query.query or {}) then
			-- print("state.zk.query.query is not empty.") -- DEBUG:
			-- Add here ムダなファイルを除去する

			-- for _, root in ipairs(state.tree:get_nodes()) do
			-- 	-- filter_tree(root:get_id())
			-- 	print(vim.inspect(root))
			-- end
			-- -- manager.redraw(state.name)

			-- for idx, item in ipairs(root.children) do
			-- 	print(vim.inspect(item))
			--    if not state.zk.notes_cache[item.id] then
			--       -- root.children[idx] を削除する処理
			--    end
			-- end

			-- root.children = vim.tbl_filter(
			-- 	function(item) -- 良い方法だけど、root.children がそもそも notes_cache と同じになってしまってる。nodeじゃないとね。
			-- 		print(vim.inspect(item))
			-- 		return state.zk.notes_cache[item.id] ~= nil
			-- 	end,
			-- 	root.children
			-- )
		end

		-- DEBUG: NOT WORKS
		-- tree 生成されてないエラー
		--
		-- local renderer = require("neo-tree.ui.renderer")
		--
		-- -- 表示中ツリーから node をフィルタ
		-- local nodes = renderer.get_expanded_nodes(state.tree, state.path) -- 展開ノードを取得
		-- local filtered = vim.tbl_filter(function(node)
		-- 	return state.zk.notes_cache[node.id] ~= nil
		-- end, nodes)
		-- renderer.show_nodes(filtered, state)

		-- DEBUG: ノード削除のテストだ。get_items を呼ばなくしたので、いらないはず
		-- -- print("state: " .. vim.inspect(state)) -- DEBUG:
		-- if state.tree then
		-- 	-- print("tree あったよ！") -- DEBUG:
		-- 	local node_id = "/Users/rio/Projects/terminal/test/A.md"
		-- 	local node = state.tree:get_node(node_id)
		-- 	if node then
		-- 		-- print("node もあったよ！: " .. vim.inspect(node)) -- DEBUG:
		-- 		local ret = state.tree:remove_node(node_id)
		-- 		if not ret then
		-- 			print("node 削除にしっぱい！") -- DEBUG:
		-- 		end
		-- 		state.tree:render()
		--
		-- 		node = state.tree:get_node(node_id) -- Again
		-- 		-- print("削除したはずのnode: " .. vim.inspect(node)) -- DEBUG:
		--
		-- 		-- print("node 削除後のstate: " .. vim.inspect(state)) -- DEBUG:
		--
		-- 		-- local utils = require("neo-tree.utils")
		-- 		-- local manager = require("neo-tree.sources.manager")
		-- 		-- local refresh = utils.wrap(manager.refresh, "zk")
		--
		-- 		-- require("neo-tree.sources.manager").redraw("zk")
		-- 		-- refresh()
		-- 	end
		-- end

		-- Sort
		state.zk.sorter = function(a, b)
			return sorter(state, a, b) -- Wrap sorter to access state.zk.notes_cache
		end
		state.sort_function_override = state.zk.sorter
		-- file_items.deep_sort(root.children)
		file_items.deep_sort(root.children, state.zk.sorter)

		renderer.show_nodes({ root }, state, nil, callback)
		-- renderer.show_nodes({ root }, state, state.path, callback)

		state.loading = false
		if type(callback) == "function" then
			callback()
		end
	end)
end

---An entry point to get zk items
---@param state table neotree.State
---@param path string?
function M.get_zk(state, path, callback)
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
