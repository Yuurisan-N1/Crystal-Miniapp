<div align="center">

<img width="100%" alt="header" src="https://capsule-render.vercel.app/api?type=waving&height=210&text=Crystal%20Mining%20Bot&fontAlign=50&fontAlignY=36&fontSize=56&desc=Mining%20Claim%20%7C%20Task%20Automation%20%7C%20Proxy%20Support&descAlign=50&descAlignY=58"/>

<img alt="typing" src="https://readme-typing-svg.demolab.com?font=Inter&size=18&duration=3000&pause=650&center=true&vCenter=true&width=900&lines=Mining+Claim+%2B+Daily+Bonus+Automation;Bot+Tasks+%7C+Channel+Tasks+%7C+Ad+Rewards;Multi-Account+%7C+Sequential+Processing;Proxy+Support+%7C+One+Proxy+Per+Account"/>

<p>
  <img alt="elixir" src="https://img.shields.io/badge/Elixir-1.14%2B-4B275F?logo=elixir&logoColor=white"/>
  <img alt="platform" src="https://img.shields.io/badge/Platform-Crystal%20Mining%20Miniapp-111111"/>
  <img alt="multi-account" src="https://img.shields.io/badge/Multi--Account-Supported-111111"/>
  <img alt="proxy" src="https://img.shields.io/badge/Proxy-Supported-111111"/>
  <img alt="author" src="https://img.shields.io/badge/by-Yuurisandesu-111111"/>
</p>

<p>
  <b>Crystal Mining Bot</b> is a full automation bot for the Crystal Mining Telegram Miniapp.<br/>
  It handles the complete daily cycle: mining claim, daily bonus, daily combo, bot tasks, channel tasks and advertisement rewards, all running automatically across multiple accounts with proxy support and a live countdown between cycles.<br/>
  Built and distributed by <b>Yuurisandesu</b>.
</p>

</div>

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Bot](#running-the-bot)
- [Features](#features)
- [File Structure](#file-structure)
- [Disclaimer](#disclaimer)

---

## Requirements

- Elixir `1.14+` with Erlang/OTP `25+`
- Git

---

## Installation

### Install Elixir

Elixir runs on the Erlang virtual machine, so **Erlang/OTP is required** Elixir cannot run without
it. Every package manager below installs Erlang/OTP for you as a dependency. The only path that needs
a separate Erlang step is the Windows manual installer (see below).

**Windows:**

*Option A package manager (recommended, installs Erlang automatically):*

```cmd
winget install Elixir.Elixir
```

*Option B manual installer (two installers, in this order):*

1. Download and run the **Erlang/OTP installer** from https://www.erlang.org/downloads
2. Run `erl -s halt` to check which OTP version you got
3. Download the **Elixir installer built for that exact OTP** from https://elixir-lang.org/install.html (`elixir-otp-<N>.exe`) and run it

Then open Command Prompt and verify:

```cmd
elixir --version
```

The output prints both versions, for example `Elixir 1.14.0 (compiled with Erlang/OTP 25)`.

**Linux (Ubuntu / Debian):**

```bash
sudo apt-get update
sudo apt-get install -y elixir
elixir --version
```

**macOS:**

```bash
brew install elixir
elixir --version
```

> If you do not have Homebrew, install it first from https://brew.sh

**Termux (Android):**

```bash
pkg update && pkg upgrade -y
pkg install elixir -y
elixir --version
```

> If the `elixir` package is not available in your Termux repository, install an Ubuntu environment first with `pkg install proot-distro`, then `proot-distro install ubuntu`, then `proot-distro login ubuntu` and run the Linux command above inside it.

---

### Clone and Install

**Clone the repository:**

```bash
git clone https://github.com/Yuurisan-N1/CrystalMining-Miniapp.git
cd CrystalMining-Miniapp
```

**Install dependencies:**

This bot uses only the Elixir standard library, so there is nothing to install. Erlang/OTP was already installed by the step above.

---

## Configuration

### 1. Accounts (data.txt)

Fill `data.txt` with Telegram WebApp `initData` for each account, one per line:

```
user=%7B%22id%22...&hash=abc123
user=%7B%22id%22...&hash=def456
```

> `initData` can be obtained from the browser DevTools when opening the Crystal Mining Miniapp on Telegram Web.

### 2. Proxy (proxy.txt)

Fill `proxy.txt` with proxies, one per line (optional, leave empty to run without proxy):

```
host:port
host:port:user:pass
http://user:pass@host:port
```

Proxies are assigned to accounts by index in round-robin order.

### 3. Bot Settings (config.json)

`sleep_seconds` controls how many seconds the bot waits between cycles. If `config.json` is missing, it is created automatically with a default of `3600` seconds.

---

## Running the Bot

**Linux / macOS:**

```bash
elixir --erl "+Bd" bot.exs
```

**Windows:**

```cmd
elixir --erl "+Bc" bot.exs
```

Or just double click `run_pc.bat`, which runs the Windows command above.

---

## Features

### Account State
At the start of every account the bot reads the full account snapshot and logs the account name together with the current crystal balance. When the miniapp still requires membership in its announcement channels, that is reported so it can be completed by hand.

### Mining Claim
When the mining session has finished, the bot claims the pending reward and logs the exact amount of TON that was credited by the server.

### Daily Bonus
Once per day the bot claims the daily bonus and logs the crystal amount the server credited. A bonus that was already taken is reported as such.

### Daily Combo
Once per day the bot submits a combination attempt. The server decides the correct answer, and the result is logged either as a solved combo with its reward or as an attempt that was used up.

### Bot Tasks
Every partner task that only requires opening another miniapp is processed automatically: the bot starts the task, waits the task timer, then settles it. Each settled task is logged with the crystal amount the server credited.

### Channel Tasks
Tasks that require membership in a Telegram channel are processed the same way. A task whose channel has not been joined yet is reported instead of being counted as a reward, so the log always matches the server balance.

### Advertisement Rewards
The bot watches the available advertisement placements and claims the reward for each one, logging the running advertisement counter and the crystals credited. When the miniapp asks for a security check that only a real device can complete, the bot reports it and moves on without inventing a reward.

### Multi Account
All accounts in `data.txt` are processed sequentially within every cycle. Each account is logged with its index, its name and its balance. The cycle number is tracked and logged at the start of each round.

### Proxy Support
Proxies are loaded from `proxy.txt` and assigned to accounts by position in round-robin order. Proxy credentials are masked in log output. Running without proxies is fully supported.

### Auto Countdown
Every wait inside the cycle displays a live `HH:MM:SS` countdown in place, and after all accounts complete a cycle the bot shows a countdown until the next cycle starts.

---

## File Structure

```text
CrystalMining-Miniapp/
├── bot.exs         # Main bot, full daily cycle automation
├── config.json     # Sleep duration between cycles
├── data.txt        # Account initData, one per line
├── proxy.txt       # Proxy list, one per line (optional)
├── run_pc.bat      # Launcher for Windows
├── LICENSE         # License file
└── utils/
    ├── banner.ex   # Banner display on startup
    └── json.ex     # JSON encoder and decoder
```

---

## Disclaimer

This tool is built for educational and technical exploration purposes. Use it wisely and at your own responsibility.

---

<div align="center">
<img width="100%" alt="footer" src="https://capsule-render.vercel.app/api?type=waving&height=120&section=footer"/>
</div>