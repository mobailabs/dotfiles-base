return {
  "keaising/im-select.nvim",
  config = function()
    require("im_select").setup({
        default_command = vim.fn.expand("$HOME/dotfiles/src/common/bin/im-select"),
        default_im_select = "com.apple.keylayout.ABC",
        set_default_events = { "VimEnter", "FocusGained", "InsertLeave", "CmdlineLeave" },
        set_previous_events = { "InsertEnter" },
        keep_quiet_on_no_binary = true,
        async_switch_im = true,
    })
  end,
}
