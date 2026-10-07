Code.require_file("utils/json.ex", __DIR__)
Code.require_file("utils/banner.ex", __DIR__)

defmodule Crystal do
  @moduledoc false

  @my_project "Crystal Mining Miniapp"
  @base_url "https://hbvkjhkj-production.up.railway.app"
  @ref_code "0466MRP1JP"
  @root __DIR__

  @reset "\e[0m"
  @bold "\e[1m"
  @red "\e[91m"
  @green "\e[92m"
  @yellow "\e[93m"

  @ad_gate_wait 3
  @task_wait 16
  @pulse_gap 2
  @pulse_max 5
  @watch_min 16_000

  def ref_code, do: @ref_code

  def run do
    :logger.set_primary_config(:level, :error)
    install_signal_handler()

    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    Banner.set_title(@my_project)
    Banner.show_banner(@my_project)

    accounts = load_lines("data.txt")

    cond do
      accounts == [] ->
        red("File data.txt is empty, please add your initData entries")
        System.halt(1)

      true ->
        proxies = load_lines("proxy.txt")
        settings = load_settings()

        loop(accounts, proxies, settings, 1)
    end
  end

  defp loop(accounts, proxies, settings, cycle) do
    yellow("Starting automation cycle number #{cycle}")

    Enum.with_index(accounts)
    |> Enum.each(fn {account, index} ->
      proxy = proxy_for(proxies, index)

      case proxy do
        nil -> :ok
        line -> yellow("Using proxy #{mask_proxy(line)}")
      end

      process_account(account, index, proxy)
    end)

    yellow("All accounts processed for cycle number #{cycle}")

    wait = sleep_seconds(settings)
    countdown(wait, "Next cycle starts in")
    Banner.show_banner(@my_project)
    loop(accounts, proxies, settings, cycle + 1)
  end

  defp process_account(account, index, proxy) do
    label = "account #{index + 1}"

    case call("getState", %{}, account, proxy) do
      {:ok, state} ->
        user = get(state, "user", %{})
        balance = get(state, "balance", 0)

        green(
          "Welcome back #{clean_text(get(user, "firstName", "Unknown"), "user")} with balance #{balance} CRYSTAL"
        )

        force_sub = get(state, "forceSub", %{})

        if get(force_sub, "required", false) and not get(force_sub, "passed", false) do
          yellow("Mandatory channel membership is still pending for #{label}")
        end

        claim_mining(state, account, proxy)
        claim_daily(state, account, proxy)
        solve_combo(state, account, proxy)
        process_bot_tasks(state, account, proxy)
        process_channel_tasks(state, account, proxy)
        process_ads(state, account, proxy)

        :ok

      {:error, reason} ->
        red("Failed to fetch account state for #{label} with #{clean_text(reason, "error")}")
    end
  end

  defp claim_mining(state, account, proxy) do
    mining = get(state, "mining", %{})

    if get(mining, "canClaim", false) do
      with {:ok, gate} <- gate("claimMining", account, proxy),
           :ok <- pace(@ad_gate_wait, "Next claim in"),
           {:ok, data} <- call("claimMining", %{"adGate" => gate}, account, proxy) do
        green(
          "Mining session claimed successfully earning #{format_amount(get(data, "tonAdded", 0))} TON"
        )
      else
        {:error, reason} -> red("Mining claim failed with #{clean_text(reason, "error")}")
      end
    else
      yellow("Mining session is still running, next claim will be available later")
    end
  end

  defp claim_daily(state, account, proxy) do
    daily = get(state, "daily", %{})

    if get(daily, "claimed", false) do
      yellow("Daily bonus already claimed for today")
    else
      with {:ok, gate} <- gate("claimDailyBonus", account, proxy),
           :ok <- pace(@ad_gate_wait, "Next claim in"),
           {:ok, data} <- call("claimDailyBonus", %{"adGate" => gate}, account, proxy) do
        green("Daily bonus claimed successfully earning #{get(data, "shibaAdded", 0)} CRYSTAL")
      else
        {:error, reason} -> red("Daily bonus claim failed with #{clean_text(reason, "error")}")
      end
    end
  end

  defp solve_combo(state, account, proxy) do
    combo = get(state, "combo", %{})

    if get(combo, "solvedToday", false) do
      yellow("Daily combo attempt was already used for today")
    else
      selection = ["c1", "c2", "c3", "c4"]

      with {:ok, gate} <- gate("checkCombo", account, proxy),
           :ok <- pace(@ad_gate_wait, "Next combo in"),
           {:ok, data} <-
             call("checkCombo", %{"selection" => selection, "adGate" => gate}, account, proxy) do
        if get(data, "correct", false) do
          green("Daily combo solved successfully earning #{get(data, "reward", 0)} CRYSTAL")
        else
          yellow("Daily combo answer was wrong, a new attempt is available tomorrow")
        end
      else
        {:error, reason} -> red("Daily combo check failed with #{clean_text(reason, "error")}")
      end
    end
  end

  defp process_bot_tasks(state, account, proxy) do
    tasks = pending_tasks(state, fn task -> bot_task?(task) end)

    case tasks do
      [] ->
        yellow("Every available bot task was already completed")

      list ->
        green("Found #{plural(length(list), "bot task")} to process")

        Enum.each(list, fn task ->
          title = clean_text(get(task, "title", "task"), "task")
          id = get(task, "id")

          case call("startTask", %{"taskId" => id}, account, proxy) do
            {:ok, _} ->
              with {:ok, gate} <- gate("verifyTask", account, proxy),
                   :ok <- pace(@task_wait, "Next task in"),
                   {:ok, data} <-
                     call("verifyTask", %{"taskId" => id, "adGate" => gate}, account, proxy) do
                green(
                  "Task #{title} claimed successfully earning #{get(data, "shibaAdded", 0)} CRYSTAL"
                )
              else
                {:error, reason} ->
                  red("Task #{title} claim failed with #{clean_text(reason, "error")}")
              end

            {:error, reason} ->
              red("Task #{title} start failed with #{clean_text(reason, "error")}")
          end
        end)
    end
  end

  defp process_channel_tasks(state, account, proxy) do
    tasks = pending_tasks(state, fn task -> not bot_task?(task) end)

    case tasks do
      [] ->
        yellow("Every available channel task was already completed")

      list ->
        green("Found #{plural(length(list), "channel task")} to process")
        walk_channels(list, account, proxy, 0, 0)
    end
  end

  defp walk_channels([], _account, _proxy, claimed, skipped) do
    if skipped > 0 do
      yellow(
        "#{plural(skipped, "channel task")} still need a manual channel join before they can pay"
      )
    end

    if claimed == 0 and skipped == 0 do
      yellow("No channel task could be settled on this run")
    end
  end

  defp walk_channels([task | rest], account, proxy, claimed, skipped) do
    title = clean_text(get(task, "title", "task"), "task")
    id = get(task, "id")

    case call("startTask", %{"taskId" => id}, account, proxy) do
      {:ok, _} ->
        with {:ok, gate} <- gate("verifyTask", account, proxy),
             :ok <- pace(@task_wait, "Next task in"),
             {:ok, data} <-
               call("verifyTask", %{"taskId" => id, "adGate" => gate}, account, proxy) do
          green("Task #{title} claimed successfully earning #{get(data, "shibaAdded", 0)} CRYSTAL")
          walk_channels(rest, account, proxy, claimed + 1, skipped)
        else
          {:error, reason} ->
            text = clean_text(reason, "error")

            if join_required?(text) do
              walk_channels(rest, account, proxy, claimed, skipped + 1)
            else
              red("Task #{title} claim failed with #{text}")
              walk_channels(rest, account, proxy, claimed, skipped)
            end
        end

      {:error, reason} ->
        red("Task #{title} start failed with #{clean_text(reason, "error")}")
        walk_channels(rest, account, proxy, claimed, skipped)
    end
  end

  defp process_ads(state, account, proxy) do
    config = get(state, "config", %{})
    settings = get(config, "adCompanies", %{})
    stats = get(state, "stats", %{})
    watched = get(stats, "adsWatchedByCompany", %{})
    daily = get(config, "adDailyLimit", 100)

    if get(stats, "adsWatchedToday", 0) >= daily do
      yellow("Daily advertisement limit was already reached for today")
    else
      names =
        settings
        |> Enum.filter(fn {_name, value} -> get(value, "reward", 0) > 0 end)
        |> Enum.map(fn {name, _value} -> name end)

      run_ad_phase(names, settings, watched, account, proxy, 0, false)
    end
  end

  defp run_ad_phase([], _companies, _watched, _account, _proxy, credited, false) do
    if credited == 0 do
      yellow("No ad reward could be verified from the ad network")
    end
  end

  defp run_ad_phase([], _companies, _watched, _account, _proxy, _credited, true), do: :ok

  defp run_ad_phase([company | rest], companies, watched, account, proxy, credited, blocked) do
    settings = get(companies, company, %{})
    limit = get(settings, "dailyLimit", 0)
    seen = get(watched, company, 0)

    if seen >= limit do
      run_ad_phase(rest, companies, watched, account, proxy, credited, blocked)
    else
      case watch_ad(company, account, proxy) do
        {:ok, data} ->
          green(
            "Ad view #{get(data, "adsWatchedToday", 0)} out of #{limit} was watched and rewarded #{get(data, "shibaAdded", 0)} CRYSTAL"
          )

          run_ad_phase(rest, companies, watched, account, proxy, credited + 1, blocked)

        {:captcha, _} ->
          yellow("Ad reward for #{company} requires a security check and was skipped")
          run_ad_phase(rest, companies, watched, account, proxy, credited, true)

        {:error, reason} ->
          red("Ad reward for #{company} failed with #{clean_text(reason, "error")}")
          run_ad_phase(rest, companies, watched, account, proxy, credited, blocked)
      end
    end
  end

  defp watch_ad(company, account, proxy) do
    started = System.monotonic_time(:millisecond)

    with {:ok, session} <- call("checkSession", %{"company" => company}, account, proxy),
         sid when is_binary(sid) <- get(session, "sid"),
         {:ok, chk} <- pulse(sid, account, proxy, "", [], 0, started),
         :ok <- hold(started, "Next ad in") do
      payload = %{
        "company" => company,
        "sid" => sid,
        "ct" => System.system_time(:millisecond),
        "chk" => chk
      }

      case call("syncBalance", payload, account, proxy) do
        {:ok, data} ->
          {:ok, data}

        {:error, reason} ->
          if captcha_required?(reason), do: {:captcha, reason}, else: {:error, reason}
      end
    else
      nil -> {:error, "ad session was not granted"}
      {:error, reason} -> if captcha_required?(reason), do: {:captcha, reason}, else: {:error, reason}
      _ -> {:error, "ad session was not granted"}
    end
  end

  defp hold(started, label) do
    remaining = @watch_min - (System.monotonic_time(:millisecond) - started)
    pace(div(max(remaining, 0) + 999, 1000), label)
  end

  defp pulse(_sid, _account, _proxy, _prev, acc, count, _started) when count >= @pulse_max,
    do: {:ok, acc}

  defp pulse(sid, account, proxy, prev, acc, count, started) do
    :timer.sleep(@pulse_gap * 1000)

    case call("sessionSync", %{"sid" => sid, "p" => prev}, account, proxy) do
      {:ok, data} ->
        next = get(data, "n", "")
        acc = acc ++ [next]

        if get(data, "left", 0) == 0 do
          {:ok, acc}
        else
          pulse(sid, account, proxy, next, acc, count + 1, started)
        end

      {:error, reason} ->
        if acc == [], do: {:error, reason}, else: {:ok, acc}
    end
  end

  defp pending_tasks(state, predicate) do
    tasks = get(state, "tasks", [])
    completed = get(state, "completedTasks", [])

    Enum.filter(tasks, fn task ->
      id = get(task, "id")
      is_list(completed) and id not in completed and predicate.(task)
    end)
  end

  defp bot_task?(task) do
    category = get(task, "category", "")
    kind = get(task, "kind", "")
    type = get(task, "type", "")

    cond do
      category == "bots" -> true
      kind == "bot" or type == "bot" -> true
      true -> false
    end
  end

  defp join_required?(text) do
    lowered = String.downcase(text)

    String.contains?(lowered, "join the channel") or
      String.contains?(lowered, "join the chat") or
      String.contains?(lowered, "not a member")
  end

  defp captcha_required?(reason) do
    text = to_string(reason) |> String.downcase()

    String.contains?(text, "captcha") or String.contains?(text, "security check")
  end

  defp gate(name, account, proxy) do
    case call("adGateStart", %{"gate" => name}, account, proxy) do
      {:ok, data} ->
        case get(data, "gate") do
          value when is_binary(value) -> {:ok, value}
          _ -> {:error, "ad gate was not granted"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call(action, payload, account, proxy) do
    case request(action, payload, account, proxy) do
      {:ok, body} ->
        case get(body, "success", false) do
          true -> {:ok, get(body, "data", %{})}
          _ -> {:error, get(body, "error", "request was refused")}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(action, payload, init_data, proxy) do
    url = String.to_charlist(@base_url <> "/" <> action)
    body = YuurisanJSON.encode(payload)
    {profile, auth} = proxy_setup(proxy)

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"accept", ~c"*/*"},
      {~c"accept-language", ~c"en-US,en;q=0.9"},
      {~c"origin", ~c"https://crystal-alpha-two.vercel.app"},
      {~c"referer", ~c"https://crystal-alpha-two.vercel.app/"},
      {~c"authorization", String.to_charlist("tma " <> init_data)},
      {~c"user-agent",
       ~c"Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"}
    ]

    options =
      [ssl: [verify: :verify_none], timeout: 30_000, connect_timeout: 15_000] ++ auth

    case :httpc.request(
           :post,
           {url, headers, ~c"application/json", body},
           options,
           [body_format: :binary],
           profile
         ) do
      {:ok, {{_, status, _}, _, response}} ->
        if status >= 200 and status < 300 do
          case YuurisanJSON.decode(response) do
            {:ok, value} -> {:ok, value}
            {:error, _} -> {:error, "response could not be parsed"}
          end
        else
          case YuurisanJSON.decode(response) do
            {:ok, value} -> {:ok, value}
            {:error, _} -> {:error, "server returned status #{status}"}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp proxy_setup(nil), do: {:default, []}

  defp proxy_setup(line) do
    case parse_proxy(line) do
      {host, port, user, pass} -> proxy_profile(host, port, user, pass)
      {host, port} -> proxy_profile(host, port, "", "")
      nil -> {:default, []}
    end
  end

  defp proxy_profile(host, port, user, pass) do
    name = String.to_atom("proxy_#{host}_#{port}")
    address = {String.to_charlist(host), port}

    case :inets.start(:httpc, profile: name) do
      {:ok, _pid} -> :httpc.set_options([proxy: {address, []}, https_proxy: {address, []}], name)
      {:error, {:already_started, _pid}} -> :ok
      _ -> :ok
    end

    case user do
      "" -> {name, []}
      _ -> {name, [proxy_auth: {String.to_charlist(user), String.to_charlist(pass)}]}
    end
  end

  defp parse_proxy(line) do
    value = line |> String.trim() |> String.replace_prefix("http://", "") |> String.replace_prefix("https://", "")
    value = String.replace_prefix(value, "socks5://", "")

    case String.split(value, "@") do
      [credentials, host_part] ->
        case String.split(credentials, ":") do
          [user, pass] -> with_host_port(host_part, user, pass)
          _ -> with_host_port(host_part, "", "")
        end

      [host_part] ->
        case String.split(host_part, ":") do
          [host, port] -> with_port(host, port)
          [host, port, user, pass] -> with_port_creds(host, port, user, pass)
          _ -> nil
        end
    end
  end

  defp with_host_port(host_part, user, pass) do
    case String.split(host_part, ":") do
      [host, port] -> with_port_creds(host, port, user, pass)
      _ -> nil
    end
  end

  defp with_port(host, port) do
    case Integer.parse(port) do
      {number, ""} -> {host, number}
      _ -> nil
    end
  end

  defp with_port_creds(host, port, user, pass) do
    case Integer.parse(port) do
      {number, ""} -> {host, number, user, pass}
      _ -> nil
    end
  end

  defp mask_proxy(line) do
    case parse_proxy(line) do
      {host, port, _user, _pass} -> "http://user:pass@#{mask_host(host)}:#{port}"
      {host, port} -> "http://user:pass@#{mask_host(host)}:#{port}"
      nil -> "http://user:pass@***:***"
    end
  end

  defp mask_host(host) do
    parts = String.split(host, ".")

    case parts do
      [a, _b, _c, d] -> "#{a}*****#{d}"
      _ -> if String.length(host) > 4, do: String.slice(host, 0, 2) <> "*****" <> String.slice(host, -2, 2), else: "***"
    end
  end

  defp proxy_for([], _index), do: nil

  defp proxy_for(proxies, index) do
    Enum.at(proxies, rem(index, length(proxies)))
  end

  defp load_lines(name) do
    case File.read(Path.join(@root, name)) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:error, _} ->
        []
    end
  end

  defp load_settings do
    case File.read(Path.join(@root, "config.json")) do
      {:ok, content} ->
        case YuurisanJSON.decode(content) do
          {:ok, value} -> value
          {:error, _} -> default_settings()
        end

      {:error, _} ->
        settings = default_settings()
        File.write(Path.join(@root, "config.json"), YuurisanJSON.encode(settings))
        settings
    end
  end

  defp default_settings, do: %{"settings" => %{"sleep_seconds" => 3600}}

  defp sleep_seconds(settings) do
    case get(get(settings, "settings", %{}), "sleep_seconds", 3600) do
      value when is_integer(value) and value > 0 -> value
      value when is_float(value) and value > 0 -> trunc(value)
      _ -> 3600
    end
  end

  defp get(map, key, default \\ nil)

  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp get(_other, _key, default), do: default

  defp clean_text(value, fallback) do
    text =
      value
      |> to_string()
      |> String.replace(
        ["[", "]", "|", "#", "!", "@", "$", "%", "^", "&", "*", "(", ")", "-"],
        " "
      )

    case String.split(text) |> Enum.join(" ") do
      "" -> fallback
      cleaned -> cleaned
    end
  end

  defp format_amount(value) when is_float(value) do
    if abs(value) < 1 do
      :erlang.float_to_binary(value, decimals: 8)
    else
      :erlang.float_to_binary(value, decimals: 2)
    end
  end

  defp format_amount(value), do: to_string(value)

  defp install_signal_handler do
    handler = fn ->
      IO.write("\n" <> @red <> @bold <> "Script stopped by user" <> @reset <> "\n")
      System.halt(0)
    end

    try do
      System.trap_signal(:sigint, handler)
    rescue
      _ -> :ok
    end

    try do
      System.trap_signal(:sigterm, handler)
    rescue
      _ -> :ok
    end
  end

  defp plural(count, word) do
    if count == 1 do
      "#{count} #{word}"
    else
      "#{count} #{pluralize(word)}"
    end
  end

  defp pluralize(word) do
    if String.ends_with?(word, "y") do
      String.slice(word, 0, String.length(word) - 1) <> "ies"
    else
      word <> "s"
    end
  end

  defp pace(seconds, label) do
    countdown(seconds, label)
    :ok
  end

  defp countdown(seconds, label) do
    left = max(seconds, 0)

    if left >= 1 do
      width = frame(label, left, 0)
      tick(left, label, width)
    end
  end

  defp tick(0, _label, width) do
    IO.write("\r" <> String.duplicate(" ", width) <> "\r")
  end

  defp tick(left, label, width) do
    width = frame(label, left, width)
    :timer.sleep(1000)
    tick(left - 1, label, width)
  end

  defp frame(label, left, width) do
    text = label <> " " <> format_duration(left)
    IO.write("\r" <> @yellow <> @bold <> text <> @reset)
    max(width, String.length(text))
  end

  defp format_duration(total) do
    days = div(total, 86_400)
    hours = div(rem(total, 86_400), 3600)
    minutes = div(rem(total, 3600), 60)
    seconds = rem(total, 60)

    if days > 0 do
      pad(days) <> ":" <> pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    else
      pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    end
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")

  defp green(message), do: IO.puts(@green <> @bold <> message <> @reset)
  defp yellow(message), do: IO.puts(@yellow <> @bold <> message <> @reset)
  defp red(message), do: IO.puts(@red <> @bold <> message <> @reset)
end

Crystal.run()
