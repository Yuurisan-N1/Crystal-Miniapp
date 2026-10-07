defmodule Banner do
  @moduledoc false

  @art "__   __                _                     _                 \n" <>
         "\\ \\ / /   _ _   _ _ __(_)___  __ _ _ __   __| | ___  ___ _   _ \n" <>
         " \\ V / | | | | | | '__| / __|/ _` | '_ \\ / _` |/ _ \\/ __| | | |\n" <>
         "  | || |_| | |_| | |  | \\__ \\ (_| | | | | (_| |  __/\\__ \\ |_| |\n" <>
         "  |_| \\__,_|\\__,_|_|  |_|___/\\__,_|_| |_|\\__,_|\\___||___/\\__,_|\n" <>
         "                                                               "

  @community "https://t.me/Y3YuYuYo"

  def set_title(name) do
    IO.write("\e]2;#{name} by : 佐賀県産 (YUURI)\a")
  end

  def show_banner(name) do
    IO.write("\e[H\e[2J\e[3J")
    IO.write("\e[36m\e[1m" <> @art <> "\e[0m\n")
    IO.write("\e[35m\e[1mWelcome to Yuuri's #{name}\e[0m\n")
    IO.write("\e[32m\e[1mJoin our community: #{@community}\e[0m\n")
    IO.write("\e[33m\e[1mCurrent time: #{stamp()}\e[0m\n")
    IO.write("\n")
  end

  defp stamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.local_time()

    :io_lib.format("~2..0B-~2..0B-~4..0B ~2..0B:~2..0B:~2..0B", [d, m, y, hh, mm, ss])
    |> to_string()
  end
end
