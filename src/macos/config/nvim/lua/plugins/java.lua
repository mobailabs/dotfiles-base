---@type LazySpec
return {
	{
		"mfussenegger/nvim-jdtls",
		ft = { "java" },
		opts = function(_, opts)
			local utils = require("astrocore")

			-- 定位 Java 21 runtime。
			-- 不写死用户名/版本号：优先用 JAVA_HOME（mise/JDK 管理器一般会设），
			-- 否则回退到 mise 的 java 安装目录里第一个能用的 JDK。
			local function find_java_home()
				if vim.env.JAVA_HOME and vim.uv.fs_stat(vim.env.JAVA_HOME) then
					return vim.env.JAVA_HOME
				end

				local candidates = {
					vim.fn.expand("~/.local/share/mise/installs/java"),
					"/opt/homebrew/opt/openjdk@21",
					"/usr/local/opt/openjdk@21",
					"/Library/Java/JavaVirtualMachines",
				}

				for _, base in ipairs(candidates) do
					local ok, entries = pcall(vim.fn.readdir, base)
					if ok and entries then
						-- readdir 顺序不稳定，排序保证可复现
						table.sort(entries)
						for _, entry in ipairs(entries) do
							local dir = base .. "/" .. entry
							if vim.uv.fs_stat(dir .. "/bin/java") then
								return dir
							end
						end
					end
				end

				return nil
			end

			local java_home = find_java_home()

			-- 添加 Java runtimes 配置
			opts.settings = opts.settings or {}
			opts.settings.java = opts.settings.java or {}
			opts.settings.java.configuration = opts.settings.java.configuration or {}
			if java_home then
				opts.settings.java.configuration.runtimes = {
					{
						name = "JavaSE-21",
						path = java_home,
						default = true,
					},
				}

				-- 强制使用找到的 Java 进行调试
				opts.init_options = opts.init_options or {}
				opts.init_options.java = opts.init_options.java or {}
				opts.init_options.java.javaExec = java_home .. "/bin/java"
			end

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
