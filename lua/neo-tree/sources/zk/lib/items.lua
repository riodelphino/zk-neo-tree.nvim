local vim = vim
local uv = vim.uv or vim.loop
local renderer = require("neo-tree.ui.renderer")
local file_items = require("neo-tree.sources.common.file-items")
-- local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local utils = require("neo-tree.utils")
local manager = require("neo-tree.sources.manager")
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
local function zk_sort_function(state, a, b)
	-- 1. Directories come first
	if a.type == "directory" and b.type ~= "directory" then
		return true
	elseif a.type ~= "directory" and b.type == "directory" then
		return false
	elseif a.type == "directory" and b.type == "directory" then
		return a.name:lower() < b.name:lower() -- Sort by directory name
	end

	-- Both are files
	local a_cache = state.notes_cache[a.path]
	local b_cache = state.notes_cache[b.path]
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

-- local handle_refresh_or_up = function(context, async_dir_scan)
-- 	local parent_id = context.parent_id
-- 	local path_to_reveal = context.path_to_reveal
-- 	local state = context.state
-- 	local path = parent_id or state.path
-- 	context.paths_to_load = {}
-- 	if parent_id == nil then
-- 		if utils.truthy(state.force_open_folders) then
-- 			for _, f in ipairs(state.force_open_folders) do
-- 				table.insert(context.paths_to_load, f)
-- 			end
-- 		elseif state.tree then
-- 			context.paths_to_load = renderer.get_expanded_nodes(state.tree, state.path)
-- 		end
-- 		-- Ensure parents of all expanded nodes are also scanned
-- 		if #context.paths_to_load > 0 and state.tree then
-- 			---@type table<string, boolean?>
-- 			local seen = {}
-- 			for _, p in ipairs(context.paths_to_load) do
-- 				---@type string?
-- 				local current = p
-- 				while current do
-- 					if seen[current] then
-- 						break
-- 					end
-- 					seen[current] = true
-- 					local current_node = state.tree:get_node(current)
-- 					current = current_node and current_node:get_parent_id()
-- 				end
-- 			end
-- 			context.paths_to_load = vim.tbl_keys(seen)
-- 		end
-- 		-- Ensure that there are no nested files in the list of folders to load
-- 		context.paths_to_load = vim.tbl_filter(function(p)
-- 			local stats = uv.fs_stat(p)
-- 			return stats and stats.type == "directory" or false
-- 		end, context.paths_to_load)
-- 		if path_to_reveal then
-- 			-- be sure to load all of the folders leading up to the path to reveal
-- 			local path_to_reveal_parts = utils.split(path_to_reveal, utils.path_separator)
-- 			table.remove(path_to_reveal_parts) -- remove the file name
-- 			-- add all parent folders to the list of paths to load
-- 			utils.reduce(path_to_reveal_parts, "", function(acc, part)
-- 				local current_path = utils.path_join(acc, part)
-- 				if #current_path > #path then -- within current root
-- 					table.insert(context.paths_to_load, current_path)
-- 					table.insert(state.default_expanded_nodes, current_path)
-- 				end
-- 				return current_path
-- 			end)
-- 			context.paths_to_load = utils.unique(context.paths_to_load)
-- 		end
-- 	end
--
-- 	local filtered_items = state.filtered_items or {}
-- 	context.is_a_never_show_file = function(fname)
-- 		if fname then
-- 			local _, name = utils.split_path(fname)
-- 			if name then
-- 				if filtered_items.never_show and filtered_items.never_show[name] then
-- 					return true
-- 				end
-- 				if utils.is_filtered_by_pattern(filtered_items.never_show_by_pattern, fname, name) then
-- 					return true
-- 				end
-- 			end
-- 		end
-- 		return false
-- 	end
-- 	table.insert(context.paths_to_load, path)
--
-- 	-- FIX: fs_scan から追加してみた
--
-- 	if fs_scan.async_dir_scan then
-- 		fs_scan.async_scan(context, path)
-- 	else
-- 		fs_scan.sync_scan(context, path)
-- 	end
-- end

function M.scan(state, callback)
	state.git_ignored = state.git_ignored or {}
	-- -- context が get_items() 内で新規生成されてしまう。一応ツリーは表示される。
	-- require("neo-tree.sources.zk.lib.fs_scan").get_items_async(
	fs_scan.get_items_async(
		state,
		state.path,
		state.path_to_reveal,
		function() -- context は callback 引数に無い
			-- DEBUG: fs_scan.lua から get_items() を実行したときの流れ
			--
			-- sources.filesystem.lib.fs_scan.lua:
			--    1. get_items() * context 生成
			--    2. handle_refresh_or_up()
			--    3. async_scan()
			--    4. job_complete()
			--    5. render_context()
			--    6. この関数 5 で、下記関数 ui.renderer.show_noteds() を async？ で呼び出し後、末尾で context = nil と初期化されてしまう。ので、流用できない
			--
			-- ui.renderer.lua:
			--    1. show_nodes(..., context.callback)
			--    2. 末尾で引数なしで実行される。ので、ここでも context は流用できない
			--
			-- つまり、先に get_items した場合は context の流用は不可能。

			-- DEBUG: プラン1 じゃどうする？
			--
			-- fs_scan.lua をコピペでカスタマイズ。
			--    1. root か state を返すようにする
			--    2. renderしないで、zk側でするようにする

			-- DEBUG: プラン2 できるかなぁ？ -> 元の関数が他のsourceから使えなくなってしまう -> 上書きではなく、似た別関数を作る感じなら？
			--
			-- 1. fs_scan.lua を fs_scan として require し
			-- 2. fs_scan.関数名 = function() で関数を上書き
			-- *  関数内から呼び出している local 関数は scope エラーにならんの？

			-- DEBUG: その他のプラン
			--
			-- 表示中の root.children を取得する common 関数があるんじゃないか？
			-- manager に get_state() がある！ -> でもこれは state だけで、children 含まず。state はもともと持ってるから意味ない

			-- print("state: " .. vim.inspect(state))
			-- local root = state.root
			-- 	or file_items.create_item(file_items.create_context(state), state.path, "directory")
			-- print("root: " .. vim.inspect(root))
			-- print("state: " .. vim.inspect(state))

			-- DEBUG: わかった！
			--
			-- get_items() しておくと、自動的に全ファイルが取得された状態で引き継がれる！

			require("zk.api").list(
				state.path,
				vim.tbl_extend("error", { select = { "absPath", "title" } }, state.zk.query or {}),
				function(err, notes)
					if err then
						log.error("Error querying notes " .. vim.inspect(err))
						return
					end

					-- cache
					state.notes_cache = index_by_path(notes)

					local context = file_items.create_context(state)
					local root = file_items.create_item(context, state.path, "directory")

					-- DEBUG: いったんなし
					-- root.children = state.tree:get_node(state.path) -- DEBUG: nui の nodes だけどこう受け渡すしか無い。一応動作するっぽい

					root.id = state.path
					root.name = vim.fn.fnamemodify(state.path, ":~")
					root.search_pattern = state.search_pattern

					-- DEBUG: 既にあるので不要
					--
					-- root.loaded = false
					-- context.folders[root.path] = root

					-- zk
					for _, note in pairs(notes) do
						local success, item = pcall(file_items.create_item, context, note.absPath, "file") -- DEBUG: これ、create じゃなくて既存のテーブル修正では？
						-- Extra fields (e.g. `item.extra.title = note.title`) are stripped out internally.
						-- print("item = " .. vim.inspect(item)) -- DEBUG:
						if not success then
							log.error("Error creating item for " .. note.absPath .. ": " .. item)
						end
					end
					-- print("root = " .. vim.inspect(root)) -- DEBUG:
					-- -- DEBUG: GPT プランなぜこれ？
					-- for _, note in pairs(root.children or {}) do
					-- 	local success, item = pcall(file_items.create_item, context, note.path, "file")
					-- 	if success and item then
					-- 		table.insert(root.children, item)
					-- 	else
					-- 		log.error("failed to create zk item for " .. note.path)
					-- 	end
					-- end

					-- DEBUG: 試しに、create_item で a フォルダを追加してみる。
					--
					-- local success, item =
					-- 	pcall(file_items.create_item, context, "/Users/rio/Projects/terminal/test/a", "directory") -- IT WORKS
					-- -- print(vim.inspect(item))

					-- FIX: 移植したけど、実行するとファイルリストが空になる
					-- require("neo-tree.sources.zk.lib.fs_scan").handle_refresh_or_up(context, false)
					-- require("neo-tree.sources.zk.lib.fs_scan").get_items_sync(state, state.path, nil, function()
					--
					-- context.paths_to_load = { state.path } -- 追加しとかないとエラーになる
					-- require("neo-tree.sources.zk.lib.fs_scan").sync_scan(context, state.path) -- 無理やり M. にしたけど、

					-- TODO: つまり、state を渡して全体ツリーに反映させたい場合は M.get_items_sync / M.get_items_async を呼ぶのが正解です。

					-- Expand default settings
					state.default_expanded_nodes = {}
					-- for id_, _ in pairs(context.folders) do -- TODO: remove later
					-- 	table.insert(state.default_expanded_nodes, id_)
					-- end

					state.zk_sort_function = function(a, b)
						return zk_sort_function(state, a, b)
					end

					state.sort_function_override = state.zk_sort_function

					-- print("Before deep_sort") -- DEBUG:
					-- print("root.children: " .. vim.inspect(root.children)) -- DEBUG:
					file_items.deep_sort(root.children, state.zk_sort_function)
					-- print("After deep_sort") -- DEBUG:
					-- file_items.advanced_sort(root.children, state) -- FIX: NEEDED?

					-- state.path_to_reveal = vim.fn.expand("%:p") or nil -- FIX: そんな bufnr は無い、のエラー
					-- -- GPT 修正版
					-- local buf = vim.api.nvim_get_current_buf()
					-- if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
					-- 	state.path_to_reveal = vim.api.nvim_buf_get_name(buf)
					-- else
					-- 	state.path_to_reveal = nil
					-- end
					-- state.path_to_reveal = manager.get_path_to_reveal(true) -- 常に nil になる

					-- FIX: もしや neo-tree 側が自動取得してくれるからやんなくていい？
					--
					-- state.path_to_reveal = utils.normalize_path(manager.get_path_to_reveal() or "")
					-- print("state.path_to_reveal: " .. (state.path_to_reveal or "nil"))

					-- renderer.show_nodes({ root }, state) -- DEBUG: あれ、これ要らない？ なくても表示されるぜ？ おそらく get_items_async() が内部で表示してる
					-- renderer.show_nodes({ root.children }, state) -- DEBUG:

					state.loading = false
					if type(callback) == "function" then
						callback()
					end
				end
			)
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
