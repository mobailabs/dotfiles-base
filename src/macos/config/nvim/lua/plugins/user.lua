-- 你自己的插件定制放这里（AstroNvim 的约定文件）。
-- 本目录（lua/plugins/）被 lazy_setup.lua 的 `{ import = "plugins" }` 自动加载。
--
-- 用法示例：
--   加插件：   { "作者/插件名", event = "...", config = function() ... end }
--   改默认：   { "现有插件", opts = { ... } }
--   禁用插件： { "作者/插件名", enabled = false }
--
-- 原来的模板示例（presence.nvim、lsp_signature、dashboard ASCII 头、
-- LuaSnip / nvim-autopairs 示例配置）已清掉 —— 它们只是 AstroNvim 模板的
-- 演示内容，不是实际使用的东西。需要时按上面的写法加回来。

---@type LazySpec
return {}
