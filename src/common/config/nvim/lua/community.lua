return {
	-- 插件仓库
	"AstroNvim/astrocommunity",

	-- 主题
	{ import = "astrocommunity.colorscheme.catppuccin" },

	-- Copilot & 其它补全
	{ import = "astrocommunity.completion.copilot-lua-cmp" },
	-- { import = "astrocommunity.completion.avante-nvim" },

	-- { import = "astrocommunity.completion.avante-nvim" },

	-- AI
	{ import = "astrocommunity.ai.opencode-nvim" },

	-- Media
	{ import = "astrocommunity.media.img-clip-nvim" },

	-- bar
	{ import = "astrocommunity.bars-and-lines.dropbar-nvim" },
	{ import = "astrocommunity.motion.hop-nvim" },

	-- 语言包
	{ import = "astrocommunity.pack.lua" },
	{ import = "astrocommunity.pack.rust" },
	{ import = "astrocommunity.pack.python" },
	{ import = "astrocommunity.pack.go" },
	{ import = "astrocommunity.pack.java" },
	{ import = "astrocommunity.pack.typescript-all-in-one" },
}
