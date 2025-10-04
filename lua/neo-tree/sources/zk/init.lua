--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
-- local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan") -- DEBUG: NOT NEEDED
local renderer = require("neo-tree.ui.renderer")
local items = require("neo-tree.sources.zk.lib.items")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local git = require("neo-tree.git")
local glob = require("neo-tree.sources.filesystem.lib.globtopattern")
local defaults = require("neo-tree.sources.zk.defaults")

---@class neotree.sources.filesystem : neotree.Source
local M = {
	name = "zk",
	display_name = " 󰉓 zk ",
}

local wrap = function(func)
	return utils.wrap(func, M.name)
end

---@return neotree.sources.filesystem.State
local get_state = function(tabid)
	return manager.get_state(M.name, tabid) --[[@as neotree.sources.filesystem.State]]
end

local follow_internal = function(callback, force_show, async)
	log.trace("follow called")
	if vim.bo.filetype == "neo-tree" or vim.bo.filetype == "neo-tree-popup" then
		return false
	end
	local path_to_reveal = utils.normalize_path(manager.get_path_to_reveal() or "")
	if not utils.truthy(path_to_reveal) then
		return false
	end
	---@cast path_to_reveal string

	local state = get_state()
	if state.current_position == "float" then
		return false
	end
	if not state.path then
		return false
	end
	local window_exists = renderer.window_exists(state)
	if window_exists then
		local node = state.tree and state.tree:get_node()
		if node then
			if node:get_id() == path_to_reveal then
				-- already focused
				return false
			end
		end
		renderer.focus_node(state, path_to_reveal, true)
	else
		if not force_show then
			return false
		end
	end
	local is_in_path = path_to_reveal:sub(1, #state.path) == state.path
	if not is_in_path then
		return false
	end
end

M.follow = function(callback, force_show)
	if vim.fn.bufname(0) == "COMMIT_EDITMSG" then
		return false
	end
	if utils.is_floating() then
		return false
	end
	utils.debounce("neo-tree-zk-follow", function()
		return follow_internal(callback, force_show)
	end, 100, utils.debounce_strategy.CALL_LAST_ONLY)
end

local fs_stat = (vim.uv or vim.loop).fs_stat

---@param state neotree.sources.filesystem.State
---@param path string?
---@param path_to_reveal string?
---@param callback function?
M._navigate_internal = function(state, path, path_to_reveal, callback, async)
	log.trace("navigate_internal", state.current_position, path, path_to_reveal)
	state.dirty = false
	local is_search = utils.truthy(state.search_pattern)
	local path_changed = false
	if not path and not state.bind_to_cwd then
		path = state.path
	end
	if path == nil then
		log.debug("navigate_internal: path is nil, using cwd")
		path = manager.get_cwd(state)
	end
	path = utils.normalize_path(path)

	-- if path doesn't exist, navigate upwards until it does
	local orig_path = path
	local backed_out = false
	while not fs_stat(path) do
		log.debug(("navigate_internal: path %s didn't exist, going up a directory"):format(path))
		backed_out = true
		local parent, _ = utils.split_path(path)
		if not parent then
			break
		end
		path = parent
	end

	if backed_out then
		log.warn(("Root path %s doesn't exist, backing out to %s"):format(orig_path, path))
	end

	if path ~= state.path then
		log.debug("navigate_internal: path changed from ", state.path, " to ", path)
		state.path = path
		path_changed = true
	end

	if path_to_reveal then
		renderer.position.set(state, path_to_reveal)
		log.debug("navigate_internal: in path_to_reveal, state.position=", state.position.node_id)
		items.get_zk(state, path, callback)
	else
		local is_current = state.current_position == "current"
		local follow_file = state.follow_current_file.enabled
			and not is_search
			and not is_current
			and manager.get_path_to_reveal()
		local handled = false
		if utils.truthy(follow_file) then
			handled = follow_internal(callback, true, async)
		end
		if not handled then
			local success, msg = pcall(renderer.position.save, state)
			if success then
				log.trace("navigate_internal: position saved")
			else
				log.trace("navigate_internal: FAILED to save position: ", msg)
			end
			items.get_zk(state, path, callback)
		end
	end

	if path_changed and state.bind_to_cwd then
		manager.set_cwd(state)
	end
	local config = require("neo-tree").config
	if config.enable_git_status and not is_search and config.git_status_async then
		git.status_async(state.path, state.git_base, config.git_status_async_options)
	end
end

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
M.navigate = function(state, path, path_to_reveal, callback, async)
	state.dirty = false
	log.trace("navigate", path, path_to_reveal, async)
	utils.debounce("filesystem_navigate", function()
		M._navigate_internal(state, path, path_to_reveal, callback, async)
	end, 100, utils.debounce_strategy.CALL_FIRST_AND_LAST)
end

---Configures the plugin, should be called before the plugin is used.

-- ---@param config neotree.Config.Filesystem comes from the neo-tree's source specific option `{ zk = {...} }`
-- ---@param global_config neotree.Config.Base comes from the neo-tree's base option
M.setup = function(config, global_config)
	config = config or {}
	config.filtered_items = config.filtered_items or {}
	config.enable_git_status = config.enable_git_status or global_config.enable_git_status

	-- default_config = require("neo-tree.sources.zk.defaults") -- DEBUG: いったん無しにしてみる。neo-tree = { zk = {} } でセットしてみる
	config = vim.tbl_deep_extend("force", defaults, config) -- DEBUG: まさか逆？ いや合ってる
	-- config = vim.tbl_deep_extend("force", config, default_config)

	-- NOTE: うーん、neo-tree config から `{ zk = { filtered_items = {...} } }` をセットしておくと効くんだけどなぁ。

	-- NOTE: `lua/neo-tree/defaults.lua` ここに、local defaults = { filesystem = { filtered_items = {...} } } があった。
	-- これを取得している場所は...
	-- neo-tree/setup/init.lua:
	-- 2行目: local defaults = require("neo-tree.defaults")
	-- だ。
	--
	-- NOTE: ソースごとの設定の取得とマージの流れ
	-- neo-tree/setup/init.lua:
	-- local defaults = require("neo-tree.defaults")
	-- ここで、全default設定を取得し、
	-- M.merge_config = function(user_config)
	--    local default_config = vim.deepcopy(defaults)
	--    user_config = vim.deepcopy(user_config or {})
	-- からの 539行目:
	--    local source_default_config = default_config[source_name]
	-- で filesystem などの設定を取得し、568行目:
	--    merge_renderers(default_config, source_default_config, user_config)
	-- でマージをしている
	-- 個別に state.filtered_items としていなくて、state に config をそのままマージしてるから、検索しづらい。
	--
	-- TODO: つまり
	-- - state.filtered_items にコピーさせるには、
	--    A. そもそもの lua/neo-tree/defaults.lua の local defaults に zk の設定を含める (fork)
	--    B. neo-tree の setup() の config に `zk = { filtered_items = {...} }` をぜんぶ含める
	-- しかないらしい。
	-- ...
	-- zk の setup 中に自力で zk の default_config を持ってきて merge する... では遅いようだ。state.filtered_items にコピーしてもらえない。
	-- しかも setup 中からは未生成の state にアクセスできないし。

	vim.notify("config: " .. vim.inspect(config.filtered_items), vim.log.levels.INFO) -- DEBUG:
	vim.notify("default_config: " .. vim.inspect(defaults.filtered_items), vim.log.levels.INFO) -- DEBUG:

	-- Merge source specific config on global config
	local shared_config = {
		"enable_git_status",
		"git_status_async",
		"enable_diagnostics",
		"enable_opened_markers",
		"enable_modified_markers",
	}
	for _, key in ipairs(shared_config) do
		if config[key] == nil then
			config[key] = global_config[key]
		end
		local value_str
		if config[key] == true then
			value_str = "true"
		elseif config[key] == false then
			value_str = "false"
		else
			value_str = tostring(config[key])
		end
		-- vim.notify(key .. " : " .. value_str, vim.log.levels.INFO) -- DEBUG:
	end

	for _, key in ipairs({ "hide_by_pattern", "always_show_by_pattern", "never_show_by_pattern" }) do
		local list = config.filtered_items[key]
		if type(list) == "table" then
			for i, pattern in ipairs(list) do
				list[i] = glob.globtopattern(pattern)
			end
		end
	end

	for _, key in ipairs({ "hide_by_name", "always_show", "never_show" }) do
		local list = config.filtered_items[key]
		if type(list) == "table" then
			config.filtered_items[key] = utils.list_to_dict(list)
		end
	end
	-- vim.notify(vim.inspect(config.filtered_items), vim.log.levels.INFO) -- DEBUG:

	--Configure events for before_render
	if config.before_render then
		--convert to new event system
		manager.subscribe(M.name, {
			event = events.BEFORE_RENDER,
			handler = function(state)
				local this_state = get_state()
				if state == this_state then
					config.before_render(this_state)
				end
			end,
		})
	end
	-- DEBUG: ここで if を分離してみた

	if config.enable_git_status and config.git_status_async then
		manager.subscribe(M.name, {
			event = events.GIT_STATUS_CHANGED,
			handler = wrap(manager.git_status_changed),
		})
	elseif config.enable_git_status then
		manager.subscribe(M.name, {
			event = events.BEFORE_RENDER,
			handler = function(state)
				local this_state = get_state()
				if state == this_state then
					state.git_status_lookup = git.status(state.git_base)
				end
			end,
		})
	end

	-- Respond to git events from git_status source or Fugitive
	if config.enable_git_status then
		manager.subscribe(M.name, {
			event = events.GIT_EVENT,
			handler = function()
				manager.refresh(M.name)
			end,
		})
	end

	--Configure event handlers for file changes
	if config.use_libuv_file_watcher then
		manager.subscribe(M.name, {
			event = events.FS_EVENT,
			handler = wrap(manager.refresh),
		})
	else
		require("neo-tree.sources.filesystem.lib.fs_watch").unwatch_all()
		if global_config.enable_refresh_on_write then
			manager.subscribe(M.name, {
				event = events.VIM_BUFFER_CHANGED,
				handler = function(arg)
					local afile = arg.afile or ""
					if utils.is_real_file(afile) then
						log.trace("refreshing due to vim_buffer_changed event: ", afile)
						manager.refresh("filesystem")
					else
						log.trace("Ignoring vim_buffer_changed event for non-file: ", afile)
					end
				end,
			})
		end
	end

	if global_config.enable_refresh_on_write then
		manager.subscribe(M.name, {
			event = events.VIM_BUFFER_CHANGED,
			handler = function(args)
				if utils.is_real_file(args.afile) then
					manager.refresh(M.name)
				end
			end,
		})
	end

	--Configure event handlers for cwd changes
	if config.bind_to_cwd then
		manager.subscribe(M.name, {
			event = events.VIM_DIR_CHANGED,
			handler = wrap(manager.dir_changed),
		})
	end

	--Configure event handlers for lsp diagnostic updates
	if config.enable_diagnostics then
		manager.subscribe(M.name, {
			event = events.VIM_DIAGNOSTIC_CHANGED,
			handler = wrap(manager.diagnostics_changed),
		})
	end

	--Configure event handlers for modified files
	if config.enable_modified_markers then
		manager.subscribe(M.name, {
			event = events.VIM_BUFFER_MODIFIED_SET,
			handler = wrap(manager.opened_buffers_changed),
		})
	end

	if config.enable_opened_markers then
		for _, event in ipairs({ events.VIM_BUFFER_ADDED, events.VIM_BUFFER_DELETED }) do
			manager.subscribe(M.name, {
				event = event,
				handler = wrap(manager.opened_buffers_changed),
			})
		end
	end

	-- Configure event handler for follow_current_file option
	if config.follow_current_file.enabled then
		manager.subscribe(M.name, {
			event = events.VIM_BUFFER_ENTER,
			handler = function(args)
				if utils.is_real_file(args.afile) then
					M.follow()
				end
			end,
		})
	end
	-- vim.notify(vim.inspect(config.filtered_items), vim.log.levels.INFO) -- DEBUG:
end

M.default_config = defaults

return M
