return {
  "keaising/im-select.nvim",
  config = function()
    require("im_select").setup({
        -- im-select 由 Homebrew 装（packages/macos/brew-cli.txt），直接在 PATH 里。
        -- 以前这里指向仓库内的一个包装脚本，那个包装已经删了。
        default_command = "im-select",
        default_im_select = "com.apple.keylayout.ABC",
        set_default_events = { "VimEnter", "FocusGained", "InsertLeave", "CmdlineLeave" },
        set_previous_events = { "InsertEnter" },
        keep_quiet_on_no_binary = true,
        async_switch_im = true,
    })
  end,
}
