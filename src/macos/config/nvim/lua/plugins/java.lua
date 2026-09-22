---@type LazySpec
return {
	{
		"mfussenegger/nvim-jdtls",
		ft = { "java" },
		opts = function(_, opts)
			local utils = require("astrocore")

			-- 定位 Java runtime。
			-- 不写死用户名/版本号：优先用 JAVA_HOME（mise/JDK 管理器一般会设），
			-- 否则回退到常见的 JDK 安装目录里第一个能用的。
			local function is_java_home(dir)
				return dir ~= nil and vim.fn.executable(dir .. "/bin/java") == 1
			end

			local function find_java_home()
				-- JAVA_HOME 可能是目录本身，也可能需要补 /Contents/Home（macOS bundle）
				if vim.env.JAVA_HOME then
					if is_java_home(vim.env.JAVA_HOME) then
						return vim.env.JAVA_HOME
					end
					if is_java_home(vim.env.JAVA_HOME .. "/Contents/Home") then
						return vim.env.JAVA_HOME .. "/Contents/Home"
					end
				end

				-- 每个候选：(根目录, 是否需要再补 /Contents/Home)
				-- mise 的 installs/java/<version> 直接就是 JAVA_HOME；
				-- macOS 的 /Library/Java/JavaVirtualMachines/*.jdk 要补 Contents/Home。
				local candidates = {
					{ vim.fn.expand("~/.local/share/mise/installs/java"), false },
					{ "/Library/Java/JavaVirtualMachines", true },
					{ "/opt/homebrew/opt/openjdk@21", false },
					{ "/usr/local/opt/openjdk@21", false },
				}

				for _, cand in ipairs(candidates) do
					local base, needs_contents_home = cand[1], cand[2]
					local ok, entries = pcall(vim.fn.readdir, base)
					if ok and type(entries) == "table" then
						table.sort(entries) -- readdir 顺序不稳定，排序保证可复现
						for _, entry in ipairs(entries) do
							local dir = base .. "/" .. entry
							if needs_contents_home then
								dir = dir .. "/Contents/Home"
							end
							if is_java_home(dir) then
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
			else
				-- 找不到 JDK 时明确说出来，而不是静默地什么都不配 ——
				-- 否则你会以为 jdtls 坏了，其实是没装 Java。
				vim.notify(
					"nvim-jdtls: 找不到 JDK（已尝试 JAVA_HOME、mise、Homebrew openjdk@21）。"
						.. "请安装 Java 21 或设置 JAVA_HOME。",
					vim.log.levels.WARN
				)
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
