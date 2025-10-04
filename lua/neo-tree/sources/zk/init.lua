--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
local items = require("neo-tree.sources.zk.lib.items")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local git = require("neo-tree.git")
local glob = require("neo-tree.sources.filesystem.lib.globtopattern")

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

	-- DEBUG: can remove ???
	--
	-- log.debug("follow file: ", path_to_reveal)
	-- local show_only_explicitly_opened = function()
	-- 	state.explicitly_opened_nodes = state.explicitly_opened_nodes or {}
	-- 	local expanded_nodes = renderer.get_expanded_nodes(state.tree)
	-- 	local state_changed = false
	-- 	for _, id in ipairs(expanded_nodes) do
	-- 		if not state.explicitly_opened_nodes[id] then
	-- 			if path_to_reveal:sub(1, #id) == id then
	-- 				state.explicitly_opened_nodes[id] = state.follow_current_file.leave_dirs_open
	-- 			else
	-- 				local node = state.tree:get_node(id)
	-- 				if node then
	-- 					node:collapse()
	-- 					state_changed = true
	-- 				end
	-- 			end
	-- 		end
	-- 		if state_changed then
	-- 			renderer.redraw(state)
	-- 		end
	-- 	end
	-- end
	--
	-- fs_scan.get_items(state, nil, path_to_reveal, function()
	-- 	show_only_explicitly_opened()
	-- 	renderer.focus_node(state, path_to_reveal, true)
	-- 	if type(callback) == "function" then
	-- 		callback()
	-- 	end
	-- end, async)
	-- return true
end

M.default_config = {
	follow_current_file = true,
	window = {
		mappings = {
			["n"] = "change_query",
		},
	},
}

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
		print("M._navigate_internal の中で get_items が呼ばれる直前")
		fs_scan.get_items(state, nil, path_to_reveal, callback) -- DEBUG: 削除するとneo-treeがロードされない  -- WARN: get_items
		print("M._navigate_internal の中で get_zk が呼ばれる直前")
		items.get_zk(state, path) -- DEBUG: これいる？ 試しにいれたけど。
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
			print("not handled になり、get_items を呼ぶ直前")
			fs_scan.get_items(state, nil, nil, callback, async) -- WARN: get_items
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
	items.get_zk(state, path) -- DEBUG: これが async に繋がってないのがおかしくない？
end

-- ---Configures the plugin, should be called before the plugin is used.
-- ---@param config neotree.Config.Filesystem Configuration table containing any keys that the user wants to change from the defaults. May be empty to accept default values.
-- ---@param global_config neotree.Config.Base
M.setup = function(config, global_config)
	config.filtered_items = config.filtered_items or {}
	config.enable_git_status = config.enable_git_status or global_config.enable_git_status

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
	elseif global_config.enable_git_status and global_config.git_status_async then
		manager.subscribe(M.name, {
			event = events.GIT_STATUS_CHANGED,
			handler = wrap(manager.git_status_changed),
		})
	elseif global_config.enable_git_status then
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
	if global_config.enable_git_status then
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
	if global_config.enable_diagnostics then
		manager.subscribe(M.name, {
			event = events.VIM_DIAGNOSTIC_CHANGED,
			handler = wrap(manager.diagnostics_changed),
		})
	end

	--Configure event handlers for modified files
	if global_config.enable_modified_markers then
		manager.subscribe(M.name, {
			event = events.VIM_BUFFER_MODIFIED_SET,
			handler = wrap(manager.opened_buffers_changed),
		})
	end

	if global_config.enable_opened_markers then
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
end

return M
