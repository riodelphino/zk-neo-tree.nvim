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

	log.debug("follow file: ", path_to_reveal)
	local show_only_explicitly_opened = function()
		state.explicitly_opened_nodes = state.explicitly_opened_nodes or {}
		local expanded_nodes = renderer.get_expanded_nodes(state.tree)
		local state_changed = false
		for _, id in ipairs(expanded_nodes) do
			if not state.explicitly_opened_nodes[id] then
				if path_to_reveal:sub(1, #id) == id then
					state.explicitly_opened_nodes[id] = state.follow_current_file.leave_dirs_open
				else
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
	end

	fs_scan.get_items(state, nil, path_to_reveal, function()
		show_only_explicitly_opened()
		renderer.focus_node(state, path_to_reveal, true)
		if type(callback) == "function" then
			callback()
		end
	end, async)
	return true
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

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
M.navigate = function(state, path, path_to_reveal, callback, async)
	state.dirty = false
	log.trace("navigate", path, path_to_reveal, async)
	utils.debounce("filesystem_navigate", function()
		M._navigate_internal(state, path, path_to_reveal, callback, async)
	end, 100, utils.debounce_strategy.CALL_FIRST_AND_LAST)
	items.get_zk(state, path)
end

---Configures the plugin, should be called before the plugin is used.
---@param config neotree.Config.Filesystem Configuration table containing any keys that the user wants to change from the defaults. May be empty to accept default values.
---@param global_config neotree.Config.Base
M.setup = function(config, global_config)
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

	if config.bind_to_cwd then
		manager.subscribe(M.name, {
			event = events.VIM_DIR_CHANGED,
			handler = wrap(manager.refresh),
		})
	end

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
			handler = wrap(manager.modified_buffers_changed),
		})
	end

	-- Configure event handler for follow_current_file option
	if config.follow_current_file then
		manager.subscribe(M.name, {
			event = events.VIM_BUFFER_ENTER,
			handler = M.follow,
		})
		manager.subscribe(M.name, {
			event = events.VIM_TERMINAL_ENTER,
			handler = M.follow,
		})
	end
end

return M
