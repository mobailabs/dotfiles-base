---@type LazySpec
return {
	{
		"mfussenegger/nvim-jdtls",
		ft = { "java" },
		opts = function(_, opts)
			local utils = require("astrocore")

			-- 添加 Java runtimes 配置
			opts.settings = opts.settings or {}
			opts.settings.java = opts.settings.java or {}
			opts.settings.java.configuration = opts.settings.java.configuration or {}
			opts.settings.java.configuration.runtimes = {
				{
					name = "JavaSE-21",
					path = "/Users/zhaopeng/.local/share/mise/installs/java/zulu-21.46.19.0",
					default = true,
				},
			}

			-- 强制使用 Java 21 进行调试
			opts.init_options = opts.init_options or {}
			opts.init_options.java = opts.init_options.java or {}
			opts.init_options.java.javaExec = "/Users/zhaopeng/.local/share/mise/installs/java/zulu-21.46.19.0/bin/java"

			-- 项目根目录标记（优先找 pom.xml）
			local root_markers = { "pom.xml", "build.gradle", "mvnw", "gradlew", ".git" }

			-- 计算项目名称和 workspace
			local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
			local workspace_dir = vim.fn.stdpath("data") .. "/site/java/workspace-root/" .. project_name
			vim.fn.mkdir(workspace_dir, "p")

			return utils.extend_tbl({
				root_dir = vim.fs.root(0, root_markers),
			}, opts)
		end,
	},
}
